'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const repoRoot = path.resolve(__dirname, '..')
const siteDir = path.join(repoRoot, 'build/site')
const personaTitles = ['Consultant', 'AAP administrator', 'Developer', 'Partner']

function readHtml (rel) {
  const file = path.join(siteDir, rel)
  assert.ok(fs.existsSync(file), `build the site before running this test: missing ${rel}`)
  return fs.readFileSync(file, 'utf8')
}

function articleHtml (html) {
  const match = html.match(/<article class="doc">([\s\S]*?)<\/article>/)
  assert.ok(match, 'expected article.doc')
  return match[1]
}

function navMenuHtml (html) {
  const match = html.match(/<nav class="nav-menu">([\s\S]*?)<\/nav>/)
  assert.ok(match, 'expected nav.nav-menu')
  return match[1]
}

function noteBlocks (article) {
  const blocks = []
  const parts = article.split('<div class="admonitionblock note">')
  for (let i = 1; i < parts.length; i++) {
    const contentTd = parts[i].match(/<td class="content">([\s\S]*?)<\/td>/)
    if (!contentTd) continue
    const titleMatch = contentTd[1].match(/<div class="title">([^<]*)<\/div>/)
    const paragraphs = [...contentTd[1].matchAll(/<p>([\s\S]*?)<\/p>/g)].map((m) => m[1])
    const paragraphHtml = paragraphs[0] || ''
    const hrefs = []
    const hrefRe = /<a href="([^"]*)" class="xref page">([^<]*)<\/a>/g
    let m
    while ((m = hrefRe.exec(paragraphHtml)) !== null) {
      hrefs.push({ href: m[1], text: m[2] })
    }
    blocks.push({
      title: titleMatch ? titleMatch[1].trim() : '',
      paragraphCount: paragraphs.length,
      paragraphText: paragraphHtml.replace(/<[^>]+>/g, ''),
      paragraphHtml,
      hrefs,
    })
  }
  return blocks
}

function noteByTitle (notes, title) {
  const note = notes.find((block) => block.title === title)
  assert.ok(note, `expected a [NOTE] titled ${title}`)
  return note
}

function navLabels (navHtml) {
  const labels = []
  const re = /<(?:a class="nav-link"[^>]*>|span class="nav-text">)([^<]*)/g
  let m
  while ((m = re.exec(navHtml)) !== null) {
    labels.push(m[1].trim())
  }
  return labels
}

function assertPageExists (hrefFromV2Index) {
  const file = path.join(siteDir, 'v2', hrefFromV2Index)
  assert.ok(fs.existsSync(file), `xref target must exist on disk: ${hrefFromV2Index}`)
}

describe('persona callouts on the v2 introduction', () => {
  const v2Index = path.join('v2', 'index.html')

  it('shows Who this journey is for with four titled [NOTE] callouts', () => {
    const article = articleHtml(readHtml(v2Index))
    assert.match(article, /<h2 id="who-this-journey-is-for">[\s\S]*?Who this journey is for<\/h2>/)
    const notes = noteBlocks(article)
    assert.deepEqual(notes.map((note) => note.title), personaTitles)
    for (const note of notes) {
      assert.equal(note.paragraphCount, 1, `${note.title} must be one short paragraph`)
      assert.ok(note.paragraphText.length > 0)
    }
  })

  it('sends the Consultant note to Preparing your environment', () => {
    const notes = noteBlocks(articleHtml(readHtml(v2Index)))
    const note = noteByTitle(notes, 'Consultant')
    assert.ok(note.hrefs.some((link) =>
      link.href === 'journey/setup-environment.html' &&
      link.text === 'Preparing your environment'))
    assertPageExists('journey/setup-environment.html')
  })

  it('sends the AAP administrator note through the same journey and to Day 2 operations', () => {
    const notes = noteBlocks(articleHtml(readHtml(v2Index)))
    const note = noteByTitle(notes, 'AAP administrator')
    assert.match(note.paragraphText, /migration journey/i)
    assert.ok(note.hrefs.some((link) =>
      link.href === 'journey/setup-environment.html' &&
      link.text === 'Preparing your environment'))
    assert.ok(note.hrefs.some((link) =>
      link.href === 'journey/day2-overview.html' &&
      link.text === 'Day 2 operations'))
    assertPageExists('journey/day2-overview.html')
  })

  it('points the Developer note at Automation reference and this docs repo', () => {
    const notes = noteBlocks(articleHtml(readHtml(v2Index)))
    const note = noteByTitle(notes, 'Developer')
    assert.match(note.paragraphText, /contribute/i)
    assert.match(note.paragraphHtml, /redhat-cop\/openshift-virtualization-migration-documentation/)
    assert.ok(note.hrefs.some((link) =>
      link.href === 'roles/index.html' &&
      link.text === 'Automation reference'))
    assertPageExists('roles/index.html')
  })

  it('sends the Partner note along the consultant journey with no fork or logo steps', () => {
    const notes = noteBlocks(articleHtml(readHtml(v2Index)))
    const note = noteByTitle(notes, 'Partner')
    assert.ok(note.hrefs.some((link) =>
      link.href === 'journey/setup-environment.html' &&
      link.text === 'Preparing your environment'))
    assert.doesNotMatch(note.paragraphText, /\bfork\b|\blogos?\b/i)
  })
})

