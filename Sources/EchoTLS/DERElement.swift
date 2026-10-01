import Foundation

/// Just enough DER to tell key formats apart and to wrap an EC key: tag-length-value elements.
struct DERElement {
    let tag: UInt8
    let value: Data

    /// The elements inside a SEQUENCE (or any constructed element).
    func children() -> [DERElement]? { DERElement.parseAll(value) }

    /// One element at the start of `data`, and how many bytes it used.
    static func parse(_ data: Data) -> (element: DERElement, length: Int)? {
        let bytes = [UInt8](data.prefix(6))
        guard bytes.count >= 2 else { return nil }
        var length = Int(bytes[1])
        var header = 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), bytes.count >= 2 + count else { return nil }
            length = bytes[2..<(2 + count)].reduce(0) { $0 << 8 | Int($1) }
            header += count
        }
        guard data.count >= header + length else { return nil }
        let start = data.startIndex + header
        return (DERElement(tag: bytes[0], value: Data(data[start..<(start + length)])), header + length)
    }

    static func parseAll(_ data: Data) -> [DERElement]? {
        var rest = data
        var elements: [DERElement] = []
        while !rest.isEmpty {
            guard let (element, used) = parse(rest) else { return nil }
            elements.append(element)
            rest = Data(rest.dropFirst(used))
        }
        return elements
    }

    static func encode(tag: UInt8, _ value: Data) -> Data {
        var out = Data([tag])
        if value.count < 0x80 {
            out.append(UInt8(value.count))
        } else {
            let lengthBytes = withUnsafeBytes(of: UInt32(value.count).bigEndian) { Array($0) }.drop { $0 == 0 }
            out.append(0x80 | UInt8(lengthBytes.count))
            out.append(contentsOf: lengthBytes)
        }
        out.append(value)
        return out
    }
}

/// The private key formats OpenSSL reads, told apart by their DER structure.
enum PrivateKeyFormat: Equatable {
    /// PKCS#8 `PrivateKeyInfo`.
    case pkcs8
    /// PKCS#8 `EncryptedPrivateKeyInfo`: needs the key password.
    case encryptedPKCS8
    /// PKCS#1 `RSAPrivateKey`.
    case rsa
    /// SEC1 `ECPrivateKey`.
    case ec

    var pemLabel: String {
        switch self {
        case .pkcs8: "PRIVATE KEY"
        case .encryptedPKCS8: "ENCRYPTED PRIVATE KEY"
        case .rsa: "RSA PRIVATE KEY"
        case .ec: "EC PRIVATE KEY"
        }
    }

    init?(der: Data) {
        guard let (outer, used) = DERElement.parse(der), used == der.count, outer.tag == 0x30,
              let children = outer.children(), children.count >= 2 else { return nil }
        switch (children[0].tag, children[1].tag) {
        case (0x30, 0x04): self = .encryptedPKCS8
        case (0x02, 0x30): self = .pkcs8
        case (0x02, 0x02): self = .rsa
        case (0x02, 0x04) where children[0].value == Data([1]): self = .ec
        default: return nil
        }
    }
}
