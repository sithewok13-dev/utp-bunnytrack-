import Foundation

struct UT99TouchConfiguration: Codable, Equatable {
    static let defaultsKey = "ut99.touch.configuration.v1"
    static let supportedActionIDs: Set<String> = [
        "primaryFire", "leftPrimaryFire", "alternateFire", "jump", "crouch", "dodge", "walk", "use",
        "nextWeapon", "previousWeapon", "scoreboard", "customCommand", "pause"
    ]
    /// Controls the Bunny Track layout hides: combat and inventory buttons a
    /// trick-jump run never needs, plus the DODGE pad the look-side flick
    /// replaces.
    static let bunnyTrackHiddenActions: Set<String> = [
        "leftPrimaryFire", "use", "nextWeapon", "previousWeapon", "scoreboard", "dodge"
    ]
    static let defaultCustomCommand = "suicide"

    var leftHanded: Bool
    var hiddenActions: Set<String>
    var lookAcceleration: Double
    var lookDeadZone: Double
    var movementDeadZone: Double
    var autoHideForController: Bool
    /// Swipe travel, in points, before the DODGE pad commits to a direction.
    var dodgeSwipeDistance: Double
    /// Limit the DODGE pad to left/right so a vertical slip can never fire a
    /// forward or backward dodge.
    var dodgeSideOnly: Bool
    var dodgeHaptics: Bool
    /// Spacing between the synthesized double-tap edges. Each edge must
    /// survive at least one engine tick, and the whole tap must still land
    /// inside UT's 0.25s DodgeClickTime.
    var dodgeStepMilliseconds: Int
    /// A fast sideways flick on the look side dodges instead of turning.
    var flickDodgeEnabled: Bool
    /// Horizontal travel, in points, a look-side flick needs to dodge.
    var flickDodgeDistance: Double
    /// A flick only dodges if it covers that distance within this window;
    /// slower movement stays ordinary looking.
    var flickDodgeMilliseconds: Int
    /// Console command bound to the CUSTOM button's key (Insert).
    var customCommand: String
    /// In gameplay ALT dodges left and FIRE dodges right instead of shooting.
    var fireButtonsDodge: Bool
    /// CUSTOM fires only after a short hold, so a stray touch cannot run it.
    var customHoldToConfirm: Bool
    /// Switch to the Bunny Track profile on BT maps and back elsewhere.
    var autoProfileByMap: Bool
    /// Follow UT's own menu/gameplay state instead of a manual switch.
    var autoMenuSwitch: Bool

    init(
        leftHanded: Bool,
        hiddenActions: Set<String>,
        lookAcceleration: Double,
        lookDeadZone: Double,
        movementDeadZone: Double,
        autoHideForController: Bool,
        dodgeSwipeDistance: Double = 18,
        dodgeSideOnly: Bool = false,
        dodgeHaptics: Bool = true,
        dodgeStepMilliseconds: Int = 50,
        flickDodgeEnabled: Bool = true,
        flickDodgeDistance: Double = 40,
        flickDodgeMilliseconds: Int = 150,
        customCommand: String = UT99TouchConfiguration.defaultCustomCommand,
        fireButtonsDodge: Bool = false,
        customHoldToConfirm: Bool = true,
        autoProfileByMap: Bool = true,
        autoMenuSwitch: Bool = true
    ) {
        self.leftHanded = leftHanded
        self.hiddenActions = hiddenActions
        self.lookAcceleration = lookAcceleration
        self.lookDeadZone = lookDeadZone
        self.movementDeadZone = movementDeadZone
        self.autoHideForController = autoHideForController
        self.dodgeSwipeDistance = dodgeSwipeDistance
        self.dodgeSideOnly = dodgeSideOnly
        self.dodgeHaptics = dodgeHaptics
        self.dodgeStepMilliseconds = dodgeStepMilliseconds
        self.flickDodgeEnabled = flickDodgeEnabled
        self.flickDodgeDistance = flickDodgeDistance
        self.flickDodgeMilliseconds = flickDodgeMilliseconds
        self.customCommand = customCommand
        self.fireButtonsDodge = fireButtonsDodge
        self.customHoldToConfirm = customHoldToConfirm
        self.autoProfileByMap = autoProfileByMap
        self.autoMenuSwitch = autoMenuSwitch
    }

