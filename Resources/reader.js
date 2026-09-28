// Brook reader view: a clean overlay with the page's article, toggled by the Reader button.
// Runs in its own content world. Returns "on", "off" or "none" (nothing readable found).
(function () {
  var host = document.getElementById('brook-reader');
  if (host) {
    host.remove();
    document.documentElement.style.overflow = host.dataset.overflow || '';
    return 'off';
  }

  // Pick the element holding the most paragraph text, preferring <article> and <main>.
  function textOf(el) {
    var n = 0;
    el.querySelectorAll('p').forEach(function (p) { n += p.textContent.trim().length; });
    return n;
  }
  var best = null, bestScore = 0;
  var candidates = document.querySelectorAll('article, main, [role="main"], [itemprop="articleBody"], section, div');
  for (var i = 0; i < candidates.length; i++) {
    var el = candidates[i];
    var score = textOf(el);
    if (score < 400) continue;
    // Deeper containers win ties: they carry less navigation and footer text.
    if (/^(ARTICLE|MAIN)$/.test(el.tagName)) score *= 1.3;
    if (score > bestScore * 1.05 || (score >= bestScore * 0.9 && best && best.contains(el))) {
      best = el; bestScore = score;
    }
  }
  if (!best) return 'none';

  var article = best.cloneNode(true);
  article.querySelectorAll('script, style, noscript, iframe, form, button, input, nav, aside, footer, header, ' +
                           'svg, [role="navigation"], [role="complementary"], [aria-hidden="true"]')
    .forEach(function (n) { n.remove(); });
  article.querySelectorAll('*').forEach(function (n) {
    n.removeAttribute('style');
    n.removeAttribute('class');
    n.removeAttribute('id');
    if (n.tagName === 'IMG') {
      var src = n.currentSrc || n.getAttribute('data-src') || n.getAttribute('src');
      if (src) n.setAttribute('src', new URL(src, location.href).href);
      n.removeAttribute('srcset');
      n.removeAttribute('loading');
    }
    if (n.tagName === 'A' && n.getAttribute('href')) n.setAttribute('href', new URL(n.getAttribute('href'), location.href).href);
  });

  var title = (document.querySelector('h1') || {}).textContent || document.title;
  var site = location.hostname.replace(/^www\./, '');
  var dark = matchMedia('(prefers-color-scheme: dark)').matches;

  host = document.createElement('div');
  host.id = 'brook-reader';
  host.dataset.overflow = document.documentElement.style.overflow;
  host.style.cssText = 'position:fixed;inset:0;z-index:2147483647;overflow:auto;';
  var root = host.attachShadow({ mode: 'closed' });
  root.innerHTML =
    '<style>' +
    ':host{all:initial}' +
    '.page{min-height:100%;background:' + (dark ? '#1c1b1a' : '#faf8f4') + ';color:' + (dark ? '#e8e4dc' : '#2a2724') + ';' +
    'font:19px/1.65 "New York", ui-serif, Georgia, serif;padding:64px 24px 120px;box-sizing:border-box}' +
    '.col{max-width:680px;margin:0 auto}' +
    '.site{font:600 13px -apple-system, system-ui;letter-spacing:.04em;text-transform:uppercase;opacity:.55;margin-bottom:12px}' +
    'h1.title{font-size:2em;line-height:1.2;margin:0 0 32px}' +
    'img,video,figure{max-width:100%;height:auto;border-radius:8px}' +
    'figure{margin:24px 0}figcaption{font-size:.8em;opacity:.65}' +
    'a{color:inherit;text-decoration-color:' + (dark ? '#8a857c' : '#b3ab9e') + '}' +
    'pre,code{font:15px ui-monospace, Menlo, monospace;white-space:pre-wrap}' +
    'blockquote{margin:0;padding-left:20px;border-left:3px solid ' + (dark ? '#3d3a36' : '#e2ddd3') + '}' +
    '</style>' +
    '<div class="page"><div class="col"><div class="site"></div><h1 class="title"></h1><div class="body"></div></div></div>';
  root.querySelector('.site').textContent = site;
  root.querySelector('.title').textContent = title.trim();
  var firstHeading = article.querySelector('h1');
  if (firstHeading && firstHeading.textContent.trim() === title.trim()) firstHeading.remove();
  root.querySelector('.body').appendChild(article);
  document.documentElement.appendChild(host);
  document.documentElement.style.overflow = 'hidden';
  return 'on';
})();
