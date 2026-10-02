'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const os = require('node:os')

const repoRoot = path.resolve(__dirname, '..')
const navFilter = require(path.join(repoRoot, 'supplemental-ui/js/nav-filter.js'))
const searchEmpty = require(path.join(repoRoot, 'supplemental-ui/js/search-empty.js'))

const journeyNav = [
  {
    label: 'Preparing your environment',
    children: [
      { label: 'Prerequisites' },
      { label: 'Migration Factory prerequisites' },
      { label: 'OpenShift' },
    ],
  },
  { label: 'Seeding Ansible Automation Platform' },
  {
    label: 'Performing a migration wave',
    children: [
      { label: 'Introduction to migration waves' },
      { label: 'Configure providers' },
      { label: 'Configure storage and network maps' },
      { label: 'Defining a migration wave' },
      { label: 'Preparing VMs for migration' },
    ],
  },
  { label: 'Support' },
]

function visibleLabels (result) {
  const labels = []
  function walk (nodes) {
    for (const node of nodes) {
      if (!node.visible) continue
      labels.push(node.label)
      walk(node.children || [])
    }
  }
  walk(result.nodes)
  return labels
}

function expandedLabels (result) {
  const labels = []
  function walk (nodes) {
    for (const node of nodes) {
      if (node.visible && node.expanded) labels.push(node.label)
      if (node.visible) walk(node.children || [])
    }
  }
  walk(result.nodes)
  return labels
}

function mockEl (tag, attrs, children) {
  attrs = attrs || {}
  const classSet = new Set(String(attrs.className || '').split(/\s+/).filter(Boolean))
  const data = {}
  if (attrs.id) data.id = attrs.id
  const el = {
    tagName: String(tag).toUpperCase(),
    children: [],
    parentElement: null,
    textContent: attrs.textContent || '',
    classList: {
      contains (name) { return classSet.has(name) },
      add (name) { classSet.add(name) },
      remove (name) { classSet.delete(name) },
    },
    getAttribute (name) { return Object.prototype.hasOwnProperty.call(data, name) ? data[name] : null },
    setAttribute (name, value) { data[name] = String(value) },
    hasAttribute (name) { return Object.prototype.hasOwnProperty.call(data, name) },
    removeAttribute (name) { delete data[name] },
    querySelector (selector) { return el.querySelectorAll(selector)[0] || null },
    querySelectorAll (selector) { return queryAll(el, selector) },
  }
  ;(children || []).forEach((child) => {
    child.parentElement = el
    el.children.push(child)
  })
  return el
}

function queryAll (root, selector) {
  const parts = selector.split(',').map((part) => part.trim())
  if (parts.length > 1) {
    const seen = []
    parts.forEach((part) => {
      queryAll(root, part).forEach((node) => {
        if (!seen.includes(node)) seen.push(node)
      })
    })
    return seen
  }
  if (selector.startsWith(':scope > ')) {
    const childSel = selector.slice(':scope > '.length)
    return root.children.filter((child) => matches(child, childSel))
  }
  const found = []
  function walk (node, isRoot) {
    if (!isRoot && matches(node, selector)) found.push(node)
    ;(node.children || []).forEach((child) => walk(child, false))
  }
  walk(root, true)
  return found
}

function matches (node, selector) {
  if (selector.startsWith('#')) return node.getAttribute('id') === selector.slice(1)
  if (selector.startsWith('.')) return node.classList.contains(selector.slice(1))
  return false
}

function navItem (label, opts) {
  opts = opts || {}
  const labelEl = mockEl(opts.href ? 'a' : 'span', {
    className: opts.href ? 'nav-link' : 'nav-text',
    textContent: label,
  })
  const kids = [labelEl]
  if (opts.children && opts.children.length) {
    kids.push(mockEl('ul', { className: 'nav-list' }, opts.children))
  }
  return mockEl('li', { className: 'nav-item' }, kids)
}

