import AppKit
import CoreText

/// Monospaced fonts for the console. Fira Code ships inside the app (SIL Open Font License)
/// and is registered for this process only; any installed monospaced family can replace it.
public enum ConsoleFonts {
    public static let defaultFamily = "Fira Code"
    /// The system's SF Mono is not listed as a regular font family, so it gets a stable name.
    public static let systemFamily = "SF Mono"
    /// Whether consoles join characters such as `->` and `!=` into ligatures; off unless chosen.
    public static let ligaturesKey = "terminalLigatures"

    /// Registers the bundled fonts once. Safe to call repeatedly.
    @MainActor public static func registerBundled() {
        guard !registered else { return }
        registered = true
        guard let directory = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension.lowercased() == "ttf" }) else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
    @MainActor private static var registered = false

    /// Installed families whose regular face is fixed pitch, plus SF Mono, sorted by name.
    @MainActor public static func monospacedFamilies() -> [String] {
        registerBundled()
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let member = manager.availableMembers(ofFontFamily: family)?.first,
                  let name = member.first as? String,
                  let font = NSFont(name: name, size: 12) else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        return Array(Set(families + [systemFamily, defaultFamily])).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// A font from `family`, falling back to Fira Code and then SF Mono.
    @MainActor public static func font(family: String, size: CGFloat, weight: NSFont.Weight = .regular,
                                       ligatures: Bool = true) -> NSFont {
        registerBundled()
        for candidate in [family, defaultFamily] where candidate != systemFamily {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: candidate,
                .traits: [NSFontDescriptor.TraitKey.weight: weight],
            ])
            if let font = NSFont(descriptor: descriptor, size: size), font.familyName == candidate {
                return ligatures ? font : withoutLigatures(font)
            }
        }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Fira Code builds its ligatures from hundreds of contextual substitutions; without them a busy
    /// terminal redraws about two and a half times faster. Bold and italic faces keep the setting.
    private static func withoutLigatures(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [NSFontDescriptor.FeatureKey.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
