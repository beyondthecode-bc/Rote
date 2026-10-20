import XCTest
@testable import Rote

/// macOS 27 renamed the System Settings list of apps with Accessibility access to "Device Control and
/// Data Access", so the texts that name the list pick their key by the system's major version. The
/// expected names are Apple's own: on macOS 27.0.1 the SecurityPrivacyExtension's CFBundleDisplayName
/// (Privacy & Security) and the ACCESSIBILITY key of its Localizable.loctable.
@MainActor
final class PermissionPaneTests: XCTestCase {
    private func strings(_ code: String) -> LocalizationManager {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        testDefaults.defaults.set(code, forKey: "rote.language")
        return LocalizationManager(defaults: testDefaults.defaults, bundle: .main)
    }

    private func text(_ key: String, macOS majorVersion: Int, _ strings: LocalizationManager) -> String {
        strings.string(for: PermissionPane.key(key, majorVersion: majorVersion))
    }

    /// Where each language sends the user: System Settings' names before macOS 27 and from macOS 27 on.
    private static let paneNames: [String: (before: String, after: String)] = [
        "en": ("Privacy & Security › Accessibility", "Privacy & Security › Device Control and Data Access"),
        "fr": ("Confidentialité et sécurité › Accessibilité", "Confidentialité et sécurité › Contrôle de l’appareil et accès aux données"),
        "de": ("Datenschutz & Sicherheit › Bedienungshilfen", "Datenschutz & Sicherheit › Gerätesteuerung und Datenzugriff"),
        "es": ("Privacidad y seguridad › Accesibilidad", "Privacidad y seguridad › Control de dispositivos y acceso a datos"),
        "ja": ("「プライバシーとセキュリティ」›「アクセシビリティ」", "「プライバシーとセキュリティ」›「デバイスの制御とデータへのアクセス」"),
        "ko": ("개인정보 보호 및 보안 › 손쉬운 사용", "개인정보 보호 및 보안 › 기기 제어 및 데이터 접근"),
        "pt-BR": ("Privacidade e Segurança › Acessibilidade", "Privacidade e Segurança › Controle do Dispositivo e Acesso a Dados"),
        "zh-Hans": ("“隐私与安全性” › “辅助功能”", "“隐私与安全” › “设备控制和数据访问”"),
    ]

    func testMacOS14Through26KeepTheKeyAndMacOS27AndLaterUseTheirOwn() {
        XCTAssertEqual(PermissionPane.key("permission.waiting", majorVersion: 14), "permission.waiting")
        XCTAssertEqual(PermissionPane.key("permission.waiting", majorVersion: 26), "permission.waiting")
        XCTAssertEqual(PermissionPane.key("permission.waiting", majorVersion: 27), "permission.waiting.macOS27")
        XCTAssertEqual(PermissionPane.key("onboarding.needsAccess", majorVersion: 28), "onboarding.needsAccess.macOS27")
    }

    func testTheDefaultFollowsThisMac() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(PermissionPane.systemMajorVersion, major)
        XCTAssertEqual(PermissionPane.key("permission.waiting"), PermissionPane.key("permission.waiting", majorVersion: major))
    }

    func testEnglishNamesAccessibilityBeforeMacOS27AndDeviceControlFromIt() {
        let english = strings("en")
        XCTAssertEqual(
            text("permission.waiting", macOS: 26, english),
            "Waiting for access… turn on Rote under Privacy & Security › Accessibility"
        )
        XCTAssertEqual(
            text("permission.waiting", macOS: 27, english),
            "Waiting for access… turn on Rote under Privacy & Security › Device Control and Data Access"
        )
    }

    func testGermanNamesBedienungshilfenBeforeMacOS27AndGeraetesteuerungFromIt() {
        let german = strings("de")
        XCTAssertEqual(
            text("permission.waiting", macOS: 26, german),
            "Warten auf Zugriff … Aktivieren Sie Rote unter Datenschutz & Sicherheit › Bedienungshilfen"
        )
        XCTAssertEqual(
            text("permission.waiting", macOS: 27, german),
            "Warten auf Zugriff … Aktivieren Sie Rote unter Datenschutz & Sicherheit › Gerätesteuerung und Datenzugriff"
        )
    }

    func testEveryLanguageNamesThePaneAsSystemSettingsDoesOnEachSideOfTheRename() {
        XCTAssertEqual(Set(Self.paneNames.keys), Set(LocalizationManager.supportedCodes))
        for code in LocalizationManager.supportedCodes {
            let strings = strings(code)
            guard let pane = Self.paneNames[code] else { continue }
            for key in ["permission.waiting", "onboarding.needsAccess"] {
                let before = text(key, macOS: 26, strings)
                let after = text(key, macOS: 27, strings)
                XCTAssertTrue(before.contains(pane.before), "\(code) \(key) before macOS 27: \(before)")
                XCTAssertTrue(after.contains(pane.after), "\(code) \(key) on macOS 27: \(after)")
                XCTAssertFalse(after.contains(pane.before), "\(code) \(key) on macOS 27: \(after)")
                XCTAssertTrue(after.contains("Rote"), "\(code) \(key) on macOS 27: \(after)")
                XCTAssertFalse(after.contains(".macOS27"), "\(code) \(key) shows its key: \(after)")
            }
        }
    }

    /// The rest of each sentence is unchanged: only the pane's name differs between the two keys.
    func testOnlyThePaneNameChangesOnMacOS27() {
        for code in LocalizationManager.supportedCodes {
            let strings = strings(code)
            guard let pane = Self.paneNames[code] else { continue }
            for key in ["permission.waiting", "onboarding.needsAccess"] {
                let before = text(key, macOS: 26, strings)
                let after = text(key, macOS: 27, strings)
                XCTAssertEqual(before.replacingOccurrences(of: pane.before, with: pane.after), after, "\(code) \(key)")
            }
        }
    }
}