    static let standard = UT99TouchConfiguration(
        leftHanded: false,
        // The look-side flick replaces the DODGE pad, and WALK and CUSTOM are
        // Bunny Track tools; the BT layout turns the last two on.
        hiddenActions: ["scoreboard", "dodge", "walk", "customCommand"],
        lookAcceleration: 0.45,
        lookDeadZone: 0.00025,
        movementDeadZone: 0.04,
        autoHideForController: true
    )

    func sanitized() -> UT99TouchConfiguration {
        UT99TouchConfiguration(
            leftHanded: leftHanded,
            hiddenActions: hiddenActions.intersection(Self.supportedActionIDs),
            lookAcceleration: min(max(lookAcceleration, 0), 1.5),
            lookDeadZone: min(max(lookDeadZone, 0), 0.03),
            movementDeadZone: min(max(movementDeadZone, 0.02), 0.45),
            autoHideForController: autoHideForController,
            dodgeSwipeDistance: min(max(dodgeSwipeDistance, 8), 48),
            dodgeSideOnly: dodgeSideOnly,
            dodgeHaptics: dodgeHaptics,
            dodgeStepMilliseconds: min(max(dodgeStepMilliseconds, UT99DodgePlan.minimumStepMilliseconds),
                                       UT99DodgePlan.maximumStepMilliseconds),
            flickDodgeEnabled: flickDodgeEnabled,
            flickDodgeDistance: min(max(flickDodgeDistance, 20), 90),
            flickDodgeMilliseconds: min(max(flickDodgeMilliseconds, 60), 300),
            customCommand: UT99TouchKeyBindings.sanitizedCommand(customCommand),
            fireButtonsDodge: fireButtonsDodge,
            customHoldToConfirm: customHoldToConfirm,
            autoProfileByMap: autoProfileByMap,
            autoMenuSwitch: autoMenuSwitch
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> UT99TouchConfiguration {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return .standard
        }
        var configuration = decoded.sanitized()
        // Preview builds seeded 28%, which required almost a third of the
        // stick radius before movement began. Migrate that exact old default
        // to the new roughly three-times-more-responsive threshold.
        if abs(configuration.movementDeadZone - 0.28) < 0.0001 ||
            abs(configuration.movementDeadZone - 0.09) < 0.0001 {
            configuration.movementDeadZone = Self.standard.movementDeadZone
        }
        // The first floating-look preview inherited the swipe surface's
        // 0.0025 threshold. Its stick publishes at most 0.010 per frame, so
        // that accidentally discarded the first quarter of thumb travel.
        if abs(configuration.lookDeadZone - 0.0025) < 0.00001 {
            configuration.lookDeadZone = Self.standard.lookDeadZone
        }
        // Preview builds exposed SCORE by default. Hide it once without
        // disturbing the player's saved positions or other visibility choices.
        let scoreMigrationKey = "ut99.touch.migration.hideScore.v1"
        if !defaults.bool(forKey: scoreMigrationKey) {
            configuration.hiddenActions.insert("scoreboard")
            defaults.set(true, forKey: scoreMigrationKey)
        }
        // The DODGE pad shipped visible before the look-side flick replaced
        // it; WALK and CUSTOM are new. Hide all three once, as for SCORE.
        let bunnyTrackMigrationKey = "ut99.touch.migration.bunnyTrackControls.v1"
        if !defaults.bool(forKey: bunnyTrackMigrationKey) {
            configuration.hiddenActions.formUnion(["dodge", "walk", "customCommand"])
            defaults.set(true, forKey: bunnyTrackMigrationKey)
        }
        configuration.save(to: defaults)
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        let value = sanitized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private enum CodingKeys: String, CodingKey {
        case leftHanded, hiddenActions, lookAcceleration, lookDeadZone, movementDeadZone, autoHideForController
        case dodgeSwipeDistance, dodgeSideOnly, dodgeHaptics, dodgeStepMilliseconds
        case flickDodgeEnabled, flickDodgeDistance, flickDodgeMilliseconds, customCommand, fireButtonsDodge
        case customHoldToConfirm, autoProfileByMap, autoMenuSwitch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leftHanded = try container.decode(Bool.self, forKey: .leftHanded)
        hiddenActions = Set(try container.decode([String].self, forKey: .hiddenActions))
        lookAcceleration = try container.decode(Double.self, forKey: .lookAcceleration)
        lookDeadZone = try container.decode(Double.self, forKey: .lookDeadZone)
        movementDeadZone = try container.decode(Double.self, forKey: .movementDeadZone)
        autoHideForController = try container.decode(Bool.self, forKey: .autoHideForController)
        // Dodge settings arrived after configurations and exported profiles
        // were already in the field. Missing keys take the standard values.
        let standard = Self.standard
        dodgeSwipeDistance = try container.decodeIfPresent(Double.self, forKey: .dodgeSwipeDistance)
            ?? standard.dodgeSwipeDistance
        dodgeSideOnly = try container.decodeIfPresent(Bool.self, forKey: .dodgeSideOnly) ?? standard.dodgeSideOnly
        dodgeHaptics = try container.decodeIfPresent(Bool.self, forKey: .dodgeHaptics) ?? standard.dodgeHaptics
        dodgeStepMilliseconds = try container.decodeIfPresent(Int.self, forKey: .dodgeStepMilliseconds)
            ?? standard.dodgeStepMilliseconds
        flickDodgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .flickDodgeEnabled)
            ?? standard.flickDodgeEnabled
        flickDodgeDistance = try container.decodeIfPresent(Double.self, forKey: .flickDodgeDistance)
            ?? standard.flickDodgeDistance
        flickDodgeMilliseconds = try container.decodeIfPresent(Int.self, forKey: .flickDodgeMilliseconds)
            ?? standard.flickDodgeMilliseconds
        customCommand = try container.decodeIfPresent(String.self, forKey: .customCommand)
            ?? standard.customCommand
        fireButtonsDodge = try container.decodeIfPresent(Bool.self, forKey: .fireButtonsDodge)
            ?? standard.fireButtonsDodge
        customHoldToConfirm = try container.decodeIfPresent(Bool.self, forKey: .customHoldToConfirm)
            ?? standard.customHoldToConfirm
        autoProfileByMap = try container.decodeIfPresent(Bool.self, forKey: .autoProfileByMap)
            ?? standard.autoProfileByMap
        autoMenuSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoMenuSwitch)
            ?? standard.autoMenuSwitch
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leftHanded, forKey: .leftHanded)
        try container.encode(hiddenActions.sorted(), forKey: .hiddenActions)
        try container.encode(lookAcceleration, forKey: .lookAcceleration)
        try container.encode(lookDeadZone, forKey: .lookDeadZone)
        try container.encode(movementDeadZone, forKey: .movementDeadZone)
        try container.encode(autoHideForController, forKey: .autoHideForController)
        try container.encode(dodgeSwipeDistance, forKey: .dodgeSwipeDistance)
        try container.encode(dodgeSideOnly, forKey: .dodgeSideOnly)
        try container.encode(dodgeHaptics, forKey: .dodgeHaptics)
        try container.encode(dodgeStepMilliseconds, forKey: .dodgeStepMilliseconds)
        try container.encode(flickDodgeEnabled, forKey: .flickDodgeEnabled)
        try container.encode(flickDodgeDistance, forKey: .flickDodgeDistance)
        try container.encode(flickDodgeMilliseconds, forKey: .flickDodgeMilliseconds)
        try container.encode(customCommand, forKey: .customCommand)
        try container.encode(fireButtonsDodge, forKey: .fireButtonsDodge)
        try container.encode(customHoldToConfirm, forKey: .customHoldToConfirm)
        try container.encode(autoProfileByMap, forKey: .autoProfileByMap)
        try container.encode(autoMenuSwitch, forKey: .autoMenuSwitch)
    }

    /// The Bunny Track preset: hide combat clutter, slow the look curve for
    /// precise lines, and dodge with a look-side flick or ALT (left) and
    /// FIRE (right).
    func applyingBunnyTrackPreset() -> UT99TouchConfiguration {
        var result = self
        result.hiddenActions = Self.bunnyTrackHiddenActions
        result.lookAcceleration = 0.2
        result.flickDodgeEnabled = true
        result.fireButtonsDodge = true
        return result.sanitized()
    }
}

