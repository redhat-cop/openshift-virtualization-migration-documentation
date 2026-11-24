'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const repoRoot = path.resolve(__dirname, '..')

const forbidden = /bitwarden|service-now|servicenow|enterprise\.slack|issues\.redhat|forms\.gle|docs\.google|onboarding form|forum-virt-migration|shebi\.eu|shebi lab|v2-lab-shebi|KB0010984|vault\.bitwarden|23\.88\.73\.30|192\.168\.50\.145|192\.168\.50\.206|id_rsa_open|jira|slack|google group|red hat hub/i

function walk (dir, acc) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'build' || entry.name === '.git') continue
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(full, acc)
    else if (/\.(adoc|md|yml|example|sh)$/.test(entry.name)) acc.push(full)
  }
  return acc
}

function read (rel) {
  return fs.readFileSync(path.join(repoRoot, rel), 'utf8')
}

function httpUrls (body) {
  return (body.match(/https?:\/\/[^\s\][)<>"]+/g) || []).flatMap((raw) => {
    try {
      return [new URL(raw)]
    } catch {
      return []
    }
  })
}

function linksTo (body, expected) {
  const target = new URL(expected)
  return httpUrls(body).some((url) =>
    url.protocol === target.protocol &&
    url.hostname === target.hostname &&
    url.pathname === target.pathname
  )
}

describe('public docs omit internal tool and lab-host references', () => {
  it('does not name internal tools, forms, or the lab hosts in published sources', () => {
    const hits = []
    const roots = ['guides', 'v2', 'utilities', 'CONTRIBUTING.md'].map((rel) => path.join(repoRoot, rel))
    const files = []
    for (const root of roots) {
      if (fs.statSync(root).isDirectory()) walk(root, files)
      else files.push(root)
    }
    for (const file of files) {
      const rel = path.relative(repoRoot, file)
      if (rel === 'guides/modules/appendix/pages/maintainer.adoc') continue
      const body = fs.readFileSync(file, 'utf8')
      if (forbidden.test(body)) hits.push(rel)
    }
    assert.deepEqual(hits, [])
  })

  it('keeps maintainer attribution', () => {
    assert.match(read('guides/modules/appendix/pages/maintainer.adoc'), /shebi@redhat\.com/)
  })

  it('points support, home, and the v2 index at GitHub issues', () => {
    const channels = read('v2/modules/support/pages/channels.adoc')
    assert.match(channels, /^\* Issues: link:https:\/\/github\.com\/redhat-cop\/openshift_virtualization_migration\/issues\[GitHub Issues\]/m)
    assert.doesNotMatch(channels, /Jira:/)
    assert.match(channels, /openshift-virtualization-migration-documentation/)

    for (const page of ['guides/modules/ROOT/pages/home.adoc', 'v2/modules/ROOT/pages/index.adoc']) {
      const body = read(page)
      assert.ok(linksTo(body, 'https://github.com/redhat-cop/openshift_virtualization_migration/issues'), page)
      assert.ok(!httpUrls(body).some((url) => url.hostname === 'docs.google.com'), page)
    }
  })

  it('drops the Bitwarden appendix topic and states that pull credentials are unpublished', () => {
    const appendix = read('guides/modules/appendix/pages/appendix.adoc')
    assert.doesNotMatch(appendix, /== Bitwarden/)
    assert.match(appendix, /xref:github-credentials\[GitHub Credentials\]/)
    assert.match(appendix, /xref:ssh-key-generation\[SSH Key Generation\]/)

    const prereqs = read('v2/modules/journey/pages/migration-factory-prerequisites.adoc')
    assert.match(prereqs, /Pull credentials are required and are not published in this documentation/)
    assert.ok(prereqs.split('\n').some((line) => line.trim() === 'podman login quay.io/redhat-cop'))
  })

  it('publishes placeholder lab hosts and keeps the RHDP workshop', () => {
    const example = read('utilities/quick-start-lab/lab.env.example')
    assert.match(example, /BASTION_HOST=bastion\.example\.com/)
    assert.match(example, /VMWARE_HOST=esxi\.example\.com/)
    assert.doesNotMatch(example, /EE_LAB_IMAGE=./)
    assert.match(example, /^AAP_EXECUTION_ENVIRONMENT_ID=$/m)
    assert.match(example, /^AAP_REGISTRY_CREDENTIAL_ID=$/m)

    const script = read('utilities/quick-start-lab/build-v2-lab-ee.sh')
    assert.match(script, /\$\{AAP_EXECUTION_ENVIRONMENT_ID\}/)
    assert.match(script, /\$\{AAP_REGISTRY_CREDENTIAL_ID\}/)
    assert.doesNotMatch(script, /execution_environments\/\d/)
    assert.doesNotMatch(script, /"credential":\d/)
    assert.doesNotMatch(script, /:-\d/)

    assert.ok(fs.existsSync(path.join(repoRoot, 'v2/modules/journey/pages/setup-rhdp.adoc')))
    assert.match(
      read('guides/modules/rhdp/pages/sub-pages/custom-inventory.adoc'),
      /exclusive use of internal Red Hat testing/
    )
  })
})
