import Testing
@testable import TideBarCore

@Test func iconSizePresetsKeepArtworkAndSlotsAligned() {
    #expect(IconSizePreset.compact.iconSide == 32)
    #expect(IconSizePreset.standard.iconSide == 40)
    #expect(IconSizePreset.spacious.iconSide == 48)
    #expect(IconSizePreset.allCases.allSatisfy { $0.iconSlot >= $0.iconSide + 10 })
    #expect(IconSizePreset.allCases.allSatisfy { $0.expandedHeight >= $0.iconSide + 24 })
}

@Test func tidelineBrightnessUsesThemeAwareAutomaticOpacity() {
    #expect(TideLineBrightness.automatic.opacity(isDark: false) > TideLineBrightness.automatic.opacity(isDark: true))
    #expect(TideLineBrightness.low.opacity(isDark: false) < TideLineBrightness.standard.opacity(isDark: false))
    #expect(TideLineBrightness.high.opacity(isDark: true) == 1)
}

@Test func animationPresetsHaveOrderedSpeedFactors() {
    #expect(AnimationPreset.gentle.speedFactor < AnimationPreset.standard.speedFactor)
    #expect(AnimationPreset.standard.speedFactor < AnimationPreset.fast.speedFactor)
}

@Test func reducedMotionPreferenceCanOverrideSystemValue() {
    #expect(ReducedMotionPreference.automatic.isEnabled(systemValue: true))
    #expect(!ReducedMotionPreference.automatic.isEnabled(systemValue: false))
    #expect(!ReducedMotionPreference.alwaysOff.isEnabled(systemValue: true))
    #expect(ReducedMotionPreference.alwaysOn.isEnabled(systemValue: false))
}