/// Look-side flick recognition. A flick dodges only if it is fast, mostly
/// horizontal, and long enough; anything slower is ordinary looking.
enum UT99FlickDodge {
    static func direction(
        for translation: CGPoint,
        elapsedMilliseconds: Double,
        distance: CGFloat,
        windowMilliseconds: Double
    ) -> UT99DodgeDirection? {
        guard elapsedMilliseconds <= windowMilliseconds else { return nil }
        let horizontal = abs(translation.x)
        // A clearly sideways flick: at least twice as wide as it is tall, so
        // diagonal aim corrections never dodge.
        guard horizontal >= distance, horizontal >= abs(translation.y) * 2 else { return nil }
        return translation.x < 0 ? .left : .right
    }
}

/// Keys the WALK and CUSTOM buttons press, and the User.ini lines that bind
/// them. The host rewrites only these two lines under [Engine.Input] at each
/// engine start, so the buttons work whatever the player's other bindings.
enum UT99TouchKeyBindings {
    static let walkKeyName = "Home"
    static let customKeyName = "Insert"
    static let walkCommand = "Walking"
    static let maximumCommandLength = 120

    static func sanitizedCommand(_ command: String) -> String {
        let singleLine = command
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(singleLine.prefix(maximumCommandLength))
    }

    /// Return `ini` with `Home=Walking` and `Insert=<command>` set inside
    /// [Engine.Input], adding the lines (or the section) when missing.
    static func applying(to ini: String, customCommand: String) -> String {
        let wanted: [(key: String, value: String)] = [
            (walkKeyName, walkCommand),
            (customKeyName, sanitizedCommand(customCommand)),
        ]
        var lines = ini.components(separatedBy: "\n")
        let lineEnding = lines.first?.hasSuffix("\r") == true ? "\r" : ""
        func bare(_ line: String) -> String { line.hasSuffix("\r") ? String(line.dropLast()) : line }

        guard let header = lines.firstIndex(where: { bare($0).caseInsensitiveCompare("[Engine.Input]") == .orderedSame })
        else {
            if let last = lines.last, !bare(last).isEmpty { lines.append("") }
            lines.append("[Engine.Input]" + lineEnding)
            for binding in wanted { lines.append("\(binding.key)=\(binding.value)" + lineEnding) }
            return lines.joined(separator: "\n")
        }
        var end = lines.count
        for index in (header + 1)..<lines.count where bare(lines[index]).hasPrefix("[") {
            end = index
            break
        }
        var missing: [String] = []
        for binding in wanted {
            let prefix = binding.key.lowercased() + "="
            let replacement = "\(binding.key)=\(binding.value)"
            if let index = (header + 1..<end).first(where: { bare(lines[$0]).lowercased().hasPrefix(prefix) }) {
                let ending = lines[index].hasSuffix("\r") ? "\r" : ""
                lines[index] = replacement + ending
            } else {
                missing.append(replacement + lineEnding)
            }
        }
        lines.insert(contentsOf: missing, at: header + 1)
        return lines.joined(separator: "\n")
    }
}

