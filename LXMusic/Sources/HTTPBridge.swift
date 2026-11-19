import Foundation

/// 实现 `globalThis.lx.request`：原生 URLSession 不受浏览器跨域限制，
/// 这是 iOS 原生版相比 PWA 最大的优势，音源脚本可以直连各家接口。
final class HTTPBridge {
    static let shared = HTTPBridge()

    private var tasks: [String: URLSessionDataTask] = [:]
    private let lock = NSLock()

    /// - Parameters:
    ///   - id: 与 JS 侧回调一一对应的请求 id
    ///   - completion: (错误信息, 响应对象)，始终在主线程回调
    func request(id: String,
                 urlString: String,
                 options: [String: Any],
                 completion: @escaping (String?, [String: Any]) -> Void) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            completion("无效的 URL: \(urlString)", [:])
            return
        }

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout(from: options))
        let method = (options["method"] as? String ?? "GET").uppercased()
        request.httpMethod = method

        if let headers = options["headers"] as? [String: Any] {
            for (key, value) in headers {
                request.setValue("\(value)", forHTTPHeaderField: key)
            }
        }

        // form / formData / body，按洛雪脚本常见写法依次处理
        if let form = options["form"] as? [String: Any] {
            request.httpBody = formURLEncoded(form).data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        } else if let formData = options["formData"] as? [String: Any] {
            let boundary = "----LXMusicBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            request.httpBody = multipartBody(formData, boundary: boundary)
            request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        } else if let body = options["body"] {
            if let text = body as? String {
                request.httpBody = text.data(using: .utf8)
            } else if let dict = body as? [String: Any] {
                request.httpBody = try? JSONSerialization.data(withJSONObject: dict, options: [])
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 LXMusic/1.0",
                             forHTTPHeaderField: "User-Agent")
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.forget(id)
            var result: [String: Any] = [:]
            let http = response as? HTTPURLResponse
            result["statusCode"] = http?.statusCode ?? 0
            result["status"] = http?.statusCode ?? 0

            var headers: [String: String] = [:]
            if let fields = http?.allHeaderFields {
                for (key, value) in fields {
                    headers[String(describing: key).lowercased()] = "\(value)"
                }
            }
            result["headers"] = headers

            var rawBody = ""
            var binary = false
            if let data = data, !data.isEmpty {
                if let text = String(data: data, encoding: .utf8) {
                    rawBody = text
                } else {
                    rawBody = data.base64EncodedString()
                    binary = true
                }
            }
            result["rawBody"] = rawBody
            result["bodyString"] = rawBody
            result["bodyBase64"] = binary ? rawBody : ""
            result["isBinary"] = binary

            let errorMessage: String?
            if let error = error {
                errorMessage = error.localizedDescription
            } else if let status = http?.statusCode, status >= 400 {
                errorMessage = "HTTP \(status)"
            } else {
                errorMessage = nil
            }

            DispatchQueue.main.async {
                completion(errorMessage, result)
            }
        }

        lock.lock()
        tasks[id] = task
        lock.unlock()
        task.resume()
    }

    func cancel(id: String) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
    }

    private func forget(_ id: String) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }

    private func timeout(from options: [String: Any]) -> TimeInterval {
        let raw: Double
        if let number = options["timeout"] as? NSNumber {
            raw = number.doubleValue
        } else if let string = options["timeout"] as? String {
            raw = Double(string) ?? 15
        } else {
            raw = 15
        }
        // 洛雪部分脚本用毫秒
        let seconds = raw > 1000 ? raw / 1000 : raw
        return max(3, min(seconds, 120))
    }

    private func formURLEncoded(_ form: [String: Any]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")
        return form.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = "\(value)".addingPercentEncoding(withAllowedCharacters: allowed) ?? "\(value)"
            return k.replacingOccurrences(of: " ", with: "+") + "=" + v.replacingOccurrences(of: " ", with: "+")
        }.joined(separator: "&")
    }

    private func multipartBody(_ form: [String: Any], boundary: String) -> Data {
        var data = Data()
        for (key, value) in form {
            guard let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8),
                  let body = "\(value)".data(using: .utf8),
                  let tail = "\r\n".data(using: .utf8) else { continue }
            data.append(head)
            data.append(body)
            data.append(tail)
        }
        if let end = "--\(boundary)--\r\n".data(using: .utf8) { data.append(end) }
        return data
    }
}
