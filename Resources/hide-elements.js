/* Brook: take things off a page (⇧⌘H), in isolated world BrookHide.
   Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), Curtain.swift.

   Asleep until asked: one closure until window.__brookHide.on() is called. A click picks what's under the
   pointer and sends its selector, a readable name and its shape to Brook (message handler brookHide). */
(function () {
  if (window.__brookHide || window.top !== window) return;
  var frame = null, tag = null, target = null, live = false;

  function sheet(id) {
    var s = document.getElementById(id);
    if (!s) {
      s = document.createElement('style');
      s.id = id;
      (document.head || document.documentElement).appendChild(s);
    }
    return s;
  }

  function chrome() {
    if (frame) return frame;
    frame = document.createElement('div');
    frame.style.cssText = 'position:fixed;z-index:2147483646;pointer-events:none;' +
      'border:2px solid rgba(23,23,23,.9);background:rgba(23,23,23,.07);' +
      'border-radius:4px;transition:all .07s ease-out;display:none';
    tag = document.createElement('div');
    tag.style.cssText = 'position:absolute;font:500 11px -apple-system,BlinkMacSystemFont,sans-serif;color:#fff;' +
      'background:#171717;padding:2px 7px;border-radius:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
    frame.appendChild(tag);
    document.documentElement.appendChild(frame);
    return frame;
  }

  function place(el) {
    var box = chrome(), r = el.getBoundingClientRect();
    box.style.display = 'block';
    box.style.left = r.left + 'px';
    box.style.top = r.top + 'px';
    box.style.width = r.width + 'px';
    box.style.height = r.height + 'px';
    tag.textContent = name(el);
    // Above the element when there's room, else tucked inside its top edge; never off either side.
    tag.style.top = r.top >= 26 ? '-21px' : '3px';
    tag.style.left = Math.max(2, -r.left + 4) + 'px';
    tag.style.maxWidth = Math.max(80, window.innerWidth - Math.max(0, r.left) - 16) + 'px';
  }

  var known = {
    nav: 'Navigation', header: 'Header', footer: 'Footer', aside: 'Sidebar', form: 'Form', dialog: 'Dialog',
    video: 'Video', img: 'Image', button: 'Button', iframe: 'Embed', figure: 'Figure', table: 'Table'
  };

  // What it calls itself, then what kind of thing it is, then what it says.
  function name(el) {
    var said = el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title'));
    if (said && said.trim()) return clip(said.trim(), 40);
    var tagName = el.tagName.toLowerCase();
    if (known[tagName]) return known[tagName];
    var role = el.getAttribute && el.getAttribute('role');
    if (role) return role.charAt(0).toUpperCase() + role.slice(1);
    var text = (el.innerText || '').trim().replace(/\s+/g, ' ');
    return text ? clip(text, 40) : tagName;
  }

  // Size and corner, measured now: a hidden thing has no size later, and two sidebars read alike.
  function shape(el) {
    var r = el.getBoundingClientRect();
    var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    var side = cx < window.innerWidth / 3 ? 'left' : (cx > window.innerWidth * 2 / 3 ? 'right' : 'centre');
    var band = cy < window.innerHeight / 3 ? 'top' : (cy > window.innerHeight * 2 / 3 ? 'bottom' : 'middle');
    return Math.round(r.width) + '×' + Math.round(r.height) + ' · ' + band + ' ' + side;
  }

  function clip(text, n) { return text.length > n ? text.slice(0, n) + '…' : text; }

  // A class worth hanging a rule on: a word, not a build artefact.
  function steady(c) {
    return /^[a-zA-Z][\w-]{2,29}$/.test(c) && !/\d{3,}/.test(c) && !/^(css|sc|jsx|emotion|svelte|styles?)-/.test(c);
  }

  function unique(sel) {
    try { return document.querySelectorAll(sel).length === 1; } catch (e) { return false; }
  }

  function selectorFor(el) {
    if (el.id && unique('#' + CSS.escape(el.id))) return '#' + CSS.escape(el.id);
    var hooks = ['data-testid', 'data-test', 'data-qa', 'data-cy', 'aria-label', 'name', 'role'];
    for (var i = 0; i < hooks.length; i++) {
      var v = el.getAttribute && el.getAttribute(hooks[i]);
      if (v) {
        var s = el.tagName.toLowerCase() + '[' + hooks[i] + '="' + CSS.escape(v) + '"]';
        if (unique(s)) return s;
      }
    }
    var classes = (el.className && typeof el.className === 'string') ? el.className.trim().split(/\s+/).filter(steady) : [];
    if (classes.length) {
      var byClass = el.tagName.toLowerCase() + '.' + classes.map(CSS.escape).join('.');
      if (unique(byClass)) return byClass;
    }
    // Last resort: a path, anchored on the nearest thing with a name.
    var parts = [], node = el;
    while (node && node.nodeType === 1 && node !== document.documentElement) {
      if (node.id && unique('#' + CSS.escape(node.id))) { parts.unshift('#' + CSS.escape(node.id)); break; }
      var tagName = node.tagName.toLowerCase();
      var parent = node.parentElement;
      if (!parent) { parts.unshift(tagName); break; }
      var kin = Array.prototype.filter.call(parent.children, function (c) { return c.tagName === node.tagName; });
      parts.unshift(kin.length > 1 ? tagName + ':nth-of-type(' + (kin.indexOf(node) + 1) + ')' : tagName);
      node = parent;
    }
    return parts.join(' > ');
  }

  function post(message) {
    try { window.webkit.messageHandlers.brookHide.postMessage(message); } catch (e) {}
  }

  function onMove(e) {
    if (!live) return;
    var el = document.elementFromPoint(e.clientX, e.clientY);
    if (!el || el === frame || el === document.documentElement || el === document.body) return;
    target = el;
    place(el);
  }

  // Every kind of press swallowed: real pages act on pointerdown or mousedown and are gone before a click.
  function swallow(e) {
    if (!live) return;
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
  }

  function pick(el) {
    if (!el || el === frame || el === document.documentElement || el === document.body) return;
    var selector;
    try { selector = selectorFor(el); } catch (err) { post({ trouble: String(err) }); return; }
    post({ selector: selector, label: name(el), note: shape(el) });
    target = null;
    if (frame) frame.style.display = 'none';
  }

  function onPress(e) {
    if (!live) return;
    swallow(e);
    // The pointer may have arrived without moving: a click on the first element under it, or a tap.
    pick(target || document.elementFromPoint(e.clientX, e.clientY));
  }

  function onKey(e) {
    if (!live) return;
    if (e.key === 'Escape') { swallow(e); api.off(); }
    else if (e.metaKey && !e.shiftKey && (e.key === 'z' || e.key === 'Z')) { swallow(e); post({ undo: true }); }
  }

  var presses = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click', 'dblclick', 'contextmenu', 'touchstart'];

  var api = window.__brookHide = {
    on: function () {
      if (live) return;
      live = true;
      chrome();
      document.documentElement.style.cursor = 'crosshair';
      document.addEventListener('mousemove', onMove, true);
      document.addEventListener('pointermove', onMove, true);
      document.addEventListener('keydown', onKey, true);
      presses.forEach(function (kind) { document.addEventListener(kind, kind === 'pointerdown' ? onPress : swallow, true); });
    },
    off: function () {
      if (!live) return;
      live = false;
      target = null;
      if (frame) frame.style.display = 'none';
      document.documentElement.style.cursor = '';
      document.removeEventListener('mousemove', onMove, true);
      document.removeEventListener('pointermove', onMove, true);
      document.removeEventListener('keydown', onKey, true);
      presses.forEach(function (kind) { document.removeEventListener(kind, kind === 'pointerdown' ? onPress : swallow, true); });
      post({ off: true });
    },
    // For tests and keyboard use: pick the element at a point.
    pickAt: function (x, y) { pick(document.elementFromPoint(x, y)); },
    // The site's rules, now (the document-start script covers the next load).
    apply: function (css) { sheet('brook-hide').textContent = css; },
    // Show one hidden thing, outlined and scrolled to, while its row is pointed at: the sheet is rebuilt
    // without it rather than fought with another rule, so it comes back with the layout it really had.
    peek: function (css, sel) {
      sheet('brook-hide').textContent = css;
      sheet('brook-hide-peek').textContent = sel + ' { outline: 2px solid rgba(23,23,23,.9) !important; outline-offset: 2px !important; }';
      try {
        var el = document.querySelector(sel);
        if (el) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      } catch (e) {}
    },
    unpeek: function (css) {
      sheet('brook-hide').textContent = css;
      sheet('brook-hide-peek').textContent = '';
    }
  };
})();
