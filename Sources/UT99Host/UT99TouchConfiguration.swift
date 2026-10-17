import Foundation

struct UT99TouchConfiguration: Codable, Equatable {
    static let defaultsKey = "ut99.touch.configuration.v1"
    static let supportedActionIDs: Set<String> = [
        "primaryFire", "leftPrimaryFire", "alternateFire", "jump", "crouch", "dodge", "use",
        "nextWeapon", "previousWeapon", "scoreboard", "pause"
    ]

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
        dodgeStepMilliseconds: Int = 50
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
    }

    static let standard = UT99TouchConfiguration(
        leftHanded: false,
        hiddenActions: ["scoreboard"],
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
                                       UT99DodgePlan.maximumStepMilliseconds)
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