describe('left-nav filter', () => {
  it('shows nested matches, expands ancestors, and hides non-matches', () => {
    const result = navFilter.filterTree(journeyNav, 'maps')
    assert.equal(result.hasMatches, true)
    const labels = visibleLabels(result)
    assert.deepEqual(labels, ['Performing a migration wave', 'Configure storage and network maps'])
    assert.deepEqual(expandedLabels(result), ['Performing a migration wave'])
    assert.ok(!labels.includes('Support'))
    assert.ok(!labels.includes('Configure providers'))
  })

  it('is case-insensitive on visible nav labels', () => {
    const result = navFilter.filterTree(journeyNav, 'MAPS')
    assert.ok(visibleLabels(result).includes('Configure storage and network maps'))
  })

  it('reports no matches and hides the tree when nothing matches', () => {
    const result = navFilter.filterTree(journeyNav, 'no-such-nav-label-xyz')
    assert.equal(result.hasMatches, false)
    assert.deepEqual(visibleLabels(result), [])
  })

  it('restores the full tree when the filter is cleared', () => {
    navFilter.filterTree(journeyNav, 'maps')
    const restored = navFilter.filterTree(journeyNav, '   ')
    assert.equal(restored.hasMatches, true)
    assert.ok(visibleLabels(restored).includes('Preparing your environment'))
    assert.ok(visibleLabels(restored).includes('Configure storage and network maps'))
    assert.ok(visibleLabels(restored).includes('Support'))
    assert.deepEqual(expandedLabels(restored), [])
  })

  it('marks non-matches is-filtered-out and expands ancestor items', () => {
    const maps = navItem('Configure storage and network maps', { href: true })
    const providers = navItem('Configure providers', { href: true })
    const wave = navItem('Performing a migration wave', {
      children: [maps, providers],
    })
    const support = navItem('Support', { href: true })
    const menu = mockEl('nav', { className: 'nav-menu' }, [
      mockEl('ul', { className: 'nav-list' }, [wave, support]),
    ])

    navFilter.applyNavFilter(menu, 'maps')

    assert.equal(maps.classList.contains('is-filtered-out'), false)
    assert.equal(wave.classList.contains('is-filtered-out'), false)
    assert.equal(wave.classList.contains('is-active'), true)
    assert.equal(providers.classList.contains('is-filtered-out'), true)
    assert.equal(support.classList.contains('is-filtered-out'), true)
  })
})

describe('empty search query', () => {
  it('treats empty and whitespace queries as no search', () => {
    assert.equal(searchEmpty.isEmptySearchQuery(''), true)
    assert.equal(searchEmpty.isEmptySearchQuery('   '), true)
    assert.equal(searchEmpty.isEmptySearchQuery('providers'), false)
  })

  it('collapses a whitespace-only #search-input value to empty', () => {
    const listeners = {}
    const input = {
      id: 'search-input',
      value: '   ',
      addEventListener (type, fn) {
        listeners[type] = fn
      },
    }
    searchEmpty.bindSearchEmptyQuery({
      getElementById (id) {
        return id === 'search-input' ? input : null
      },
    })
    listeners.input()
    assert.equal(input.value, '')
  })
})

describe('build wiring', () => {
  it('registers Lunr and supplemental UI in the playbook', () => {
    const playbook = fs.readFileSync(path.join(repoRoot, 'antora-playbook.yml'), 'utf8')
    assert.match(playbook, /require:\s*'@antora\/lunr-extension'/)
    assert.match(playbook, /supplemental_files:\s*.\/supplemental-ui/)
  })

  it('excludes v1 from Lunr via noindex on guides', () => {
    const descriptor = fs.readFileSync(path.join(repoRoot, 'guides/antora.yml'), 'utf8')
    assert.match(descriptor, /noindex:\s*'@'/)
    const v2 = fs.readFileSync(path.join(repoRoot, 'v2/antora.yml'), 'utf8')
    assert.doesNotMatch(v2, /noindex:/)
  })

  it('installs Lunr in lab-build and both GitHub Antora workflows', () => {
    const lab = fs.readFileSync(path.join(repoRoot, 'utilities/lab-build'), 'utf8')
    assert.match(lab, /@antora\/lunr-extension/)
    const publish = fs.readFileSync(path.join(repoRoot, '.github/workflows/publish-github-pages.yml'), 'utf8')
    const preview = fs.readFileSync(path.join(repoRoot, '.github/workflows/preview.yml'), 'utf8')
    assert.match(publish, /npm i antora @antora\/lunr-extension/)
    assert.match(preview, /npm i antora @antora\/lunr-extension/)
  })

  it('keeps the existing v2 journey grouping', () => {
    const nav = fs.readFileSync(path.join(repoRoot, 'v2/modules/journey/nav.adoc'), 'utf8')
    assert.match(nav, /^\* xref:setup-environment\.adoc\[Preparing your environment\]/m)
    assert.match(nav, /^\* xref:seed-aap\.adoc\[Seeding Ansible Automation Platform\]/m)
    assert.match(nav, /^\* Performing a migration wave/m)
    assert.match(nav, /^\* Performing a migration/m)
    assert.match(nav, /^\* Post migration/m)
    assert.match(nav, /^\* xref:scaling-the-automation\.adoc\[Updating the topology\]/m)
    assert.match(nav, /^\* Day 2 operations/m)
    assert.match(nav, /^\* Enablement/m)
    assert.match(nav, /xref:setup-rhdp\.adoc\[RHDP workshop\]/)
  })
})

