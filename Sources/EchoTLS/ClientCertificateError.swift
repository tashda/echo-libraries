import Foundation

/// A client certificate or key could not be turned into files OpenSSL can read.
public struct ClientCertificateError: Error, LocalizedError, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The client certificate isn't a certificate file.
        case certificate
        /// The key is protected by a password and none was given.
        case keyNeedsPassword
        /// The key password doesn't open the key.
        case wrongKeyPassword
        /// The file is missing, unreadable, or isn't a key.
        case unreadable
        /// The key is of a type OpenSSL can't be given from here (for example Ed25519 in a .p12).
        case unsupportedKey
    }

    public let kind: Kind
    public let message: String
    public var errorDescription: String? { message }

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}
