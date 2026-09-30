// Remembers the boxes the user typed into, so Brook doesn't put a tab to sleep while it holds text that
// was never sent: waking the page couldn't bring it back. A box emptied by sending (a chat's composer)
// no longer counts. Runs in its own content world; Brook calls brookHoldsTyping() before a tab sleeps.
(function () {
  'use strict';
  const typed = new Set();
  document.addEventListener('input', event => {
    if (!event.isTrusted || !(event.target instanceof Element)) return;
    typed.add(event.target);
    if (typed.size > 40) typed.delete(typed.values().next().value);
  }, true);
  const holds = el => {
    if (!el.isConnected) return false;
    if (el instanceof HTMLTextAreaElement) return el.value.trim() !== '' && el.value !== el.defaultValue;
    if (el instanceof HTMLInputElement) {
      if (!['text', 'email', 'url', 'tel', 'number', 'search'].includes(el.type)) return false;
      return el.value.trim() !== '' && el.value !== el.defaultValue;
    }
    return el.isContentEditable && (el.textContent || '').trim() !== '';
  };
  Object.defineProperty(globalThis, 'brookHoldsTyping', {
    value: () => {
      for (const el of typed) if (!el.isConnected) typed.delete(el);
      return [...typed].some(holds);
    }
  });
})();