function parseSearchIndex (indexSrc) {
  const prefix = 'antoraSearch.initSearch(lunr, '
  assert.ok(indexSrc.startsWith(prefix), 'search-index.js must call antoraSearch.initSearch')
  const json = indexSrc.slice(prefix.length).replace(/\)\s*$/, '')
  return JSON.parse(json)
}

function loadLunr () {
  return require('lunr')
}

function searchDocuments (lunr, data, query) {
  const index = lunr.Index.load(data.index)
  return index.search(query).map((hit) => {
    const docId = String(hit.ref).split('-')[0]
    return data.store.documents[docId]
  }).filter(Boolean)
}

describe('built site search and chrome', () => {
  const siteDir = path.join(repoRoot, 'build/site')
  const v2Page = path.join(siteDir, 'v2/index.html')

  it('exposes navbar search and a left-nav filter on v2 pages', () => {
    assert.ok(fs.existsSync(v2Page), 'build the site before running this test')
    const html = fs.readFileSync(v2Page, 'utf8')
    assert.match(html, /id="search-input"/)
    assert.match(html, /id="nav-filter-input"/)
    assert.match(html, /nav-filter\.js/)
    assert.match(html, /Development Guides/)
    assert.match(html, /Migration Factory/)
  })

  it('returns matching v2 journey pages and those URLs exist', () => {
    const indexSrc = fs.readFileSync(path.join(siteDir, 'search-index.js'), 'utf8')
    const lunr = loadLunr()
    const data = parseSearchIndex(indexSrc)
    const hits = searchDocuments(lunr, data, 'providers')
    assert.ok(hits.length > 0, 'expected v2 providers hits')
    for (const hit of hits) {
      assert.equal(hit.component, 'v2')
      assert.doesNotMatch(String(hit.url), /\/guides\//)
      const rel = String(hit.url).replace(/^\//, '')
      const pageFile = path.join(siteDir, rel)
      assert.ok(fs.existsSync(pageFile), `result URL must exist on disk: ${rel}`)
    }
    assert.ok(hits.some((hit) => /create-providers|provider/i.test(`${hit.url} ${hit.title}`)))
  })

  it('omits v1-only RHDP pages from results', () => {
    const indexSrc = fs.readFileSync(path.join(siteDir, 'search-index.js'), 'utf8')
    const lunr = loadLunr()
    const data = parseSearchIndex(indexSrc)
    const hits = searchDocuments(lunr, data, 'haproxy-user1')
    assert.equal(hits.length, 0)
    for (const doc of Object.values(data.store.documents)) {
      assert.equal(doc.component, 'v2')
    }
  })

  it('shows no results for unknown queries and does not search empty input', () => {
    const indexSrc = fs.readFileSync(path.join(siteDir, 'search-index.js'), 'utf8')
    const searchUi = fs.readFileSync(path.join(siteDir, '_/js/search-ui.js'), 'utf8')
    const lunr = loadLunr()
    const data = parseSearchIndex(indexSrc)
    const hits = searchDocuments(lunr, data, 'zxqwvutsyqjklmnb')
    assert.equal(hits.length, 0)
    assert.match(searchUi, /No results found for query/)
    assert.match(searchUi, /if \(!query\) return clearSearchResults\(\)/)
    const html = fs.readFileSync(v2Page, 'utf8')
    assert.match(html, /search-empty\.js/)
  })
})

describe('build fails without Lunr', () => {
  it('fails the Antora job when the extension is not installed', { timeout: 120000 }, () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'antora-no-lunr-'))
    const install = spawnSync('npm', ['i', '--no-fund', '--no-audit', 'antora'], {
      cwd: tmp,
      encoding: 'utf8',
    })
    if (install.status !== 0) {
      assert.fail(install.stderr || install.stdout || 'npm i antora failed')
    }
    const localLunr = path.join(repoRoot, 'node_modules/@antora/lunr-extension')
    const hiddenLunr = `${localLunr}.hidden-for-test`
    if (fs.existsSync(localLunr)) fs.renameSync(localLunr, hiddenLunr)
    try {
      const antoraBin = path.join(tmp, 'node_modules/.bin/antora')
      const result = spawnSync(antoraBin, ['antora-playbook.yml'], {
        cwd: repoRoot,
        encoding: 'utf8',
        env: {
          ...process.env,
          NODE_PATH: path.join(tmp, 'node_modules'),
        },
      })
      assert.notEqual(result.status, 0)
      const output = `${result.stderr || ''}\n${result.stdout || ''}`
      assert.match(output, /lunr-extension|Cannot find module/i)
    } finally {
      if (fs.existsSync(hiddenLunr)) fs.renameSync(hiddenLunr, localLunr)
    }
  })
})
