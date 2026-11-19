import Foundation
import JavaScriptCore

enum LXError: LocalizedError {
    case script(String)
    case noSource
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .script(let message): return message
        case .noSource: return "尚未启用可用的自定义音源"
        case .invalidResponse: return "音源返回的数据格式无法识别"
        }
    }
}

/// 在 iOS 上执行洛雪自定义源脚本。
///
/// 对应关系：
///   globalThis.lx.on / send / request  ->  JSContext + __lxNative 桥
///   globalThis.lx.utils                ->  ScriptCrypto + HTTPBridge
///   EVENT_NAMES.request                ->  perform(action:sourceKey:info:)
///
/// 所有 JSContext 操作都在主线程执行；网络请求由 HTTPBridge 异步完成后回到主线程。
final class ScriptEngine {
    private let context = JSContext()!
    private let source: ScriptSource
    private let env: String

    private var pending: [String: (Bool, String) -> Void] = [:]
    private var timeoutItems: [String: DispatchWorkItem] = [:]
    private var timerItems: [String: DispatchWorkItem] = [:]
    private var repeatingTimers: [String: Timer] = [:]
    private var counter = 0
    private var didReportReady = false
    private var readinessWorkItem: DispatchWorkItem?

    var onReady: ((Bool, [String: SourceCapability], String) -> Void)?
    var onUpdateAlert: (([String: Any]) -> Void)?
    var onLog: ((String) -> Void)?

    private(set) var capabilities: [String: SourceCapability] = [:]
    private(set) var isReady = false