/// A dodge relative to the player's view, matching UT's double-tap
/// directions on MoveForward, MoveBackward, StrafeLeft and StrafeRight.
enum UT99DodgeDirection: String, CaseIterable {
    case left, right, forward, back

    var opposite: UT99DodgeDirection {
        switch self {
        case .left: .right
        case .right: .left
        case .forward: .back
        case .back: .forward
        }
    }
}

enum UT99DodgeGesture {
    /// Classify a DODGE pad swipe. `translation` is in UIKit points, so a
    /// negative Y is an upward swipe. The dominant axis wins; nothing fires
    /// until the swipe has travelled `threshold` points along it.
    static func direction(
        for translation: CGPoint,
        threshold: CGFloat,
        sideOnly: Bool
    ) -> UT99DodgeDirection? {
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)
        if horizontal >= vertical {
            guard horizontal >= threshold, horizontal > 0 else { return nil }
            return translation.x < 0 ? .left : .right
        }
        guard !sideOnly, vertical >= threshold else { return nil }
        return translation.y < 0 ? .forward : .back
    }
}

/// The key edges that reproduce a keyboard double-tap on one movement key.
///
/// UT's PlayerPawn only sees a dodge when the key goes down, up, and down
/// again on separate ticks within DodgeClickTime. The movement stick may
/// already hold the target key (which must be lifted first) or its opposite
/// (which would cancel the axis), so both are released before the tap and
/// handed back to the stick afterwards.
enum UT99DodgePlan {
    enum Key: Equatable { case target, opposite }

    struct Edge: Equatable {
        let atMilliseconds: Int
        let key: Key
        let pressed: Bool
    }

