'use strict'

const { describe, it } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const repoRoot = path.resolve(__dirname, '..')
const imageDir = path.join(repoRoot, 'v2/modules/journey/assets/images')

const generatedSvgs = ['laptop-vs-aap.svg', 'aap-setup-path.svg']

// Active content must never ship in a generated SVG served from the public
// site: scripts and event handlers execute when the SVG URL is opened
// directly, and static hosts do not sanitize SVGs.
const activeContent = /<script[\s>]|on(?:load|error|click|mouseover|focus)=|javascript:|data:text\/html|<iframe[\s>]|<object[\s>]|<embed[\s>]/i

describe('generated SVG safety', () => {
  it('contains no active content in generated flowchart SVGs', () => {
    for (const svg of generatedSvgs) {
      const body = fs.readFileSync(path.join(imageDir, svg), 'utf8')
      assert.doesNotMatch(body, activeContent, `${svg} must not contain active content`)
    }
  })

  it('keeps every generated SVG paired with a committed .mmd source', () => {
    for (const svg of generatedSvgs) {
      const source = path.join(imageDir, svg.replace(/\.svg$/, '.mmd'))
      assert.ok(fs.existsSync(source), `missing .mmd source for ${svg}`)
    }
  })
})