    init(source: ScriptSource, env: String) {
        self.source = source
        self.env = env
        context.name = "LXMusic.Script." + source.name
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "未知 JavaScript 异常"
            self?.onLog?("JS 异常: \(message)")
        }
    }

    deinit {
        timerItems.values.forEach { $0.cancel() }
        timeoutItems.values.forEach { $0.cancel() }
        repeatingTimers.values.forEach { $0.invalidate() }
    }

    // MARK: - 启动

    func start() {
        installNativeBridge()

        guard let url = Bundle.main.url(forResource: "LXPrelude", withExtension: "js"),
              let prelude = try? String(contentsOf: url, encoding: .utf8) else {
            onLog?("打包资源缺失：LXPrelude.js")
            reportReady(false, "缺少脚本运行时资源")
            return
        }

        context.evaluateScript(prelude)
        if let exception = context.exception {
            onLog?("运行时初始化失败: \(exception.toString() ?? "")")
            reportReady(false, "脚本运行时初始化失败")
            return
        }

        context.evaluateScript(source.script)
        if let exception = context.exception {
            onLog?("脚本执行失败: \(exception.toString() ?? "")")
            reportReady(false, "脚本执行出错，详见日志")
            return
        }

        // 少数脚本会延迟发送 inited，给 3 秒宽限期
        if !didReportReady {
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, !self.didReportReady else { return }
                self.reportReady(false, "脚本未在 3 秒内发送 inited 事件")
            }
            readinessWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
        }
    }

    // MARK: - 宿主 -> 脚本

    func perform(action: String,
                 sourceKey: String,
                 info: [String: Any],
                 timeout: TimeInterval = 25,
                 completion: @escaping (Result<Any, Error>) -> Void) {
        guard isReady else {
            completion(.failure(LXError.script("音源尚未就绪：\(source.name)")))
            return
        }
        let payload: [String: Any] = ["source": sourceKey, "action": action, "info": info]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            completion(.failure(LXError.invalidResponse))
            return
        }

        counter += 1
        let callId = "call_\(counter)_\(Int(Date().timeIntervalSince1970 * 1000))"
        pending[callId] = { [weak self] ok, value in
            self?.timeoutItems.removeValue(forKey: callId)?.cancel()
            if !ok {
                completion(.failure(LXError.script(value)))
                return
            }
            if let raw = value.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: raw) {
                completion(.success(object))
            } else {
                completion(.success(value))
            }
        }

        let item = DispatchWorkItem { [weak self] in
            guard let callback = self?.pending.removeValue(forKey: callId) else { return }
            callback(false, "音源请求超时（\(Int(timeout)) 秒）")
        }
        timeoutItems[callId] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)

        // 用字符串属性传递，避免手工拼接 JS 字面量带来的转义问题
        context.setObject(json, forKeyedSubscript: "__lxPayload" as NSString)
        context.setObject(callId, forKeyedSubscript: "__lxCallId" as NSString)
        context.evaluateScript("__lxInvoke(__lxCallId, JSON.parse(__lxPayload))")
        if let exception = context.exception {
            onLog?("调用音源失败: \(exception.toString() ?? "")")
        }
    }

    // MARK: - native bridge

    private func installNativeBridge() {
        let native = JSValue(newObjectIn: context)!

        let logBlock: @convention(block) (String, String) -> Void = { [weak self] level, message in
            self?.onLog?("[\(level)] \(message)")
        }
        native.setObject(logBlock, forKeyedSubscript: "log" as NSString)

        let sendBlock: @convention(block) (String, String) -> Void = { [weak self] event, json in
            self?.handleSend(event: event, data: Self.jsonObject(json))
        }
        native.setObject(sendBlock, forKeyedSubscript: "send" as NSString)

        let requestBlock: @convention(block) (String, String, String) -> Void = { [weak self] url, optionsJSON, id in
            let options = Self.jsonObject(optionsJSON)
            HTTPBridge.shared.request(id: id, urlString: url, options: options) { [weak self] error, response in
                guard let self = self else { return }
                let errorValue: Any = error == nil ? (NSNull() as Any) : error!
                self.context.objectForKeyedSubscript("__lxRequestDone")?
                    .call(withArguments: [id, errorValue, response])
            }
        }
        native.setObject(requestBlock, forKeyedSubscript: "request" as NSString)

        let cancelBlock: @convention(block) (String) -> Void = { id in
            HTTPBridge.shared.cancel(id: id)
        }
        native.setObject(cancelBlock, forKeyedSubscript: "cancel" as NSString)

        let resolveBlock: @convention(block) (String, Bool, String) -> Void = { [weak self] id, ok, value in
            guard let callback = self?.pending.removeValue(forKey: id) else { return }
            callback(ok, value)
        }
        native.setObject(resolveBlock, forKeyedSubscript: "resolve" as NSString)

        let timerBlock: @convention(block) (String, Double, Bool) -> Void = { [weak self] id, milliseconds, repeating in
            self?.scheduleTimer(id: id, milliseconds: milliseconds, repeating: repeating)
        }
        native.setObject(timerBlock, forKeyedSubscript: "setTimeout" as NSString)

        let clearTimerBlock: @convention(block) (String) -> Void = { [weak self] id in
            self?.timerItems.removeValue(forKey: id)?.cancel()
            self?.repeatingTimers.removeValue(forKey: id)?.invalidate()
        }
        native.setObject(clearTimerBlock, forKeyedSubscript: "clearTimer" as NSString)

        let zlibBlock: @convention(block) (String, String, Bool) -> Void = { [weak self] id, base64, compress in
            let result = ScriptCrypto.zlibCompress(base64: base64, compress: compress)
            self?.context.objectForKeyedSubscript("__lxZlibDone")?
                .call(withArguments: [id, result != nil, result ?? ""])
        }
        native.setObject(zlibBlock, forKeyedSubscript: "zlib" as NSString)

        let md5Block: @convention(block) (String) -> String = { ScriptCrypto.md5Hex($0) }
        native.setObject(md5Block, forKeyedSubscript: "md5" as NSString)

        let sha1Block: @convention(block) (String) -> String = { ScriptCrypto.sha1Hex($0) }
        native.setObject(sha1Block, forKeyedSubscript: "sha1" as NSString)

        let randomBlock: @convention(block) (Double) -> String = { ScriptCrypto.randomBytesBase64(Int($0)) }
        native.setObject(randomBlock, forKeyedSubscript: "randomBytes" as NSString)

        let aesBlock: @convention(block) (String, String, String, String) -> String = { base64, mode, key, iv in
            guard let data = Data(base64Encoded: base64) else { return "" }
            return ScriptCrypto.aesEncrypt(data: data, mode: mode, key: key, iv: iv) ?? ""
        }
        native.setObject(aesBlock, forKeyedSubscript: "aesEncrypt" as NSString)

        let rsaBlock: @convention(block) (String, String) -> String = { base64, key in
            guard let data = Data(base64Encoded: base64) else { return "" }
            return ScriptCrypto.rsaEncrypt(data: data, publicKeyPEM: key) ?? ""
        }
        native.setObject(rsaBlock, forKeyedSubscript: "rsaEncrypt" as NSString)

        let b64EncodeBlock: @convention(block) (String) -> String = { ScriptCrypto.b64encode($0) }
        native.setObject(b64EncodeBlock, forKeyedSubscript: "b64encode" as NSString)

        let b64DecodeBlock: @convention(block) (String) -> String = { ScriptCrypto.b64decode($0) }
        native.setObject(b64DecodeBlock, forKeyedSubscript: "b64decode" as NSString)

        let bufToStringBlock: @convention(block) (String, String) -> String = { base64, format in
            ScriptCrypto.bufToString(base64: base64, format: format)
        }
        native.setObject(bufToStringBlock, forKeyedSubscript: "bufToString" as NSString)

        let utf8EncodeBlock: @convention(block) (String) -> String = { ScriptCrypto.utf8Encode($0) }
        native.setObject(utf8EncodeBlock, forKeyedSubscript: "utf8Encode" as NSString)

        let utf8DecodeBlock: @convention(block) (String) -> String = { ScriptCrypto.utf8Decode($0) }
        native.setObject(utf8DecodeBlock, forKeyedSubscript: "utf8Decode" as NSString)

        let versionBlock: @convention(block) () -> String = { "2.0.0" }
        native.setObject(versionBlock, forKeyedSubscript: "apiVersion" as NSString)

        let envValue = env
        let envBlock: @convention(block) () -> String = { envValue }
        native.setObject(envBlock, forKeyedSubscript: "env" as NSString)

        let infoJSON = scriptInfoJSON()
        let infoBlock: @convention(block) () -> String = { infoJSON }
        native.setObject(infoBlock, forKeyedSubscript: "currentScriptInfo" as NSString)

        context.setObject(native, forKeyedSubscript: "__lxNative" as NSString)
    }

    // MARK: - 事件处理

    private func handleSend(event: String, data: [String: Any]) {
        switch event {
        case EventName.inited:
            if let status = data["status"] as? Bool, status == false {
                reportReady(false, data["message"] as? String ?? "脚本报告初始化失败")
                return
            }
            var caps: [String: SourceCapability] = [:]
            if let sources = data["sources"] as? [String: Any] {
                for (key, value) in sources {
                    guard let item = value as? [String: Any] else { continue }
                    caps[key] = SourceCapability(name: item["name"] as? String ?? key,
                                                 actions: item["actions"] as? [String] ?? [],
                                                 qualitys: item["qualitys"] as? [String] ?? [])
                }
            }
            capabilities = caps
            isReady = !caps.isEmpty
            if isReady {
                let names = caps.map { "\($0.key)(\($0.value.actions.joined(separator: "/")))" }.joined(separator: ", ")
                onLog?("音源就绪: \(names)")
                reportReady(true, "就绪")
            } else {
                reportReady(false, "音源未声明任何可用 source")
            }

        case EventName.updateAlert:
            onUpdateAlert?(data)

        default:
            onLog?("脚本事件: \(event)")
        }
    }

    private func reportReady(_ ok: Bool, _ message: String) {
        guard !didReportReady else { return }
        didReportReady = true
        readinessWorkItem?.cancel()
        onReady?(ok, capabilities, message)
    }

    private enum EventName {
        static let inited = "inited"
        static let updateAlert = "updateAlert"
    }

    // MARK: - 定时器

    private func scheduleTimer(id: String, milliseconds: Double, repeating: Bool) {
        let interval = max(0, milliseconds) / 1000.0
        if repeating {
            let timer = Timer.scheduledTimer(withTimeInterval: max(interval, 0.02), repeats: true) { [weak self] _ in
                self?.fireTimer(id: id, repeating: true)
            }
            repeatingTimers[id] = timer
        } else {
            let item = DispatchWorkItem { [weak self] in
                self?.timerItems.removeValue(forKey: id)
                self?.fireTimer(id: id, repeating: false)
            }
            timerItems[id] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
        }
    }

    private func fireTimer(id: String, repeating: Bool) {
        context.objectForKeyedSubscript("__lxTimerFire")?.call(withArguments: [id, repeating])
    }

    // MARK: - 工具

    private func scriptInfoJSON() -> String {
        let info: [String: Any] = [
            "name": source.name,
            "description": source.description,
            "version": source.version,
            "author": source.author,
            "homepage": source.homepage,
            "rawScript": source.script,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: []) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func jsonObject(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object
    }
}
