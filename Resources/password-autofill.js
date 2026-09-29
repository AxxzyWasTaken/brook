(() => {
    'use strict';
    let target = null;
    let token = '';
    let interaction = -Infinity;
    let edited = 0;
    let offered = false;
    const submitted = new WeakSet();
    const send = body => window.webkit.messageHandlers.brookPasswords.postMessage(body);
    const visible = field => {
        if (!(field instanceof HTMLInputElement) || !field.isConnected || field.disabled || field.readOnly) return false;
        const r = field.getBoundingClientRect();
        if (r.width < 8 || r.height < 8 || r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) return false;
        for (let node = field; node instanceof Element; node = node.parentElement) {
            const style = getComputedStyle(node);
            if (style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0) return false;
        }
        const x = Math.max(0, Math.min(innerWidth - 1, r.left + r.width / 2));
        const y = Math.max(0, Math.min(innerHeight - 1, r.top + r.height / 2));
        return document.elementFromPoint(x, y) === field;
    };
    const fields = input => {
        if (!(input instanceof HTMLInputElement) || !['text', 'email', 'password'].includes(input.type)) return null;
        const scope = input.form || document;
        const passwords = [...scope.querySelectorAll('input[type="password"]')].filter(visible);
        if (passwords.length !== 1 || passwords[0].autocomplete === 'new-password' || passwords[0].autocomplete === 'one-time-code') return null;
        const password = passwords[0];
        const users = [...scope.querySelectorAll('input')].filter(field =>
            ['text', 'email'].includes(field.type) && visible(field) && field.autocomplete !== 'one-time-code' &&
            Boolean(field.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING));
        const username = users.find(field => field.autocomplete === 'username') || users.at(-1) || null;
        if (input !== password && input !== username) return null;
        return { username, password };
    };
    const offer = input => {
        const pair = fields(input);
        if (!pair || !visible(input) || document.activeElement !== input || performance.now() - interaction > 1000) return;
        target = { input, ...pair };
        token = [...crypto.getRandomValues(new Uint32Array(4))].join('-');
        const r = input.getBoundingClientRect();
        offered = true;
        send({ type: 'focus', token, x: r.x, y: r.y, width: r.width, height: r.height });
    };
    const dismiss = () => {
        token = '';
        target = null;
        if (offered) send({ type: 'dismiss' });
        offered = false;
    };
    document.addEventListener('pointerdown', event => {
        if (!event.isTrusted) return;
        interaction = performance.now();
        if (event.target instanceof HTMLInputElement) setTimeout(() => offer(event.target), 0);
        else dismiss();
    }, true);
    document.addEventListener('keydown', event => {
        if (!event.isTrusted) return;
        interaction = performance.now();
        if (event.key === 'Escape') dismiss();
    }, true);
    document.addEventListener('focusin', event => offer(event.target), true);
    document.addEventListener('input', event => {
        if (event.isTrusted && fields(event.target)) {
            edited = performance.now();
            if (event.target.form) submitted.delete(event.target.form);
        }
    }, true);
    document.addEventListener('focusout', () => setTimeout(() => {
        if (target && document.activeElement !== target.input) dismiss();
    }, 0), true);
    window.addEventListener('pagehide', dismiss);
    window.addEventListener('scroll', dismiss, true);
    window.addEventListener('resize', dismiss);
    const setValue = (field, value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
    };
    Object.defineProperty(globalThis, 'brookPasswordFill', { value: (request, username, password) => {
        const pair = target && fields(target.input);
        if (!request || request !== token || !target || !pair || pair.password !== target.password ||
            pair.username !== target.username || document.activeElement !== target.input || !visible(target.input)) return false;
        token = '';
        if (target.username) setValue(target.username, username);
        setValue(target.password, password);
        return true;
    }});
    document.addEventListener('submit', event => {
        if (!event.isTrusted || !(event.target instanceof HTMLFormElement) || !edited || performance.now() - edited > 60000) return;
        const password = [...event.target.querySelectorAll('input[type="password"]')].find(visible);
        const pair = password && fields(password);
        if (!pair || !pair.password.value || pair.password.value.length > 16384) return;
        let action;
        try { action = new URL(event.target.action || location.href, location.href); } catch { return; }
        if (action.origin !== location.origin) return;
        const username = pair.username?.value || '';
        if (submitted.has(event.target)) return;
        submitted.add(event.target);
        edited = 0;
        send({ type: 'submit', username, password: pair.password.value });
    }, true);
})();
