// HGHub iOS v1 — cover image decryption (map §6).
// Cover URLs are NOT images: the CDN returns AES-128-CBC ciphertext.
// Key / IV are the hardcoded ASCII strings from the original client
// (media.rs IMG_KEY / IMG_IV); use their UTF-8 bytes, not hex.
// Magic-sniff first: bytes that already look like an image are
// returned as-is. Otherwise decrypt (NoPadding at the cipher layer,
// PKCS#7 stripped in code, exactly like the Rust client).
// In-memory cache, max 240 entries keyed by full URL (map §9).

import Foundation
import UIKit

final class CoverDecryptor {
    static let shared = CoverDecryptor()

    private static let keyString = "f5d965df75336270"
    private static let ivString = "97b60394abc2fbe1"
    private static let maxEntries = 240

    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = Self.maxEntries
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    /// Fetch a cover URL and return decrypted image bytes.
    func imageData(for urlString: String, edge: EdgeClient) async throws -> Data {
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached as Data
        }
        guard let url = URL(string: urlString) else { throw HGHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(EdgeClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(edge.base + "/", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: request)
        let plain = try Self.decryptIfNeeded(data)
        cache.setObject(plain as NSData, forKey: urlString as NSString)
        return plain
    }

    /// Magic-sniff, then AES-128-CBC decrypt + PKCS#7 strip if needed.
    static func decryptIfNeeded(_ data: Data) throws -> Data {
        if isImage(data) { return data }
        guard !data.isEmpty, data.count % kCCBlockSizeAES128 == 0 else {
            throw HGHubError.server("封面解密失败")
        }
        guard
            let keyData = keyString.data(using: .utf8),
            let ivData = ivString.data(using: .utf8),
            keyData.count == kCCKeySizeAES128,
            ivData.count == kCCBlockSizeAES128
        else { throw HGHubError.server("封面解密失败") }

        var out = Data(count: data.count)
        var outLength = 0
        // Copy the capacity to a local first: reading `out.count`
        // inside `withUnsafeMutableBytes` is an overlapping access
        // (Swift exclusive-access error) because `out` is already
        // borrowed mutably by that closure.
        let outCapacity = out.count
        let status = keyData.withUnsafeBytes { keyPtr in
            ivData.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { inPtr in
                    out.withUnsafeMutableBytes { outPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(0), // NoPadding; PKCS#7 stripped below, like Rust
                            keyPtr.baseAddress, kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, data.count,
                            outPtr.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw HGHubError.server("封面解密失败") }
        out.count = outLength
        return try stripPKCS7(out)
    }

    /// Last byte = pad length (1–16); truncate only if the last `pad`
    /// bytes all equal `pad` (map §6, strip_padding).
    private static func stripPKCS7(_ data: Data) throws -> Data {
        guard let pad = data.last, pad >= 1, pad <= 16 else {
            throw HGHubError.server("封面解密失败")
        }
        let count = Int(pad)
        guard data.count >= count else { throw HGHubError.server("封面解密失败") }
        let tail = data.suffix(count)
        guard tail.allSatisfy({ $0 == pad }) else { throw HGHubError.server("封面解密失败") }
        return data.prefix(data.count - count)
    }

    /// JPEG FF D8, PNG 89 50 4E 47, GIF "GIF8", WEBP "RIFF....WEBP".
    private static func isImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let b = [UInt8](data.prefix(12))
        if b[0] == 0xFF && b[1] == 0xD8 { return true } // JPEG
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return true } // PNG
        if data.count >= 4, String(bytes: b.prefix(4), encoding: .ascii) == "GIF8" { return true }
        if data.count >= 12,
           String(bytes: b.prefix(4), encoding: .ascii) == "RIFF",
           String(bytes: b[8..<12], encoding: .ascii) == "WEBP" { return true }
        return false
    }
}
