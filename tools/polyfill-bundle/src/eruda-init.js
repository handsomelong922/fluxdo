// 在 main frame 装 Eruda。等 body 出现后再 init（Eruda 需要往 body 挂 UI）。
// 失败完全静默，不影响业务。
import eruda from 'eruda';

function initEruda() {
  try {
    if (window.__fluxdoErudaInited) return;
    window.__fluxdoErudaInited = true;
    eruda.init({
      tool: ['console', 'network', 'elements', 'resources', 'sources', 'info'],
      defaults: {
        displaySize: 50,
        transparency: 0.95,
        theme: 'Dark',
      },
    });
  } catch (e) {}
}

if (document.body) {
  initEruda();
} else if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEruda, { once: true });
} else {
  var tries = 0;
  var timer = setInterval(function () {
    if (document.body) {
      clearInterval(timer);
      initEruda();
    } else if (++tries > 100) {
      clearInterval(timer);
    }
  }, 50);
}
