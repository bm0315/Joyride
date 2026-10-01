import AgentAvatarCore
import AppKit
import WebKit

@MainActor
final class AvatarWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: WKWebView
    private let schemeHandler: AvatarPackSchemeHandler
    private let onRendered: (TimeInterval) -> Void
    private var scriptMessageHandler: WeakScriptMessageHandler?
    private var pack: InstalledAvatarPack
    private var isPageReady = false
    private var pendingPresentation: Presentation?

    private struct Presentation {
        let state: AvatarStateID
        let source: String
        let additionalCount: Int
        let agents: [ActiveAgentSummary]
        let receivedAt: Date
    }

    init(pack: InstalledAvatarPack, onRendered: @escaping (TimeInterval) -> Void) {
        self.pack = pack
        self.onRendered = onRendered
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        let schemeHandler = AvatarPackSchemeHandler(packDirectory: pack.directory)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "avatar-pack")
        self.schemeHandler = schemeHandler
        webView = WKWebView(frame: .zero, configuration: configuration)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        let handler = WeakScriptMessageHandler(delegate: self)
        scriptMessageHandler = handler
        configuration.userContentController.add(handler, name: "avatarHost")
        configure(panel: panel)
        configure(webView: webView, in: panel)
        loadPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setPack(_ pack: InstalledAvatarPack) {
        self.pack = pack
        schemeHandler.setPackDirectory(pack.directory)
        isPageReady = false
        loadPage()
    }

    func present(
        state: AvatarStateID,
        source: String,
        additionalCount: Int,
        agents: [ActiveAgentSummary],
        receivedAt: Date
    ) {
        pendingPresentation = Presentation(
            state: state,
            source: source,
            additionalCount: additionalCount,
            agents: agents,
            receivedAt: receivedAt
        )
        guard isPageReady, let stateDefinition = pack.state(state) else { return }
        let agentValues = agents.map { ["source": displaySource($0.source), "state": $0.state.displayName] }
        let script = "setAvatar(\(jsonLiteral(stateDefinition.media.path)), \(jsonLiteral(stateDefinition.media.type.rawValue)), \(jsonLiteral(state.displayName)), \(jsonLiteral(source)), \(state.isWorkState), \(additionalCount), \(jsonLiteral(agentValues)), \(receivedAt.timeIntervalSince1970 * 1000))"
        webView.evaluateJavaScript(script)
    }

    func dockBottomRight() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24))
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .floating : .normal
    }

    func setClickThrough(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        guard isPageReady else { return }
        webView.evaluateJavaScript("setPlaybackEnabled(\(enabled))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        preloadCurrentPack()
        if let pendingPresentation {
            present(
                state: pendingPresentation.state,
                source: pendingPresentation.source,
                additionalCount: pendingPresentation.additionalCount,
                agents: pendingPresentation.agents,
                receivedAt: pendingPresentation.receivedAt
            )
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else { return }
        if action == "drag", let event = NSApp.currentEvent {
            window?.performDrag(with: event)
            return
        }
        if action.hasPrefix("rendered:") {
            let rawValue = action.dropFirst("rendered:".count)
            if let receivedMilliseconds = TimeInterval(rawValue) {
                onRendered(receivedMilliseconds / 1_000)
            }
        }
    }

    private func configure(panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 220, height: 220)
        panel.maxSize = NSSize(width: 760, height: 760)
        panel.contentAspectRatio = NSSize(width: 1, height: 1)
        panel.setFrameAutosaveName("JoyrideWindow")
        if !panel.setFrameUsingName("JoyrideWindow") {
            dockBottomRightAfterWindowSetup(panel)
        }
    }

    private func configure(webView: WKWebView, in panel: NSPanel) {
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = webView
    }

    private func loadPage() {
        webView.loadHTMLString(Self.pageHTML, baseURL: URL(string: "avatar-pack://current/")!)
    }

    private func preloadCurrentPack() {
        let imagePaths = pack.validation.manifest.states
            .filter { $0.media.type != .video }
            .map { $0.media.path }
        webView.evaluateJavaScript("preloadAssets(\(jsonLiteral(imagePaths)))")
    }

    private func dockBottomRightAfterWindowSetup(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.minY + 24
        ))
    }

    private func jsonLiteral(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let value = value as? String,
           let data = try? JSONSerialization.data(withJSONObject: [value]),
           let array = String(data: data, encoding: .utf8) {
            return String(array.dropFirst().dropLast())
        }
        return "null"
    }

    private func displaySource(_ value: String) -> String {
        switch value.lowercased() {
        case "openclaw": "OpenClaw"
        case "hermes": "Hermes"
        case "codex": "Codex"
        case "claude-code": "Claude Code"
        default: value
        }
    }

    private static let pageHTML = #"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        * { box-sizing: border-box; }
        html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
        body { user-select: none; -webkit-user-select: none; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        #frame { position: relative; width: 100%; height: 100%; overflow: hidden; border-radius: 24px; background: #17181b; box-shadow: inset 0 0 0 1px rgba(255,255,255,.16); }
        #backdrop, #avatar, #video { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
        #backdrop { object-fit: cover; filter: blur(18px) brightness(.7); animation: backdrop-drift 13s ease-in-out infinite; }
        #avatar, #video { object-fit: contain; transform-origin: 50% 62%; animation: avatar-breathe 5.5s ease-in-out infinite; }
        #video { display: none; }
        #shade { position: absolute; inset: auto 0 0 0; height: 34%; background: linear-gradient(transparent, rgba(0,0,0,.48)); pointer-events: none; }
        #status { position: absolute; left: 14px; bottom: 14px; display: flex; align-items: center; gap: 8px; padding: 7px 10px; max-width: calc(100% - 28px); border-radius: 999px; color: white; background: rgba(20,20,23,.58); backdrop-filter: blur(14px); font: 600 12px -apple-system, BlinkMacSystemFont, sans-serif; border: 1px solid rgba(255,255,255,.18); text-shadow: 0 1px 2px rgba(0,0,0,.35); }
        #dot { width: 7px; height: 7px; flex: 0 0 auto; border-radius: 50%; background: #69e6ad; box-shadow: 0 0 10px #69e6ad; animation: status-pulse 2.2s ease-in-out infinite; }
        #source { opacity: .72; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        #badge { display: none; border: 0; border-radius: 999px; padding: 2px 7px; color: white; background: #635bff; font: 700 11px -apple-system; cursor: pointer; }
        #details { display: none; position: absolute; right: 14px; bottom: 54px; min-width: 170px; max-width: calc(100% - 28px); padding: 10px; border-radius: 14px; color: white; background: rgba(20,20,23,.88); border: 1px solid rgba(255,255,255,.18); backdrop-filter: blur(18px); font-size: 12px; }
        #details.visible { display: block; }
        .agent { display: flex; justify-content: space-between; gap: 14px; padding: 4px 2px; }
        .agent-state { opacity: .7; }
        #frame[data-work="false"] #avatar, #frame[data-work="false"] #video { animation-duration: 8s; }
        #frame[data-work="false"] #dot { background: #9bc7ff; box-shadow: 0 0 10px #9bc7ff; }
        body[data-paused="true"] * { animation-play-state: paused !important; }
        @keyframes avatar-breathe { 0%, 100% { transform: scale(1) translateY(0); } 50% { transform: scale(1.018) translateY(-2px); } }
        @keyframes backdrop-drift { 0%, 100% { transform: scale(1.13) translate3d(-0.8%, 0, 0); } 50% { transform: scale(1.17) translate3d(0.8%, -0.5%, 0); } }
        @keyframes status-pulse { 0%, 100% { opacity: .72; transform: scale(.92); } 50% { opacity: 1; transform: scale(1.08); } }
        @media (prefers-reduced-motion: reduce) { #backdrop, #avatar, #video, #dot { animation: none; } #backdrop { transform: scale(1.13); } }
      </style>
    </head>
    <body>
      <div id="frame">
        <img id="backdrop" alt="">
        <img id="avatar" alt="Joyride Agent">
        <video id="video" muted loop playsinline></video>
        <div id="shade"></div>
        <div id="details"></div>
        <div id="status"><span id="dot"></span><span id="label">Resting</span><span id="source">· Idle</span><button id="badge"></button></div>
      </div>
      <script>
        const frame = document.getElementById('frame');
        const avatar = document.getElementById('avatar');
        const video = document.getElementById('video');
        const backdrop = document.getElementById('backdrop');
        const badge = document.getElementById('badge');
        const details = document.getElementById('details');
        let preloaded = [];
        function preloadAssets(paths) { preloaded = paths.map(path => { const image = new Image(); image.src = encodeURI(path); return image; }); }
        function setAvatar(path, mediaType, label, source, isWork, additionalCount, agents, receivedAt) {
          const encoded = encodeURI(path);
          backdrop.src = encoded;
          const usesVideo = mediaType === 'video';
          avatar.style.display = usesVideo ? 'none' : 'block';
          video.style.display = usesVideo ? 'block' : 'none';
          if (usesVideo) { video.src = encoded; video.play().catch(() => {}); }
          else { video.pause(); video.removeAttribute('src'); avatar.src = encoded; }
          document.getElementById('label').textContent = label;
          document.getElementById('source').textContent = '· ' + source;
          frame.dataset.work = isWork ? 'true' : 'false';
          badge.style.display = additionalCount > 0 ? 'block' : 'none';
          badge.textContent = '+' + additionalCount;
          details.innerHTML = '';
          agents.forEach(agent => {
            const row = document.createElement('div'); row.className = 'agent';
            const name = document.createElement('span'); name.textContent = agent.source;
            const state = document.createElement('span'); state.className = 'agent-state'; state.textContent = agent.state;
            row.append(name, state); details.append(row);
          });
          const ready = usesVideo ? Promise.resolve() : avatar.decode().catch(() => {});
          ready.finally(() => requestAnimationFrame(() => window.webkit.messageHandlers.avatarHost.postMessage('rendered:' + receivedAt)));
        }
        function setPlaybackEnabled(enabled) {
          document.body.dataset.paused = enabled ? 'false' : 'true';
          if (enabled && video.src) video.play().catch(() => {}); else video.pause();
        }
        badge.addEventListener('click', event => { event.stopPropagation(); details.classList.toggle('visible'); });
        details.addEventListener('mousedown', event => event.stopPropagation());
        frame.addEventListener('mousedown', event => {
          if (event.target !== badge && !details.contains(event.target)) window.webkit.messageHandlers.avatarHost.postMessage('drag');
        });
      </script>
    </body>
    </html>
    """#
}

@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

private final class AvatarPackSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var packDirectory: URL

    init(packDirectory: URL) {
        self.packDirectory = packDirectory.standardizedFileURL
    }

    func setPackDirectory(_ directory: URL) {
        lock.lock()
        packDirectory = directory.standardizedFileURL
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.scheme == "avatar-pack",
              requestURL.host == "current" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        lock.lock()
        let root = packDirectory
        lock.unlock()
        let relativePath = requestURL.path.removingPercentEncoding?.drop(while: { $0 == "/" }) ?? ""
        let fileURL = root.appendingPathComponent(String(relativePath)).standardizedFileURL
        guard fileURL.path.hasPrefix(root.path + "/") else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(fileURL.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(_ extensionValue: String) -> String {
        switch extensionValue.lowercased() {
        case "webp": "image/webp"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "mp4": "video/mp4"
        case "webm": "video/webm"
        default: "application/octet-stream"
        }
    }
}
