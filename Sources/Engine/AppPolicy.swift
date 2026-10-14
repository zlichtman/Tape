import Foundation

public struct AppPolicy: Codable, Equatable, Sendable {
    public var manageAll = true
    public var selected: Set<String> = []
    public var excluded: Set<String> = []
    public init() {}
    public func manages(_ bundleID: String?) -> Bool {
        guard let bundleID else { return manageAll }
        return manageAll ? !excluded.contains(bundleID) : selected.contains(bundleID)
    }
    public mutating func setManaged(_ enabled: Bool, bundleID: String) {
        if enabled { selected.insert(bundleID); excluded.remove(bundleID) }
        else { selected.remove(bundleID); excluded.insert(bundleID) }
    }
}
