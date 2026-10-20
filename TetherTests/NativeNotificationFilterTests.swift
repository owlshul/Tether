import Testing
@testable import Tether

@MainActor
struct NativeNotificationFilterTests {
    @Test(arguments: [
        ("WhatsApp", "0|com.whatsapp|12|null|10345", true),
        ("Localized name", "10|com.whatsapp|-12||1010345", true),
        ("WhatsApp", "0|com.instagram.android|12|null|10346", false),
        ("WhatsApp Business", "0|com.whatsapp.w4b|12|null|10347", false),
        ("WhatsApp", "opaque-legacy-id", true),
        (" whatsapp ", "12", true),
        ("WhatsApp Business", "12", false),
        ("Instagram", "12", false),
    ])
    func recognizesOnlyPersonalWhatsApp(name: String, id: String, expected: Bool) {
        #expect(NativeNotificationFilter.isWhatsApp(appName: name, notificationId: id) == expected)
    }
}
