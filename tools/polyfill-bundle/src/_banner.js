// 这个文件不是 ES Module entry，build.mjs 读它的内容塞到 esbuild banner，
// 让它在 bundle 最顶部、所有 import 副作用之前执行。
//
// 两个 patch 必须最早：
//   1. ensureHead：es-module-shims 启动前 document.head 必须存在；
//   2. SCRIPT.src patch：在 HTML parser 解析 script src 前，给已确认安全的
//      CDN 脚本加 crossorigin="anonymous"，让 WebKit 暴露真实错误 stack。

(function () {
  try {
    if (
      typeof document !== 'undefined' &&
      document.documentElement &&
      !document.head
    ) {
      document.documentElement.insertBefore(
        document.createElement('head'),
        document.documentElement.firstChild,
      );
    }
  } catch (e) {}

  var CROSS_ORIGIN_WHITELIST = /^https?:\/\/[a-z0-9-]+\.ldstatic\.com\//i;
  try {
    if (typeof Element !== 'undefined' && Element.prototype) {
      var origSetAttribute = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function (name, value) {
        try {
          if (
            this &&
            this.tagName === 'SCRIPT' &&
            typeof name === 'string' &&
            name.toLowerCase() === 'src' &&
            typeof value === 'string' &&
            CROSS_ORIGIN_WHITELIST.test(value) &&
            !this.hasAttribute('crossorigin')
          ) {
            origSetAttribute.call(this, 'crossorigin', 'anonymous');
          }
        } catch (_) {}
        return origSetAttribute.apply(this, arguments);
      };
    }
  } catch (e) {}
})();
