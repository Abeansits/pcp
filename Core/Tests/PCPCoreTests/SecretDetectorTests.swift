import XCTest
@testable import PCPCore

final class SecretDetectorTests: XCTestCase {
    func testFlagsPasswordsAndTokens() {
        let secrets = [
            "Tr0ub4dor&3",
            "aB3xK9pQ2mZ7",
            "x7#Kp!2qLm9@",
            "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789",
            "sk-proj-abcdefghijklmnopqrstuvwxyz012345",
            "AKIAIOSFODNN7EXAMPLE",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----",
        ]
        for s in secrets {
            XCTAssertTrue(SecretDetector.looksLikeSecret(s), s)
        }
    }

    func testLeavesOrdinaryTextAlone() {
        let normal = [
            "hello world",
            "lunch at 12.30 works for me",
            "processPayment2",
            "MacBookPro2024",
            "iPhone15Pro",
            "user@example.com",
            "https://Example.com/a1B2c3",
            "~/Documents/Invoices/4.pdf",
            "a3f9c2e1b7d04e5f",       // git sha
            "2026-02-06",
            "const processPayment = async (orderId) => {}",
            "Ünïcødé1!Aa",
        ]
        for s in normal {
            XCTAssertFalse(SecretDetector.looksLikeSecret(s), s)
        }
    }

    func testConcealedPasteboardTypes() {
        XCTAssertTrue(SecretDetector.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(SecretDetector.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"]))
    }
}
