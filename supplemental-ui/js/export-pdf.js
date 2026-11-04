;(function () {
  function absoluteUrl (href) {
    try {
      return new URL(href, document.baseURI).href
    } catch (e) {
      return href
    }
  }

  function collectHead () {
    var parts = []
    document.querySelectorAll('link[rel="stylesheet"]').forEach(function (link) {
      var href = link.getAttribute('href')
      if (!href) return
      parts.push('<link rel="stylesheet" href="' + absoluteUrl(href) + '">')
    })
    document.querySelectorAll('head style').forEach(function (style) {
      parts.push('<style>' + style.innerHTML + '</style>')
    })
    parts.push(
      '<style>' +
        'html,body{background:#fff!important;color:#151515!important;margin:0;padding:0;}' +
        'body.export-pdf-body{padding:1.25rem 1.5rem!important;font-family:"Red Hat Text",RedHatText,sans-serif;}' +
        'article.doc{color:#151515!important;max-width:46rem;margin:0 auto;padding:0!important;}' +
        'article.doc a{color:#06c!important;text-decoration:underline;}' +
        'article.doc pre.highlight code,article.doc pre:not(.highlight){' +
        'background:#f2f2f2!important;-webkit-print-color-adjust:exact;print-color-adjust:exact;}' +
        '.quick-start-toolbar,.hide-for-print,.doc-version-disclaimer,.pagination,' +
        '.export-pdf-button{display:none!important;}' +
        '*,*::before,*::after{-webkit-print-color-adjust:exact;print-color-adjust:exact;}' +
        '@page{margin:0.6in;}' +
        '</style>'
    )
    return parts.join('\n')
  }

  window.exportDocPdf = function exportDocPdf () {
    var article = document.querySelector('article.doc')
    if (!article) {
      window.print()
      return
    }

    var clone = article.cloneNode(true)
    clone
      .querySelectorAll(
        '.quick-start-toolbar, .hide-for-print, .doc-version-disclaimer, .pagination, .export-pdf-button'
      )
      .forEach(function (el) {
        el.remove()
      })

    var title = (document.title || 'Document').replace(/[<>]/g, '')
    var html =
      '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>' +
      title +
      '</title>' +
      collectHead() +
      '</head><body class="export-pdf-body">' +
      clone.outerHTML +
      '</body></html>'

    var win = window.open('', '_blank')
    if (!win) {
      window.print()
      return
    }

    win.document.open()
    win.document.write(html)
    win.document.close()

    var printed = false
    function triggerPrint () {
      if (printed) return
      printed = true
      win.focus()
      win.print()
    }

    win.addEventListener('afterprint', function () {
      win.close()
    })

    var links = Array.prototype.slice.call(
      win.document.querySelectorAll('link[rel="stylesheet"]')
    )
    if (!links.length) {
      setTimeout(triggerPrint, 50)
      return
    }

    var pending = links.length
    function done () {
      pending -= 1
      if (pending <= 0) setTimeout(triggerPrint, 50)
    }
    links.forEach(function (link) {
      link.addEventListener('load', done)
      link.addEventListener('error', done)
    })
    setTimeout(triggerPrint, 1500)
  }
})()
