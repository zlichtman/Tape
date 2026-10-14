import XCTest
@testable import TapeEngine

final class SettingsAndUpdateTests: XCTestCase {
    func testSearchIgnoresCaseDiacriticsAndPunctuation() {
        XCTAssertEqual(SettingsSearch.matches("ACCÉSSIBILITY!"), SettingsSearch.matches("accessibility"))
        XCTAssertTrue(SettingsSearch.matches("  -- ").isEmpty)
    }
    func testSearchRequiresEveryWordAcrossTitleAndKeywords() {
        XCTAssertEqual(SettingsSearch.matches("automatic download").map(\.card), ["Updates"])
        XCTAssertEqual(SettingsSearch.matches("layout gap").map(\.card), ["Spacing"])
        XCTAssertEqual(SettingsSearch.matches("apps select").map(\.card), ["Managed Apps", "Managed Windows"])
        XCTAssertTrue(SettingsSearch.matches("width permission").isEmpty)
    }
    func testSearchCardTitlesRankFirstAndHaveUniqueAnchors() {
        XCTAssertEqual(SettingsSearch.matches("focus").first?.card, "Focus")
        XCTAssertEqual(Set(SettingsSearch.entries.map(\.id)).count, SettingsSearch.entries.count)
    }
    func testUpdateVersionAndBuildMetadataRejectAmbiguity() {
        XCTAssertEqual(ReleaseRevision.version(fromTag: "v1.1"), "1.1")
        XCTAssertNil(ReleaseRevision.version(fromTag: "v1.1-beta"))
        XCTAssertNil(ReleaseRevision.version(fromTag: "v1..2"))
        XCTAssertEqual(ReleaseRevision.build(in: "Release\r\n<!-- tape-build:2 -->\r\n"), 2)
        XCTAssertNil(ReleaseRevision.build(in: "<!-- tape-build:2 -->\n<!-- tape-build:3 -->"))
        XCTAssertNil(ReleaseRevision.build(in: "<!-- tape-build:0 -->"))
        XCTAssertTrue(ReleaseRevision.isNewer(2, than: 1))
        XCTAssertFalse(ReleaseRevision.isNewer(1, than: 2))
    }
    func testUpdateSelectionKeepsTheSameMajorAndNewestBuild() {
        let candidates: [ReleaseRevision.Candidate] = [
            .init(tag: "v1.2", body: "<!-- tape-build:2 -->", draft: false, prerelease: false),
            .init(tag: "v2.9", body: "<!-- tape-build:9 -->", draft: false, prerelease: false),
            .init(tag: "v1.3", body: "<!-- tape-build:3 -->", draft: true, prerelease: false),
        ]
        XCTAssertEqual(ReleaseRevision.newest(in: candidates, major: 1)?.build, 2)
    }
}
