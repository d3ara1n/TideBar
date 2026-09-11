import Foundation
import Testing
@testable import TideBarCore

@Test func widgetPayloadRoundTripsItsInstanceConfiguration() throws {
    let app = ItemReference(scheme: "application", payload: Data([1, 2, 3]))
    let configuration = ApplicationLauncherConfiguration(applications: [app])
    let payload = WidgetPayload(type: .applicationLauncher,
                                displayName: "Work",
                                configuration: try JSONEncoder().encode(configuration))
    let decoded = try JSONDecoder().decode(WidgetPayload.self,
                                           from: JSONEncoder().encode(payload))
    #expect(decoded == payload)
    let decodedConfiguration = try JSONDecoder().decode(ApplicationLauncherConfiguration.self,
                                                        from: decoded.configuration)
    #expect(decodedConfiguration.applications == [app])
}

@Test func widgetInstancesUseIndependentItemIDs() {
    let first = PinnedItemRecord(id: .resource(), kind: .widget,
                                 reference: ItemReference(scheme: "widget", payload: Data([1])),
                                 fallbackName: "One")
    let second = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: ItemReference(scheme: "widget", payload: Data([2])),
                                  fallbackName: "Two")
    #expect(first.id != second.id)
    #expect(first.kind == .widget)
}
