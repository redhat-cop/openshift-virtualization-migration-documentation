;(function () {
  var STORAGE_PREFIX = 'ovm-doc-checklist:'

  function itemKey (input) {
    var label = input.closest('label') || input.parentElement
    var text = ((label && label.textContent) || '').replace(/\s+/g, ' ').trim()
    return STORAGE_PREFIX + location.pathname + '::' + text
  }

  function syncAttribute (input) {
    if (input.checked) input.setAttribute('checked', '')
    else input.removeAttribute('checked')
    var li = input.closest('li')
    if (li) li.classList.toggle('is-checked', input.checked)
  }

  function enableChecklist (root) {
    root.querySelectorAll('ul.checklist input[type="checkbox"]').forEach(function (input) {
      input.removeAttribute('disabled')
      input.disabled = false

      try {
        var stored = localStorage.getItem(itemKey(input))
        if (stored === '1') input.checked = true
        else if (stored === '0') input.checked = false
      } catch (e) {
        /* private mode / blocked storage */
      }

      syncAttribute(input)

      input.addEventListener('change', function () {
        syncAttribute(input)
        try {
          localStorage.setItem(itemKey(input), input.checked ? '1' : '0')
        } catch (e) {
          /* ignore quota / private mode */
        }
      })
    })
  }

  function init () {
    var article = document.querySelector('article.doc')
    if (!article) return
    enableChecklist(article)
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init)
  } else {
    init()
  }
})()
