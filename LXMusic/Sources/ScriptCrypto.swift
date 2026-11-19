import Foundation
import CryptoKit
import CommonCrypto
import Security
import Compression

/// 为音源脚本提供 `lx.utils.crypto` / `lx.utils.buffer` / `lx.utils.zlib` 所需的原生能力。
/// 洛雪的很多音源脚本需要用 MD5、AES、RSA 给各平台接口签名，这里全部用系统框架实现。
enum ScriptCrypto {

    // MARK: - Base64 / 字节串

    static func b64encode(_ binaryString: String) -> String {
        let data = binaryString.data(using: .isoLatin1) ?? Data()
        return data.base64EncodedString()
    }

    static func b64decode(_ base64: String) -> String {
        let clean = base64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: clean) else { return "" }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func utf8Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func utf8Decode(_ base64: String) -> String {
        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `Buffer.toString(buffer, format)`
    static func bufToString(base64: String, format: String) -> String {
        guard let data = Data(base64Encoded: base64) else { return "" }
        switch format.lowercased() {
        case "hex":
            return data.map { String(format: "%02x", $0) }.joined()
        case "base64":
            return data.base64EncodedString()
        case "latin1", "binary", "ascii":
            return String(data: data, encoding: .isoLatin1) ?? ""
        case "utf16le", "ucs2":
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        default:
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    // MARK: - Hash / 随机

    static func md5Hex(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha1Hex(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func randomBytesBase64(_ size: Int) -> String {
        let count = max(0, min(size, 4096))
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - AES（CBC / ECB，PKCS7）

    /// 返回 base64，JS 侧再转回 Uint8Array
    static func aesEncrypt(data: Data, mode: String, key: String, iv: String) -> String? {
        let lower = mode.lowercased()
        let keyLength: Int
        if lower.contains("256") {
            keyLength = Int(kCCKeySizeAES256)
        } else if lower.contains("192") {
            keyLength = Int(kCCKeySizeAES192)
        } else {
            keyLength = Int(kCCKeySizeAES128)
        }
        let blockSize = Int(kCCBlockSizeAES128)

        var keyData = keyBytes(from: key)
        if keyData.count < keyLength {
            keyData += Data(repeating: 0, count: keyLength - keyData.count)
        }
        if keyData.count > keyLength {
            keyData = Data(keyData.prefix(keyLength))
        }

        var ivData = keyBytes(from: iv)
        if ivData.count < blockSize {
            ivData += Data(repeating: 0, count: blockSize - ivData.count)
        }
        if ivData.count > blockSize {
            ivData = Data(ivData.prefix(blockSize))
        }

        let isECB = lower.contains("ecb")
        let optionBits: UInt32 = UInt32(kCCOptionPKCS7Padding) | (isECB ? UInt32(kCCOptionECBMode) : 0)
        let options = CCOptions(optionBits)
        let bufferSize = data.count + blockSize + 32
        var buffer = Data(repeating: 0, count: bufferSize)
        var moved = 0

        let status: CCCryptorStatus = buffer.withUnsafeMutableBytes { out -> CCCryptorStatus in
            data.withUnsafeBytes { input -> CCCryptorStatus in
                keyData.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    ivData.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                options,
                                keyPtr.baseAddress,
                                keyLength,
                                ivPtr.baseAddress,
                                input.baseAddress,
                                data.count,
                                out.baseAddress,
                                bufferSize,
                                &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        return Data(buffer.prefix(moved)).base64EncodedString()
    }

    // MARK: - RSA（PKCS#1 v1.5，PEM 公钥）

    static func rsaEncrypt(data: Data, publicKeyPEM: String) -> String? {
        var base64 = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
        base64 = base64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let keyData = Data(base64Encoded: base64) else { return nil }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else { return nil }

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key,
                                                        .rsaEncryptionPKCS1,
                                                        data as CFData,
                                                        &error) else { return nil }
        return (encrypted as Data).base64EncodedString()
    }

    // MARK: - zlib

    static func zlibCompress(base64: String, compress: Bool) -> String? {
        guard let input = Data(base64Encoded: base64) else { return nil }
        let output = compress ? deflate(input) : inflate(input)
        return output?.base64EncodedString()
    }

    private static func deflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        let capacity = input.count + input.count / 8 + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = input.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return compression_encode_buffer(&output,
                                             capacity,
                                             base.assumingMemoryBound(to: UInt8.self),
                                             input.count,
                                             nil,
                                             COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(output.prefix(written))
    }

    private static func inflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        var capacity = max(input.count * 6, 4096)
        for _ in 0..<6 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = input.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return compression_decode_buffer(&output,
                                                 capacity,
                                                 base.assumingMemoryBound(to: UInt8.self),
                                                 input.count,
                                                 nil,
                                                 COMPRESSION_ZLIB)
            }
            if written > 0 { return Data(output.prefix(written)) }
            capacity *= 4
        }
        return nil
    }

    // MARK: - 内部

    /// 密钥既可能是 hex 字符串，也可能是普通字符串
    private static func keyBytes(from value: String) -> Data {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexSet = Set("0123456789abcdefABCDEF")
        if trimmed.count >= 16,
           trimmed.count % 2 == 0,
           trimmed.allSatisfy({ hexSet.contains($0) }),
           let decoded = Data(hexString: trimmed) {
            return decoded
        }
        return trimmed.data(using: .utf8) ?? Data()
    }
}

private extension Data {
    init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = clean.startIndex
        while index < clean.endIndex {
            guard let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) else { return nil }
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
