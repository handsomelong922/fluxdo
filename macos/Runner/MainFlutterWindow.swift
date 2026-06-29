import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 注册 cookie 同步 channel，用于将 cookie 写入 HTTPCookieStorage.shared
    // WKWebView 的 sharedCookiesEnabled 在创建时从 HTTPCookieStorage.shared 读取 cookie
    let channel = FlutterMethodChannel(
      name: "com.fluxdo/cookie_storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setCookies":
        guard let args = call.arguments as? [[String: Any?]] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Expected list of cookie maps", details: nil))
          return
        }
        self.setCookiesToSharedStorage(args)
        result(true)
      case "clearCookies":
        let url = (call.arguments as? String) ?? ""
        self.clearCookiesFromSharedStorage(url: url)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 注册代理 CA 证书 channel（原生层 SSL challenge 拦截）
    let proxyCertChannel = FlutterMethodChannel(
      name: "com.fluxdo/proxy_cert",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    proxyCertChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setCaCertPem":
        guard let pem = call.arguments as? String else {
          result(false)
          return
        }
        let trusted = DohProxyCertHandler.shared.setCaCertPem(pem)
        result(trusted)
      case "isCaTrusted":
        result(DohProxyCertHandler.shared.isCaTrusted())
      case "clear":
        DohProxyCertHandler.shared.clearCaCert()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let rawCookieChannel = FlutterMethodChannel(
      name: "com.fluxdo/raw_cookie",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    let cookieObserverChannel = FlutterMethodChannel(
      name: "com.fluxdo/cookie_observer",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    CookieStoreObserverHandler.shared.attach(channel: cookieObserverChannel)

    rawCookieChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setRawCookie":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let rawSetCookie = args["rawSetCookie"] as? String,
              let url = URL(string: urlString) else {
          result(false)
          return
        }
        let headers = ["Set-Cookie": rawSetCookie]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard let cookie = cookies.first else {
          result(false)
          return
        }
        CookieStoreObserverHandler.shared.beginInternalWrite()
        let writeSharedStorage = args["writeSharedStorage"] as? Bool ?? true
        let storage = HTTPCookieStorage.shared
        if writeSharedStorage {
          // 同时写入 HTTPCookieStorage.shared，配合 sharedCookiesEnabled
          // 确保 WKWebView 在创建时即可从 shared storage 读取到 cookie。
          storage.setCookie(cookie)
        } else {
          MainFlutterWindow.deleteSharedCookieApple(storage: storage, url: url, cookie: cookie)
        }
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.setCookie(cookie) {
          CookieStoreObserverHandler.shared.endInternalWrite()
          result(true)
        }

      case "nukeAllVariants":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let name = args["name"] as? String,
              let pathCandidates = args["pathCandidates"] as? [String],
              let url = URL(string: urlString) else {
          result(0)
          return
        }
        let rawDomainCandidates = args["domainCandidates"] as? [Any] ?? []
        let domainCandidates: [String?] = rawDomainCandidates.map {
          $0 is NSNull ? nil : ($0 as? String)
        }
        MainFlutterWindow.nukeAllVariantsApple(
          url: url,
          name: name,
          domainCandidates: domainCandidates,
          pathCandidates: pathCandidates,
          result: result
        )

      case "deleteExactCookie":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let name = args["name"] as? String,
              let path = args["path"] as? String,
              let url = URL(string: urlString) else {
          result(false)
          return
        }
        let domain = args["domain"] as? String
        MainFlutterWindow.deleteExactCookieApple(
          url: url,
          name: name,
          domain: domain,
          path: path,
          result: result
        )

      case "getAllCookieInfos":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
          result([])
          return
        }
        MainFlutterWindow.getAllCookieInfosApple(url: url, result: result)

      case "countCookiesByName":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let name = args["name"] as? String,
              let url = URL(string: urlString) else {
          result(0)
          return
        }
        MainFlutterWindow.countCookiesByNameApple(url: url, name: name, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  // MARK: - Cookie 引擎 v0.4.0 原语

  private static func sameSiteString(_ cookie: HTTPCookie) -> String? {
    if #available(macOS 10.15, *) {
      guard let policy = cookie.sameSitePolicy else { return nil }
      switch policy {
      case .sameSiteLax:
        return "Lax"
      case .sameSiteStrict:
        return "Strict"
      default:
        let raw = policy.rawValue.lowercased()
        if raw.contains("none") { return "None" }
        if raw.contains("lax") { return "Lax" }
        if raw.contains("strict") { return "Strict" }
        return nil
      }
    }
    return nil
  }

  private static func matchDomain(cookieDomain: String, candidate: String?, host: String) -> Bool {
    let normalizedCookieDomain = (cookieDomain.hasPrefix(".")
      ? String(cookieDomain.dropFirst())
      : cookieDomain).lowercased()
    if let candidate = candidate {
      let normalizedCandidate = (candidate.hasPrefix(".")
        ? String(candidate.dropFirst())
        : candidate).lowercased()
      return normalizedCookieDomain == normalizedCandidate
    } else {
      return normalizedCookieDomain == host
    }
  }

  private static func deleteSharedCookieApple(
    storage: HTTPCookieStorage,
    url: URL,
    cookie: HTTPCookie
  ) {
    let host = (url.host ?? "").lowercased()
    guard let sharedCookies = storage.cookies else { return }
    for sharedCookie in sharedCookies where
      sharedCookie.name == cookie.name &&
      sharedCookie.path == cookie.path &&
      MainFlutterWindow.matchDomain(cookieDomain: sharedCookie.domain, candidate: cookie.domain, host: host) {
      storage.deleteCookie(sharedCookie)
    }
  }

  private static func nukeAllVariantsApple(
    url: URL,
    name: String,
    domainCandidates: [String?],
    pathCandidates: [String],
    result: @escaping FlutterResult
  ) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let host = (url.host ?? "").lowercased()

    store.getAllCookies { cookies in
      // 枚举真实 cookie 对象，按 name + 适用域过滤（与 countCookiesByNameApple 对齐），
      // 逐个 delete 真实对象，不再用 domainCandidates/pathCandidates 猜测。
      let matching = cookies.filter { cookie in
        guard cookie.name == name else { return false }
        let cookieDomain = (cookie.domain.hasPrefix(".")
          ? String(cookie.domain.dropFirst())
          : cookie.domain).lowercased()
        return host == cookieDomain || host.hasSuffix("." + cookieDomain)
      }

      CookieStoreObserverHandler.shared.beginInternalWrite()
      let group = DispatchGroup()
      let countLock = NSLock()
      var deletedCount = 0

      for cookie in matching {
        group.enter()
        store.delete(cookie) {
          countLock.lock()
          deletedCount += 1
          countLock.unlock()
          group.leave()
        }
      }

      let storage = HTTPCookieStorage.shared
      if let sharedCookies = storage.cookies {
        for cookie in sharedCookies where cookie.name == name {
          let cookieDomain = (cookie.domain.hasPrefix(".")
            ? String(cookie.domain.dropFirst())
            : cookie.domain).lowercased()
          if host == cookieDomain || host.hasSuffix("." + cookieDomain) {
            storage.deleteCookie(cookie)
          }
        }
      }

      group.notify(queue: .main) {
        CookieStoreObserverHandler.shared.endInternalWrite()
        result(deletedCount)
      }
    }
  }

  private static func deleteExactCookieApple(
    url: URL,
    name: String,
    domain: String?,
    path: String,
    result: @escaping FlutterResult
  ) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let host = (url.host ?? "").lowercased()

    store.getAllCookies { cookies in
      let target = cookies.first { cookie in
        cookie.name == name &&
        cookie.path == path &&
        MainFlutterWindow.matchDomain(cookieDomain: cookie.domain, candidate: domain, host: host)
      }
      guard let cookie = target else {
        DispatchQueue.main.async { result(false) }
        return
      }

      CookieStoreObserverHandler.shared.beginInternalWrite()
      let group = DispatchGroup()
      group.enter()
      store.delete(cookie) {
        group.leave()
      }

      let storage = HTTPCookieStorage.shared
      if let sharedCookies = storage.cookies {
        for sharedCookie in sharedCookies where
          sharedCookie.name == name &&
          sharedCookie.path == path &&
          MainFlutterWindow.matchDomain(cookieDomain: sharedCookie.domain, candidate: domain, host: host) {
          storage.deleteCookie(sharedCookie)
        }
      }

      group.notify(queue: .main) {
        CookieStoreObserverHandler.shared.endInternalWrite()
        result(true)
      }
    }
  }

  private static func getAllCookieInfosApple(url: URL, result: @escaping FlutterResult) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let host = (url.host ?? "").lowercased()

    store.getAllCookies { cookies in
      let applicable = cookies.filter { cookie in
        let cookieDomain = (cookie.domain.hasPrefix(".")
          ? String(cookie.domain.dropFirst())
          : cookie.domain).lowercased()
        return host == cookieDomain || host.hasSuffix("." + cookieDomain)
      }

      let infos: [[String: Any?]] = applicable.map { cookie in
        return [
          "name": cookie.name,
          "value": cookie.value,
          "domain": cookie.domain,
          "path": cookie.path,
          "isSecure": cookie.isSecure,
          "isHttpOnly": cookie.isHTTPOnly,
          "expiresMillis": cookie.expiresDate.map { Int($0.timeIntervalSince1970 * 1000) },
          "sameSite": MainFlutterWindow.sameSiteString(cookie),
        ]
      }

      DispatchQueue.main.async {
        result(infos)
      }
    }
  }

  private static func countCookiesByNameApple(url: URL, name: String, result: @escaping FlutterResult) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let host = (url.host ?? "").lowercased()

    store.getAllCookies { cookies in
      let count = cookies.filter { cookie in
        guard cookie.name == name else { return false }
        let cookieDomain = (cookie.domain.hasPrefix(".")
          ? String(cookie.domain.dropFirst())
          : cookie.domain).lowercased()
        return host == cookieDomain || host.hasSuffix("." + cookieDomain)
      }.count

      DispatchQueue.main.async {
        result(count)
      }
    }
  }

  /// 将 cookie 写入 HTTPCookieStorage.shared
  private func setCookiesToSharedStorage(_ cookieMaps: [[String: Any?]]) {
    let storage = HTTPCookieStorage.shared
    for map in cookieMaps {
      guard let name = map["name"] as? String,
            let value = map["value"] as? String,
            let urlString = map["url"] as? String else {
        continue
      }
      var properties: [HTTPCookiePropertyKey: Any] = [
        .originURL: urlString,
        .name: name,
        .value: value,
        .path: (map["path"] as? String) ?? "/",
      ]
      if let domain = map["domain"] as? String {
        properties[.domain] = domain
      } else if let host = URL(string: urlString)?.host {
        properties[.domain] = host
      }
      if let expiresMs = map["expiresDate"] as? Int, expiresMs > 0 {
        properties[.expires] = Date(timeIntervalSince1970: TimeInterval(Double(expiresMs) / 1000))
      }
      if let isSecure = map["isSecure"] as? Bool, isSecure {
        properties[.secure] = "TRUE"
      }
      if let isHttpOnly = map["isHttpOnly"] as? Bool, isHttpOnly {
        properties[.init("HttpOnly")] = "YES"
      }
      if let cookie = HTTPCookie(properties: properties) {
        storage.setCookie(cookie)
      }
    }
  }

  /// 清除 HTTPCookieStorage.shared 中指定 URL 的 cookie
  private func clearCookiesFromSharedStorage(url: String) {
    let storage = HTTPCookieStorage.shared
    guard let urlHost = URL(string: url)?.host else { return }
    if let cookies = storage.cookies {
      for cookie in cookies {
        if urlHost.hasSuffix(cookie.domain) || ".\(urlHost)".hasSuffix(cookie.domain) {
          storage.deleteCookie(cookie)
        }
      }
    }
  }
}

// MARK: - Cookie Store Observer

class CookieStoreObserverHandler: NSObject, WKHTTPCookieStoreObserver {
  static let shared = CookieStoreObserverHandler()

  private var channel: FlutterMethodChannel?
  private let lock = NSLock()
  private var internalWriteCount = 0
  private var attached = false

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    if attached { return }
    attached = true
    DispatchQueue.main.async {
      let store = WKWebsiteDataStore.default().httpCookieStore
      store.add(self)
    }
  }

  func beginInternalWrite() {
    lock.lock()
    internalWriteCount += 1
    lock.unlock()
  }

  func endInternalWrite() {
    lock.lock()
    internalWriteCount = max(0, internalWriteCount - 1)
    lock.unlock()
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    lock.lock()
    let isInternal = internalWriteCount > 0
    lock.unlock()
    if isInternal { return }

    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onCookiesChanged", arguments: nil)
    }
  }
}
