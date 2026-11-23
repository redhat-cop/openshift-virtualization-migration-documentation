;(function () {
  'use strict'

  function isEmptySearchQuery (value) {
    return !String(value || '').trim()
  }

  function bindSearchEmptyQuery (doc) {
    doc = doc || document
    const input = doc.getElementById('search-input')
    if (!input) return

    function collapseWhitespaceOnly () {
      if (isEmptySearchQuery(input.value)) input.value = ''
    }

    input.addEventListener('input', collapseWhitespaceOnly, true)
    input.addEventListener('keydown', collapseWhitespaceOnly, true)
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { isEmptySearchQuery: isEmptySearchQuery, bindSearchEmptyQuery: bindSearchEmptyQuery }
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        bindSearchEmptyQuery(document)
      })
    } else {
      bindSearchEmptyQuery(document)
    }
  }
})()
