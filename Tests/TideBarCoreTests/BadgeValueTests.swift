import Testing
@testable import TideBarCore

@Test func badgeParseNumericStrings() {
    #expect(BadgeValue.parse("16") == .count(16))
    #expect(BadgeValue.parse(" 3 ") == .count(3))
    #expect(BadgeValue.parse("1") == .count(1))
}

@Test func badgeParseNonPositiveAndEmptyYieldsNil() {
    #expect(BadgeValue.parse(nil) == nil)
    #expect(BadgeValue.parse("") == nil)
    #expect(BadgeValue.parse("   ") == nil)
    #expect(BadgeValue.parse("0") == nil)
    #expect(BadgeValue.parse("-2") == nil)
}

@Test func badgeParseNonNumericYieldsDot() {
    #expect(BadgeValue.parse("•") == .dot)
    #expect(BadgeValue.parse("new") == .dot)
}

@Test func badgeParseMixedDigitsFallsBackToDot() {
    // 非纯数字不猜数字，退化为小圆点展示
    #expect(BadgeValue.parse("3条") == .dot)
    #expect(BadgeValue.parse("1.2") == .dot)
}
