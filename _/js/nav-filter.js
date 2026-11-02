;(function (global) {
  'use strict'

  function normalizeQuery (query) {
    return String(query || '').trim().toLowerCase()
  }

  function labelMatches (label, query) {
    const q = normalizeQuery(query)
    if (!q) return true
    return String(label || '').toLowerCase().includes(q)
  }

  function filterTree (nodes, query) {
    const q = normalizeQuery(query)
    const empty = !q

    function walk (node) {
      const children = (node.children || []).map(walk)
      const childVisible = children.some(function (child) {
        return child.visible
      })
      const selfMatch = empty || String(node.label || '').toLowerCase().includes(q)
      const visible = empty || selfMatch || childVisible
      return {
        label: node.label,
        el: node.el,
        visible: visible,
        expanded: empty ? Boolean(node.expanded) : childVisible,
        children: children,
      }
    }

    const resultNodes = (nodes || []).map(walk)
    return {
      nodes: resultNodes,
      hasMatches: empty || resultNodes.some(function (node) {
        return node.visible
      }),
    }
  }

  function getItemLabel (item) {
    if (!item || !item.querySelector) return ''
    const labelEl = item.querySelector(':scope > .nav-link, :scope > .nav-text')
    return labelEl ? labelEl.textContent.replace(/\s+/g, ' ').trim() : ''
  }

  function childList (item) {
    if (!item || !item.children) return null
    for (let i = 0; i < item.children.length; i++) {
      const child = item.children[i]
      if (child.classList && child.classList.contains('nav-list')) return child
    }
    return item.querySelector ? item.querySelector(':scope > .nav-list') : null
  }

  function readTree (navRoot) {
    function walkList (ul) {
      if (!ul) return []
      const items = []
      const kids = ul.children || []
      for (let i = 0; i < kids.length; i++) {
        const li = kids[i]
        if (!li.classList || !li.classList.contains('nav-item')) continue
        items.push({
          el: li,
          label: getItemLabel(li),
          expanded: li.classList.contains('is-active'),
          children: walkList(childList(li)),
        })
      }
      return items
    }

    const rootList = navRoot.querySelector ? navRoot.querySelector(':scope > .nav-list') : null
    return walkList(rootList)
  }

  function applyResult (nodes) {
    (nodes || []).forEach(function (node) {
      if (!node.el || !node.el.classList) return
      if (node.visible) node.el.classList.remove('is-filtered-out')
      else node.el.classList.add('is-filtered-out')
      if (node.expanded) node.el.classList.add('is-active')
      else node.el.classList.remove('is-active')
      applyResult(node.children)
    })
  }

  function snapshotExpanded (navRoot) {
    const items = navRoot.querySelectorAll('.nav-item')
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (!item.hasAttribute('data-nav-filter-expanded')) {
        item.setAttribute('data-nav-filter-expanded', item.classList.contains('is-active') ? '1' : '0')
      }
    }
  }

  function restoreExpanded (navRoot) {
    const items = navRoot.querySelectorAll('.nav-item')
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      item.classList.remove('is-filtered-out')
      if (item.hasAttribute('data-nav-filter-expanded')) {
        if (item.getAttribute('data-nav-filter-expanded') === '1') item.classList.add('is-active')
        else item.classList.remove('is-active')
        item.removeAttribute('data-nav-filter-expanded')
      }
    }
  }

  function toggleEmpty (navRoot, show) {
    const empty = navRoot.querySelector('#nav-filter-empty')
    if (!empty) return
    if (show) empty.removeAttribute('hidden')
    else empty.setAttribute('hidden', '')
  }

  function collectVisibleLabels (nodes, acc) {
    acc = acc || []
    ;(nodes || []).forEach(function (node) {
      if (node.visible) {
        acc.push(node.label)
        collectVisibleLabels(node.children, acc)
      }
    })
    return acc
  }

  function applyNavFilter (navRoot, query) {
    if (!navRoot) return { hasMatches: false, visibleLabels: [] }
    const q = normalizeQuery(query)

    if (!q) {
      restoreExpanded(navRoot)
      toggleEmpty(navRoot, false)
      const restored = filterTree(readTree(navRoot), '')
      return { hasMatches: true, visibleLabels: collectVisibleLabels(restored.nodes) }
    }

    snapshotExpanded(navRoot)
    const result = filterTree(readTree(navRoot), q)
    applyResult(result.nodes)
    toggleEmpty(navRoot, !result.hasMatches)
    return {
      hasMatches: result.hasMatches,
      visibleLabels: collectVisibleLabels(result.nodes),
    }
  }

  function bindNavFilter (doc) {
    doc = doc || (typeof document !== 'undefined' ? document : null)
    if (!doc) return
    const input = doc.getElementById('nav-filter-input')
    const navRoot = doc.querySelector('.nav-menu')
    if (!input || !navRoot) return

    function onInput () {
      applyNavFilter(navRoot, input.value)
    }

    input.addEventListener('input', onInput)
    input.addEventListener('search', onInput)
    onInput()
  }

  const api = {
    normalizeQuery: normalizeQuery,
    labelMatches: labelMatches,
    filterTree: filterTree,
    applyNavFilter: applyNavFilter,
    bindNavFilter: bindNavFilter,
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api
  }
  global.NavFilter = api

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        bindNavFilter(document)
      })
    } else {
      bindNavFilter(document)
    }
  }
})(typeof globalThis !== 'undefined' ? globalThis : this)