    static let dodgeClickWindowMilliseconds = 250
    static let minimumStepMilliseconds = 20
    /// Two steps separate the taps, so this keeps them inside the window.
    static let maximumStepMilliseconds = 100

    static func edges(targetHeld: Bool, oppositeHeld: Bool, stepMilliseconds: Int) -> [Edge] {
        let step = min(max(stepMilliseconds, minimumStepMilliseconds), maximumStepMilliseconds)
        var result: [Edge] = []
        if targetHeld { result.append(Edge(atMilliseconds: 0, key: .target, pressed: false)) }
        if oppositeHeld { result.append(Edge(atMilliseconds: 0, key: .opposite, pressed: false)) }
        let start = targetHeld || oppositeHeld ? step : 0
        result.append(Edge(atMilliseconds: start, key: .target, pressed: true))
        result.append(Edge(atMilliseconds: start + step, key: .target, pressed: false))
        result.append(Edge(atMilliseconds: start + step * 2, key: .target, pressed: true))
        return result
    }

    /// When the stick takes its keys back: one step after the second tap so
    /// that press is also seen on its own tick.
    static func durationMilliseconds(targetHeld: Bool, oppositeHeld: Bool, stepMilliseconds: Int) -> Int {
        (edges(targetHeld: targetHeld, oppositeHeld: oppositeHeld, stepMilliseconds: stepMilliseconds)
            .last?.atMilliseconds ?? 0) + min(max(stepMilliseconds, minimumStepMilliseconds), maximumStepMilliseconds)
    }

    /// Edges that return both keys to whatever the stick holds now. The
    /// target is physically down after the tap; the opposite is up.
    static func restore(targetHeld: Bool, oppositeHeld: Bool) -> [(key: Key, pressed: Bool)] {
        var result: [(key: Key, pressed: Bool)] = []
        if !targetHeld { result.append((.target, false)) }
        if oppositeHeld { result.append((.opposite, true)) }
        return result
    }
}

enum UT99TouchInputTuning {
    static func controllerMenuCursor(
        _ value: CGPoint,
        deadZone: CGFloat = 0.14
    ) -> CGPoint {
        hypot(value.x, value.y) >= deadZone ? value : CGPoint(x: 0, y: 0)
    }

    /// Reject the small cross-axis wobble common near the cardinal directions
    /// of a physical thumbstick. Deliberate diagonals remain unchanged once
    /// the secondary axis passes 30 percent travel.
    static func controllerMovement(
        _ value: CGPoint,
        axisDeadZone: CGFloat = 0.12,
        cardinalThreshold: CGFloat = 0.30
    ) -> CGPoint {
        var result = CGPoint(
            x: abs(value.x) >= axisDeadZone ? value.x : 0,
            y: abs(value.y) >= axisDeadZone ? value.y : 0
        )
        if abs(result.y) > abs(result.x), abs(result.x) < cardinalThreshold {
            result.x = 0
        } else if abs(result.x) > abs(result.y), abs(result.y) < cardinalThreshold {
            result.y = 0
        }
        return result
    }

    /// Convert a radial stick into a bounded per-frame relative-look value.
    /// A small physical dead zone rejects resting noise, while the sub-linear
    /// curve responds early and the lower ceiling preserves control at full
    /// thumb travel.
    static func floatingStickLook(
        _ value: CGPoint,
        deadZone: CGFloat = 0.035,
        maximumPerFrame: CGFloat = 0.0065,
        exponent: CGFloat = 0.72
    ) -> CGPoint {
        let magnitude = hypot(value.x, value.y)
        guard magnitude > deadZone else { return CGPoint(x: 0, y: 0) }
        let direction = CGPoint(x: value.x / magnitude, y: value.y / magnitude)
        let normalized = min(max((magnitude - deadZone) / max(1 - deadZone, 0.001), 0), 1)
        let response = pow(normalized, exponent) * maximumPerFrame
        return CGPoint(x: direction.x * response, y: direction.y * response)
    }

