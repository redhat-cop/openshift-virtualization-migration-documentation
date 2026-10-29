'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const repoRoot = path.resolve(__dirname, '..')
const siteDir = path.join(repoRoot, 'build/site')

function readSite (rel) {
  const file = path.join(siteDir, rel)
  assert.ok(fs.existsSync(file), `build the site before running this test: missing ${rel}`)
  return fs.readFileSync(file, 'utf8')
}

function jobBlock (workflow, name) {
  const marker = `\n  ${name}:`
  const start = workflow.indexOf(marker)
  assert.ok(start >= 0, `missing job ${name}`)
  const rest = workflow.slice(start + 1)
  const next = rest.search(/\n {2}[a-z0-9-]+:\n/)
  return next === -1 ? rest : rest.slice(0, next)
}

describe('v2 preview review', () => {
  const preview = fs.readFileSync(path.join(repoRoot, '.github/workflows/preview.yml'), 'utf8')
  const build = jobBlock(preview, 'build')
  const deploy = jobBlock(preview, 'deploy')

  it('lets only the deploy job write, and skips deploy when the build fails', () => {
    const header = preview.slice(0, preview.indexOf('\njobs:'))
    assert.match(header, /contents: read/)
    assert.doesNotMatch(header, /contents: write/)
    assert.doesNotMatch(header, /pull-requests: write/)
    assert.match(build, /github\.event\.action != 'closed'/)
    assert.doesNotMatch(build, /contents: write/)
    assert.doesNotMatch(build, /pull-requests: write/)
    assert.match(deploy, /actions: read/)
    assert.match(deploy, /contents: write/)
    assert.match(deploy, /pull-requests: write/)
    assert.match(deploy, /needs\.build\.result == 'success'/)
    assert.doesNotMatch(deploy, /needs\.build\.result == 'failure'/)
    assert.match(build, /touch build\/site\/\.nojekyll/)
    const uploadAt = build.indexOf('- name: Upload site')
    assert.ok(uploadAt >= 0, 'missing Upload site step')
    assert.match(build.slice(uploadAt), /include-hidden-files:\s*true/)
  })

  it('still removes the preview when the pull request is closed', () => {
    assert.match(deploy, /github\.event\.action == 'closed'/)
    const checkoutAt = deploy.indexOf('- name: Checkout repository')
    const downloadAt = deploy.indexOf('- name: Download site')
    assert.ok(checkoutAt >= 0 && downloadAt > checkoutAt, 'missing Checkout repository step')
    assert.match(deploy.slice(checkoutAt, downloadAt), /if: github\.event\.action != 'closed'/)
    assert.match(deploy, /Download site[\s\S]*if: github\.event\.action != 'closed'/)
    assert.match(deploy, /Deploy preview/)
    const deployStep = deploy.slice(deploy.indexOf('- name: Deploy preview'))
    assert.doesNotMatch(deployStep, /if:/)
  })

  it('redirects a removed role URL to Automation reference and keeps the eight roles', () => {
    const indexAdoc = fs.readFileSync(path.join(repoRoot, 'v2/modules/roles/pages/index.adoc'), 'utf8')
    const aliasLine = indexAdoc.match(/^:page-aliases:\s*(.+)$/m)
    assert.ok(aliasLine, 'expected :page-aliases: on Automation reference')
    const aliases = aliasLine[1].split(',').map((spec) => spec.trim().replace(/\.adoc$/, '')).filter(Boolean)
    assert.ok(aliases.includes('mtv_migrate'))
    for (const alias of aliases) {
      const redirect = readSite(path.join('v2', 'roles', `${alias}.html`))
      assert.match(redirect, /location="index\.html"/, alias)
      assert.match(redirect, /url=index\.html/, alias)
    }
    const reference = readSite(path.join('v2', 'roles', 'index.html'))
    assert.match(reference, /Automation reference/)
    assert.doesNotMatch(reference, /Redirect Notice/)
    const appendix = fs.readFileSync(path.join(repoRoot, 'v2/modules/appendix/nav.adoc'), 'utf8')
    const roles = [...appendix.matchAll(/xref:roles:([a-z0-9_]+)\.adoc/g)].map((match) => match[1])
    assert.deepEqual(roles, [
      'index',
      'aap_seed',
      'mtv_hook_invoke_aap',
      'mtv_maps',
      'mtv_plans',
      'mtv_provider',
      'mtv_query_inventory',
      'utility_aap_deploy',
      'utility_openshift_target_credential',
    ])
  })

  it('publishes borrowed images from v2', () => {
    const home = readSite(path.join('v2', 'index.html'))
    assert.match(home, /<img src="_images\/mf-overview\.png"/)
    assert.ok(fs.existsSync(path.join(siteDir, 'v2', '_images', 'mf-overview.png')))
    const plans = readSite(path.join('v2', 'journey', 'archive-plan.html'))
    assert.match(plans, /<img src="_images\/openshift-mtv-plans\.png"/)
    assert.ok(fs.existsSync(path.join(siteDir, 'v2', 'journey', '_images', 'openshift-mtv-plans.png')))
    const rhdp = readSite(path.join('v2', 'journey', 'setup-rhdp.html'))
    assert.match(rhdp, /<img src="_images\/rhdp-service-details\.png"/)
    const journeyImages = {
      'create-maps.html': ['openshift-mtv-networkmaps.png'],
      'create-providers.html': ['openshift-mtv-providers.png'],
      'execute-migration.html': ['openshift-mtv-plan-virtual-machines.png', 'openshift-mtv-completed-plan.png'],
      'prepare-migration-wave.html': ['openshift-mtv-plans.png'],
      'verify-migration.html': ['openshift-mtv-completed-plan.png', 'openshift-migrated-vm.png'],
    }
    const journeyPages = []
    for (const [page, images] of Object.entries(journeyImages)) {
      const html = readSite(path.join('v2', 'journey', page))
      journeyPages.push(html)
      for (const image of images) {
        assert.match(html, new RegExp(`<img src="_images/${image.replace(/\./g, '\\.')}"`), page)
        assert.ok(fs.existsSync(path.join(siteDir, 'v2', 'journey', '_images', image)), image)
      }
    }
    for (const html of [home, plans, rhdp, ...journeyPages]) {
      const sources = [...html.matchAll(/<img src="([^"]+)"/g)].map((match) => match[1])
      assert.ok(sources.length > 0)
      for (const source of sources) assert.doesNotMatch(source, /guides/)
    }
  })

  it('warns that skipping TLS verification is lab-only and keeps the command', () => {
    const page = readSite(path.join('v2', 'journey', 'setup-existing-ocp.html'))
    assert.match(page, /admonitionblock warning[\s\S]*K8S_AUTH_VERIFY_SSL=false[\s\S]*lab only, not production/)
    assert.match(page, /--senv=K8S_AUTH_VERIFY_SSL=false \\/)
  })
})
