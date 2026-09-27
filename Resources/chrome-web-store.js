(() => {
  if (location.hostname !== 'chromewebstore.google.com') return;
  const BUTTON_ID = 'brook-add-extension';

  const extensionId = () => {
    const m = location.pathname.match(/\/detail\/(?:[^/]+\/)?([a-p]{32})/);
    return m ? m[1] : null;
  };

  const update = () => {
    const id = extensionId();
    let button = document.getElementById(BUTTON_ID);
    if (!id) { if (button) button.remove(); return; }
    if (button) return;
    button = document.createElement('button');
    button.id = BUTTON_ID;
    button.textContent = 'Add to Brook';
    Object.assign(button.style, {
      position: 'fixed', right: '24px', bottom: '24px', zIndex: '2147483647',
      padding: '12px 22px', borderRadius: '999px', border: '1px solid rgba(255,255,255,.35)',
      font: '600 15px -apple-system, system-ui, sans-serif', color: '#fff', cursor: 'pointer',
      background: 'linear-gradient(135deg, #7b61ff, #2f80ed)',
      boxShadow: '0 10px 30px rgba(47,128,237,.35)'
    });
    button.addEventListener('click', () => {
      const current = extensionId();
      if (current) window.webkit.messageHandlers.brookInstallExtension.postMessage(current);
    });
    document.documentElement.appendChild(button);
  };

  update();
  setInterval(update, 800);
})();
