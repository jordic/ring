import Foundation
import CryptoKit

/// Pure-Swift TOTP generator (RFC 6238 / HOTP RFC 4226).
/// No external dependencies — uses CryptoKit for HMAC-SHA1.
enum TOTPGenerator {

    enum TOTPError: LocalizedError {
        case invalidBase32
        case generationFailed

        var errorDescription: String? {
            switch self {
            case .invalidBase32:    return "Invalid base32 TOTP secret"
            case .generationFailed: return "Failed to generate TOTP code"
            }
        }
    }

    /// Generates a 6-digit TOTP code for the given base32 secret at the current time.
    static func generate(secret: String) throws -> String {
        let key = try decodeBase32(secret.uppercased().replacingOccurrences(of: " ", with: ""))
        let counter = UInt64(Date().timeIntervalSince1970) / 30
        return try hotp(key: key, counter: counter, digits: 6)
    }

    // MARK: - HOTP (RFC 4226)

    private static func hotp(key: Data, counter: UInt64, digits: Int) throws -> String {
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)

        let symKey = SymmetricKey(data: key)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symKey)
        let hmacBytes = Data(mac)

        let offset = Int(hmacBytes[hmacBytes.count - 1] & 0x0f)
        let truncated = hmacBytes.withUnsafeBytes { ptr -> UInt32 in
            var value: UInt32 = 0
            withUnsafeMutableBytes(of: &value) { dest in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: ptr.baseAddress!.advanced(by: offset), count: 4))
            }
            return UInt32(bigEndian: value) & 0x7fff_ffff
        }

        let code = truncated % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", code)
    }

    // MARK: - Base32 decoder (RFC 4648)

    private static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    private static func decodeBase32(_ input: String) throws -> Data {
        var bits = 0
        var value = 0
        var output = Data()

        for char in input {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                if char == "=" { continue } // padding
                throw TOTPError.invalidBase32
            }
            let charValue = base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            value = (value << 5) | charValue
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }

        return output
    }
}
