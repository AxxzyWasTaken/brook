// Chrome Web Store: turns the store's own greyed-out "Add to Chrome" button into a working
// "Add to Brook" / "Remove from Brook" button and hides the "Switch to Chrome" nags.
// If the store's markup changes and its button can't be found, a floating button stands in.
(() => {
  if (location.hostname !== 'chromewebstore.google.com') return;
  const FLOATING_ID = 'brook-add-extension';
  const FALLBACK_DELAY = 3000;   // ms on a detail page without finding the store's button
  // Replies 'installed' or 'not-installed'.
  const native = (action, id) => window.webkit.messageHandlers.brookStore.postMessage({ action, id });

  let currentId = null;
  let arrivedAt = 0;
  let installed = null;          // null while unknown
  let busy = false;

  const extensionId = () => {
    const m = location.pathname.match(/\/detail\/(?:[^/]+\/)?([a-p]{32})/);
    return m ? m[1] : null;
  };

  const refreshStatus = () => {
    const id = currentId;
    if (!id || busy) return;
    native('status', id).then(state => {
      if (id !== currentId || busy) return;
      installed = state === 'installed';
      schedule();
    });
  };

  const act = () => {
    const id = currentId;
    if (!id || busy || installed === null) return;
    busy = true;
    schedule();
    native(installed ? 'remove' : 'install', id).then(state => {
      busy = false;
      if (id === currentId) installed = state === 'installed';
      schedule();
    });
  };

  // The store's own install button: disabled and described by the "Switch to Chrome" banner.
  const storeButton = () =>
    document.querySelector('main button[data-brook-store]') ||
    document.querySelector('main button[aria-describedby]:disabled');

  const label = () => busy ? (installed ? 'Removing…' : 'Adding…') : (installed ? 'Remove from Brook' : 'Add to Brook');

  // Keeps Google's markup (ripple, focus ring) and swaps only the visible text.
  const setLabel = (button, text) => {
    const walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.nodeValue.trim()) {
        if (node.nodeValue !== text) node.nodeValue = text;
        return;
      }
    }
    button.textContent = text;
  };

  // The "Switch to Chrome" banner above the listing. The button's aria-describedby names it, but
  // the page renames the banner when it hydrates without updating the button, so match on content too.
  const hideBanner = (button) => {
    const bannerId = button.getAttribute('aria-describedby');
    const banners = [...document.querySelectorAll('main [aria-label="Info"]')]
      .filter(el => /Switch to Chrome/.test(el.textContent))
      .map(el => el.parentElement);
    const byId = bannerId && document.getElementById(bannerId);
    if (byId) banners.push(byId);
    for (const b of banners) if (b.style.display !== 'none') b.style.display = 'none';
  };

  const adopt = (button) => {
    button.dataset.brookStore = '1';
    const disabled = busy || installed === null;
    if (button.disabled !== disabled) button.disabled = disabled;
    setLabel(button, label());
    hideBanner(button);
  };

  // The "Switch to Chrome?" card the store pops up under its header.
  const hideSwitchDialog = () => {
    for (const d of document.querySelectorAll('header [role="dialog"]')) {
      if (/Switch to Chrome/.test(d.textContent) && d.style.display !== 'none') d.style.display = 'none';
    }
  };

  const floating = (show) => {
    let button = document.getElementById(FLOATING_ID);
    if (!show) { if (button) button.remove(); return; }
    if (!button) {
      button = document.createElement('button');
      button.id = FLOATING_ID;
      Object.assign(button.style, {
        position: 'fixed', right: '24px', bottom: '24px', zIndex: '2147483647',
        padding: '12px 22px', borderRadius: '999px', border: 'none',
        font: '600 15px -apple-system, system-ui, sans-serif', color: '#fff', cursor: 'pointer',
        background: '#0b57d0', boxShadow: '0 4px 14px rgba(0,0,0,.2)'
      });
      button.addEventListener('click', act);
      document.documentElement.appendChild(button);
    }
    button.disabled = busy || installed === null;
    if (button.textContent !== label()) button.textContent = label();
  };

  const update = () => {
    const id = extensionId();
    if (id !== currentId) {
      currentId = id;
      arrivedAt = Date.now();
      installed = null;
      busy = false;
      refreshStatus();
    }
    hideSwitchDialog();
    if (!id) { floating(false); return; }
    const button = storeButton();
    if (button) adopt(button);
    floating(!button && Date.now() - arrivedAt > FALLBACK_DELAY);
  };

  let pending = false;
  const schedule = () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; update(); });
  };

  // Capture phase on window runs before the store's own click handling (which offers Chrome).
  window.addEventListener('click', (e) => {
    const button = e.target instanceof Element && e.target.closest('button[data-brook-store]');
    if (!button) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    act();
  }, true);

  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'aria-describedby']
  });
  // Installs and removals made elsewhere in Brook show up when the page comes back into view.
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshStatus(); });
  window.addEventListener('focus', refreshStatus);
  setInterval(schedule, 1000);   // notices the fallback delay passing when nothing else changes
  update();
})();