    static func transformedLook(
        _ value: CGPoint,
        sensitivity: Double,
        configuration: UT99TouchConfiguration,
        invertY: Bool
    ) -> CGPoint {
        let config = configuration.sanitized()
        let magnitude = hypot(value.x, value.y)
        guard Double(magnitude) > config.lookDeadZone else { return CGPoint(x: 0, y: 0) }

        let clampedSensitivity = min(max(sensitivity, 0.25), 3.0)
        // Pan deltas are normalized against the live look surface. Scale their
        // speed into a bounded curve so slow aim stays precise while a quick
        // swipe can still turn fast enough for UT combat.
        let normalizedSpeed = min(Double(magnitude) * 12.0, 1.5)
        let gain = clampedSensitivity * (1.0 + config.lookAcceleration * normalizedSpeed)
        let yDirection: CGFloat = invertY ? -1 : 1
        return CGPoint(
            x: value.x * CGFloat(gain),
            y: value.y * CGFloat(gain) * yDirection
        )
    }
}

/// Built-in touch profiles. Each keeps its own layout and settings in the
/// named-profile store once it has been used.
enum UT99TouchProfileName {
    static let standard = "Standard"
    static let bunnyTrack = "Bunny Track"

    /// Bunny Track maps are conventionally CTF-BT-*; a few use a bare BT-*.
    static func isBunnyTrackMap(_ map: String) -> Bool {
        let upper = map.uppercased()
        return upper.hasPrefix("CTF-BT") || upper.hasPrefix("BT-")
    }

    static func forMap(_ map: String) -> String {
        isBunnyTrackMap(map) ? bunnyTrack : standard
    }
}

/// What the host learns from UT's own log: the map being loaded and the
/// server being joined. The engine is unmodified, so its log is the only
/// window onto this state.
enum UT99EngineLogEvent: Equatable {
    case map(String)
    case server(String)
    /// A title or transition map: no match is running and UT's menu is up.
    case titleMap
}

enum UT99EngineLogWatch {
    /// Title-screen and transition maps that say nothing about the game mode.
    static let neutralMaps: Set<String> = ["entry", "ut-logo-map", "index", "cityintro", "autoplay"]

    static func event(in line: String) -> UT99EngineLogEvent? {
        // The host's own NSLog lines share the redirected stderr file.
        guard !line.contains("UT99") else { return nil }
        guard let marker = ["LoadMap:", "Browse:"].lazy.compactMap({ line.range(of: $0) }).first else { return nil }
        var rest = line[marker.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
        if rest.lowercased().hasPrefix("unreal://") { rest = rest.dropFirst("unreal://".count) }
        // A network client loads "host:port/Map?options": the map is what
        // matters there, the join itself was already logged by Browse.
        if line[marker].hasPrefix("LoadMap") {
            let address = rest.prefix(while: { $0 != "?" && $0 != "#" })
            if let slash = address.lastIndex(of: "/") { rest = rest[rest.index(after: slash)...] }
        }
        let token = String(rest.prefix(while: { !$0.isWhitespace && $0 != "?" && $0 != "/" && $0 != "#" }))
        guard !token.isEmpty else { return nil }
        if isServerAddress(token) { return .server(token) }
        var map = token
        if map.lowercased().hasSuffix(".unr") { map = String(map.dropLast(4)) }
        guard !map.isEmpty else { return nil }
        if neutralMaps.contains(map.lowercased()) { return .titleMap }
        guard map.allSatisfy({ $0.isLetter || $0.isNumber || "-_[]().".contains($0) }) else { return nil }
        return .map(map)
    }

    /// IPv4 with a port, e.g. 203.0.113.7:7777.
    static func isServerAddress(_ token: String) -> Bool {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port) else { return false }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            guard let value = Int(octet), octet.count <= 3 else { return false }
            return (0...255).contains(value)
        }
    }
}

/// The last few servers joined, newest first, for one-tap reconnecting.
struct UT99RecentServer: Codable, Equatable {
    var address: String
    var map: String?

    static let defaultsKey = "ut99.recentServers.v1"
    static let maximumCount = 6

    static func recording(_ address: String, map: String?, in list: [UT99RecentServer]) -> [UT99RecentServer] {
        let previous = list.first { $0.address == address }
        var result = list.filter { $0.address != address }
        result.insert(UT99RecentServer(address: address, map: map ?? previous?.map), at: 0)
        return Array(result.prefix(maximumCount))
    }

    static func load(from defaults: UserDefaults = .standard) -> [UT99RecentServer] {
        guard let data = defaults.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([UT99RecentServer].self, from: data) else { return [] }
        return Array(list.filter { UT99EngineLogWatch.isServerAddress($0.address) }.prefix(maximumCount))
    }

    static func save(_ list: [UT99RecentServer], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Array(list.prefix(maximumCount))) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
