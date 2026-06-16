import Foundation

enum AWSCredentialStatus: Equatable {
    case unchecked
    case valid
    case expired
    case unavailable(String)
}