describe('persona callouts stay off the journey nav and pages', () => {
  it('keeps five collapsible sections + Appendix and adds no persona nav trees', () => {
    const navAdoc = fs.readFileSync(path.join(repoRoot, 'v2/modules/journey/nav.adoc'), 'utf8')
    assert.match(navAdoc, /^\* Prepare/m)
    assert.match(navAdoc, /^\*\* xref:setup-environment\.adoc\[Preparing your environment\]/m)
    assert.match(navAdoc, /^\*\* xref:seed-aap\.adoc\[Seeding Ansible Automation Platform\]/m)
    assert.match(navAdoc, /^\* Migrate/m)
    assert.match(navAdoc, /^\*\* Performing a migration wave/m)
    assert.match(navAdoc, /^\*\* Performing a migration/m)
    assert.match(navAdoc, /^\*\* Post migration/m)
    assert.match(navAdoc, /^\*\* xref:scaling-the-automation\.adoc\[Updating the topology\]/m)
    assert.match(navAdoc, /^\* Operate/m)
    assert.match(navAdoc, /^\*\* Day 2 operations/m)
    assert.match(navAdoc, /^\*\* Enablement/m)
    assert.match(navAdoc, /xref:setup-rhdp\.adoc\[RHDP workshop\]/)
    for (const title of personaTitles) {
      assert.doesNotMatch(navAdoc, new RegExp(title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
    }

    const appendixNav = fs.readFileSync(path.join(repoRoot, 'v2/modules/appendix/nav.adoc'), 'utf8')
    assert.match(appendixNav, /^\* Appendix/m)
    assert.match(appendixNav, /xref:roles:index\.adoc\[Automation reference\]/)
    assert.match(appendixNav, /xref:support:channels\.adoc\[Support\]/)

    const antora = fs.readFileSync(path.join(repoRoot, 'v2/antora.yml'), 'utf8')
    assert.match(antora, /nav:\n(?: {2}- modules\/(?:ROOT|journey|appendix)\/nav\.adoc\n){3}$/)

    const labels = navLabels(navMenuHtml(readHtml(path.join('v2', 'index.html'))))
    assert.ok(labels.includes('Preparing your environment'))
    assert.ok(labels.includes('Automation reference'))
    assert.ok(labels.includes('Support'))
    for (const title of personaTitles) {
      assert.ok(!labels.includes(title), `left nav must not add a ${title} entry`)
    }
  })

  it('does not add the four persona admonition titles on Preparing your environment', () => {
    const article = articleHtml(readHtml(path.join('v2', 'journey', 'setup-environment.html')))
    const titles = noteBlocks(article).map((note) => note.title)
    for (const title of personaTitles) {
      assert.ok(!titles.includes(title), `setup-environment must not title a [NOTE] ${title}`)
    }
  })
})
