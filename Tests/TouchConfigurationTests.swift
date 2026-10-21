import Foundation

@main
private enum TouchConfigurationTests {
    static func main() {
        let suiteName = "UT99TouchConfigurationTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("defaults suite unavailable")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        require(UT99TouchConfiguration.load(from: defaults) == .standard, "standard configuration missing")
        var legacy = UT99TouchConfiguration.standard
        legacy.movementDeadZone = 0.28
        legacy.save(to: defaults)
        require(UT99TouchConfiguration.load(from: defaults).movementDeadZone == 0.04,
                "legacy movement response was not migrated")
        var legacyLook = UT99TouchConfiguration.standard
        legacyLook.lookDeadZone = 0.0025
        legacyLook.save(to: defaults)
        require(UT99TouchConfiguration.load(from: defaults).lookDeadZone == UT99TouchConfiguration.standard.lookDeadZone,
                "legacy floating-look dead zone was not migrated")
        var stored = UT99TouchConfiguration.standard
        stored.leftHanded = true
        stored.hiddenActions = ["scoreboard", "crouch"]
        stored.lookAcceleration = 0.8
        stored.lookDeadZone = 0.006
        stored.movementDeadZone = 0.22
        stored.autoHideForController = false
        stored.save(to: defaults)
        require(UT99TouchConfiguration.load(from: defaults) == stored, "configuration did not persist")

        var unsafe = stored
        unsafe.lookAcceleration = 99
        unsafe.lookDeadZone = -1
        unsafe.movementDeadZone = 2
        let clamped = unsafe.sanitized()
        require(clamped.lookAcceleration == 1.5, "acceleration upper bound missing")
        require(clamped.lookDeadZone == 0, "look dead-zone lower bound missing")
        require(clamped.movementDeadZone == 0.45, "movement dead-zone upper bound missing")

        let dead = UT99TouchInputTuning.transformedLook(
            CGPoint(x: 0.001, y: 0.001), sensitivity: 1,
            configuration: stored, invertY: false
        )
        require(dead.x == 0 && dead.y == 0, "look dead zone did not suppress drift")
        let slow = UT99TouchInputTuning.transformedLook(
            CGPoint(x: 0.02, y: 0.01), sensitivity: 1,
            configuration: stored, invertY: false
        )
        let fast = UT99TouchInputTuning.transformedLook(
            CGPoint(x: 0.20, y: 0.10), sensitivity: 1,
            configuration: stored, invertY: false
        )
        require(fast.x / 10 > slow.x, "acceleration did not increase fast-swipe gain")
        let inverted = UT99TouchInputTuning.transformedLook(
            CGPoint(x: 0.02, y: 0.01), sensitivity: 1,
            configuration: stored, invertY: true
        )
        require(inverted.x == slow.x && inverted.y == -slow.y, "invert Y changed the wrong axis")

        let stickDead = UT99TouchInputTuning.floatingStickLook(CGPoint(x: 0.02, y: 0))
        let stickFine = UT99TouchInputTuning.floatingStickLook(CGPoint(x: 0.10, y: 0))
        let stickFull = UT99TouchInputTuning.floatingStickLook(CGPoint(x: 1, y: 0))
        require(stickDead.x == 0 && stickDead.y == 0, "floating stick did not reject resting noise")
        require(stickFine.x > 0.0005, "floating stick did not respond early")
        require(abs(stickFull.x - 0.0065) < 0.00001, "floating stick maximum was not bounded")

        let forward = UT99TouchInputTuning.controllerMovement(CGPoint(x: 0.11, y: 0.92))
        let diagonal = UT99TouchInputTuning.controllerMovement(CGPoint(x: 0.55, y: 0.82))
        let drift = UT99TouchInputTuning.controllerMovement(CGPoint(x: 0.08, y: -0.07))
        let menuDrift = UT99TouchInputTuning.controllerMenuCursor(CGPoint(x: 0.09, y: -0.08))
        let menuMove = UT99TouchInputTuning.controllerMenuCursor(CGPoint(x: 0.20, y: 0.03))
        require(forward.x == 0 && forward.y == 0.92, "controller forward wobble was not suppressed")
        require(diagonal.x == 0.55 && diagonal.y == 0.82, "deliberate controller diagonal was changed")
        require(drift.x == 0 && drift.y == 0, "controller resting drift was not suppressed")
        require(menuDrift.x == 0 && menuDrift.y == 0, "menu cursor resting drift was not suppressed")
        require(menuMove.x == 0.20 && menuMove.y == 0.03, "menu cursor deliberate movement changed")

        verifyDodge(defaults: defaults)
        verifyTouchFirstHost(defaults: defaults)

        print("UT99 touch configuration PASS persistence=true migration=true clamping=true deadZone=true acceleration=true invertY=true floatingCurve=true controllerCardinal=true dodge=true")
    }

    private static func verifyDodge(defaults: UserDefaults) {
        // Configurations saved before the DODGE pad existed must still load,
        // picking up the standard dodge settings.
        let legacyJSON = """
        {"leftHanded":true,"hiddenActions":["scoreboard"],"lookAcceleration":0.45,\
        "lookDeadZone":0.00025,"movementDeadZone":0.04,"autoHideForController":true}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: UT99TouchConfiguration.defaultsKey)
        let migrated = UT99TouchConfiguration.load(from: defaults)
        require(migrated.leftHanded, "legacy configuration lost its saved fields")
        require(migrated.dodgeSwipeDistance == 18 && !migrated.dodgeSideOnly &&
                migrated.dodgeHaptics && migrated.dodgeStepMilliseconds == 50,
                "legacy configuration did not take standard dodge settings")
        require(!migrated.flickDodgeEnabled && migrated.flickDodgeDistance == 40 &&
                migrated.flickDodgeMilliseconds == 150 && migrated.customCommand == "suicide",
                "legacy configuration did not take standard flick and CUSTOM settings")
        require(UT99TouchConfiguration.standard.hiddenActions.isSuperset(of: ["dodge", "walk", "customCommand"]),
                "DODGE pad, WALK and CUSTOM must start hidden outside the BT layout")

        var dodge = UT99TouchConfiguration.standard
        dodge.dodgeSwipeDistance = 26
        dodge.dodgeSideOnly = true
        dodge.dodgeHaptics = false
        dodge.dodgeStepMilliseconds = 70
        dodge.hiddenActions = ["dodge"]
        dodge.flickDodgeEnabled = false
        dodge.flickDodgeDistance = 55
        dodge.flickDodgeMilliseconds = 120
        dodge.customCommand = "mutate checkpoint"
        dodge.fireButtonsDodge = true
        dodge.save(to: defaults)
        require(UT99TouchConfiguration.load(from: defaults) == dodge, "dodge settings did not persist")

        var unsafe = dodge
        unsafe.dodgeSwipeDistance = 500
        unsafe.dodgeStepMilliseconds = 1
        require(unsafe.sanitized().dodgeSwipeDistance == 48, "dodge swipe upper bound missing")
        require(unsafe.sanitized().dodgeStepMilliseconds == UT99DodgePlan.minimumStepMilliseconds,
                "dodge step lower bound missing")
        unsafe.dodgeSwipeDistance = 0
        unsafe.dodgeStepMilliseconds = 900
        require(unsafe.sanitized().dodgeSwipeDistance == 8, "dodge swipe lower bound missing")
        require(unsafe.sanitized().dodgeStepMilliseconds == UT99DodgePlan.maximumStepMilliseconds,
                "dodge step upper bound missing")
        require(UT99DodgePlan.maximumStepMilliseconds * 2 < UT99DodgePlan.dodgeClickWindowMilliseconds,
                "slowest double-tap would miss DodgeClickTime")

        // UIKit Y grows downward: a negative Y is an upward (forward) swipe.
        func classify(_ x: CGFloat, _ y: CGFloat, sideOnly: Bool = false) -> UT99DodgeDirection? {
            UT99DodgeGesture.direction(for: CGPoint(x: x, y: y), threshold: 18, sideOnly: sideOnly)
        }
        require(classify(-18, 0) == .left && classify(18, 0) == .right, "side swipes misclassified")
        require(classify(0, -18) == .forward && classify(0, 18) == .back, "vertical swipes misclassified")
        require(classify(-17.9, 0) == nil && classify(0, 0) == nil, "swipe fired before the threshold")
        require(classify(-20, -12) == .left, "a slightly rising side swipe must stay a side dodge")
        require(classify(10, -24) == .forward, "dominant vertical swipe misclassified")
        require(classify(0, -40, sideOnly: true) == nil, "side-only mode fired a forward dodge")
        require(classify(-22, 30, sideOnly: true) == nil, "side-only mode fired on a mostly vertical swipe")
        require(classify(30, -22, sideOnly: true) == .right, "side-only mode dropped a side swipe")
        for direction in UT99DodgeDirection.allCases {
            require(direction.opposite.opposite == direction && direction.opposite != direction,
                    "dodge opposite is not an involution")
        }

        // Idle stick: down, up, down on separate steps.
        typealias Edge = UT99DodgePlan.Edge
        require(UT99DodgePlan.edges(targetHeld: false, oppositeHeld: false, stepMilliseconds: 50) == [
            Edge(atMilliseconds: 0, key: .target, pressed: true),
            Edge(atMilliseconds: 50, key: .target, pressed: false),
            Edge(atMilliseconds: 100, key: .target, pressed: true),
        ], "idle double-tap plan changed")
        require(UT99DodgePlan.durationMilliseconds(targetHeld: false, oppositeHeld: false, stepMilliseconds: 50) == 150,
                "idle dodge must hold the second tap for one step")
        // The stick already strafes toward the dodge and away from it: lift
        // both first so the tap starts from a clean key-up.
        let held = UT99DodgePlan.edges(targetHeld: true, oppositeHeld: true, stepMilliseconds: 40)
        require(held == [
            Edge(atMilliseconds: 0, key: .target, pressed: false),
            Edge(atMilliseconds: 0, key: .opposite, pressed: false),
            Edge(atMilliseconds: 40, key: .target, pressed: true),
            Edge(atMilliseconds: 80, key: .target, pressed: false),
            Edge(atMilliseconds: 120, key: .target, pressed: true),
        ], "held-stick double-tap plan changed")
        let presses = held.filter { $0.key == .target && $0.pressed }.map(\.atMilliseconds)
        require(presses.count == 2 && presses[1] - presses[0] < UT99DodgePlan.dodgeClickWindowMilliseconds,
                "double-tap presses fall outside DodgeClickTime")
        let clamped = UT99DodgePlan.edges(targetHeld: false, oppositeHeld: false, stepMilliseconds: 5)
        require(clamped.map(\.atMilliseconds) == [0, 20, 40], "dodge step was not clamped")

        verifyBunnyTrack()

        // Hand-back after the tap: the target is physically down, the
        // opposite is up; both return to whatever the stick holds now.
        require(UT99DodgePlan.restore(targetHeld: true, oppositeHeld: false).isEmpty,
                "restore must leave a still-held target down")
        let released = UT99DodgePlan.restore(targetHeld: false, oppositeHeld: true)
        require(released.count == 2 && released[0].key == .target && !released[0].pressed &&
                released[1].key == .opposite && released[1].pressed,
                "restore must lift the target and give the opposite back to the stick")
    }

    private static func verifyBunnyTrack() {
        // The BT preset hides combat clutter and keeps the BT tools.
        let preset = UT99TouchConfiguration.standard.applyingBunnyTrackPreset()
        require(preset.hiddenActions == UT99TouchConfiguration.bunnyTrackHiddenActions, "BT preset hidden set changed")
        require(!preset.hiddenActions.contains("walk") && !preset.hiddenActions.contains("customCommand") &&
                !preset.hiddenActions.contains("jump") && !preset.hiddenActions.contains("crouch") &&
                !preset.hiddenActions.contains("primaryFire"),
                "BT preset hid a control a trick-jump run needs")
        require(!preset.flickDodgeEnabled && preset.lookAcceleration == 0.2, "BT preset look tuning changed")
        require(preset.fireButtonsDodge && !preset.hiddenActions.contains("alternateFire") &&
                !preset.hiddenActions.contains("dodge"),
                "BT preset must show ◀ DODGE (ALT) and DODGE ▶ buttons")
        require(preset.hiddenActions.contains("leftPrimaryFire"), "BT keeps FIRE on the right thumb only")
        require(!preset.hiddenActions.contains("dodgeForward") &&
                UT99TouchConfiguration.standard.hiddenActions.contains("dodgeForward"),
                "▲ DODGE belongs to the BT layout only")

        // Window-state learner: keeps the word constant within each state
        // and different between them, preferring a one-bit flag.
        var learner = UT99ViewportStateLearner()
        learner.add([7, 100, 0x10, 5], menu: true)
        learner.add([7, 200, 0x00, 5], menu: false)
        require(learner.learned == nil, "learned from a single sample per state")
        learner.add([7, 300, 0x10, 5], menu: true)
        learner.add([7, 400, 0x00, 5], menu: false)
        require(learner.learned == UT99ViewportStateLearner.Learned(offset: 8, menuValue: 0x10, gameValue: 0),
                "window-state word not learned")
        require(learner.isMenu(word: 0x10) == true && learner.isMenu(word: 0) == false &&
                learner.isMenu(word: 3) == nil, "learned word misread")
        learner.add([7, 500, 0x00, 5], menu: true)
        require(learner.learned == nil, "a contradicting sample kept a wrong word")
        require(!UT99TouchConfiguration.standard.fireButtonsDodge, "FIRE must shoot outside the BT layout")
        require(UT99TouchConfiguration.bunnyTrackHiddenActions.isSubset(of: UT99TouchConfiguration.supportedActionIDs),
                "BT preset names an unknown control")

        // Look-side flick: fast, long and clearly sideways dodges; anything
        // else stays looking.
        func flick(_ x: CGFloat, _ y: CGFloat, _ ms: Double) -> UT99DodgeDirection? {
            UT99FlickDodge.direction(for: CGPoint(x: x, y: y), elapsedMilliseconds: ms,
                                     distance: 40, windowMilliseconds: 150)
        }
        require(flick(-40, 0, 100) == .left && flick(45, 10, 150) == .right, "sideways flick did not dodge")
        require(flick(39, 0, 50) == nil, "short flick dodged")
        require(flick(80, 0, 151) == nil, "slow swipe dodged instead of looking")
        require(flick(50, 30, 80) == nil, "diagonal aim correction dodged")
        require(flick(0, -80, 50) == nil, "vertical flick dodged")

        // User.ini: replace the two bindings in [Engine.Input] and nothing else.
        let ini = "[Engine.Input]\r\nAliases[0]=(Command=\"Button bFire\",Alias=Fire)\r\nHome=\r\nInsert=OldThing\r\nW=MoveForward\r\n[Engine.Console]\r\nInsert=Untouched\r\n"
        let bound = UT99TouchKeyBindings.applying(to: ini, customCommand: "suicide")
        require(bound.contains("\r\nHome=Walking\r\n") && bound.contains("\r\nInsert=suicide\r\n"),
                "WALK/CUSTOM bindings were not written")
        require(bound.contains("W=MoveForward\r\n") && bound.contains("[Engine.Console]\r\nInsert=Untouched"),
                "binding rewrite touched other lines or sections")
        require(UT99TouchKeyBindings.applying(to: bound, customCommand: "suicide") == bound,
                "binding rewrite is not idempotent")
        let added = UT99TouchKeyBindings.applying(to: "[Engine.Input]\nW=MoveForward\n", customCommand: "mutate cp")
        require(added == "[Engine.Input]\nHome=Walking\nInsert=mutate cp\nW=MoveForward\n",
                "missing bindings were not added under [Engine.Input]")
        let section = UT99TouchKeyBindings.applying(to: "[URL]\nMap=Index.unr", customCommand: "suicide")
        require(section.hasSuffix("\n\n[Engine.Input]\nHome=Walking\nInsert=suicide"),
                "missing [Engine.Input] section was not appended")
        require(UT99TouchKeyBindings.sanitizedCommand("  suicide\nquit ") == "suicide quit",
                "command newline was not neutralized")
        require(UT99TouchKeyBindings.sanitizedCommand(String(repeating: "x", count: 500)).count ==
                UT99TouchKeyBindings.maximumCommandLength, "command length was not bounded")
    }

    private static func verifyTouchFirstHost(defaults: UserDefaults) {
        let standard = UT99TouchConfiguration.standard
        require(standard.customHoldToConfirm && standard.autoProfileByMap && standard.autoMenuSwitch,
                "touch-first defaults changed")
        var changed = standard
        changed.customHoldToConfirm = false
        changed.autoProfileByMap = false
        changed.autoMenuSwitch = false
        changed.save(to: defaults)
        require(UT99TouchConfiguration.load(from: defaults) == changed, "touch-first settings did not persist")

        // Profile by map.
        require(UT99TouchProfileName.forMap("CTF-BT-Andacs") == UT99TouchProfileName.bunnyTrack, "CTF-BT map missed")
        require(UT99TouchProfileName.forMap("ctf-bt-(ice)-v2") == UT99TouchProfileName.bunnyTrack, "lowercase BT map missed")
        require(UT99TouchProfileName.forMap("BT-Mesablanca") == UT99TouchProfileName.bunnyTrack, "bare BT map missed")
        require(UT99TouchProfileName.forMap("CTF-Face") == UT99TouchProfileName.standard, "CTF map treated as BT")
        require(UT99TouchProfileName.forMap("DM-Deck16][") == UT99TouchProfileName.standard, "DM map treated as BT")

        // Movement stick: a slightly off-center forward push runs straight;
        // only a clearly diagonal push holds two keys.
        func move(_ degrees: Double) -> Set<UT99DodgeDirection> {
            let radians = degrees * .pi / 180
            return UT99TouchMovement.directions(for: CGPoint(x: sin(radians), y: cos(radians)), deadZone: 0.04)
        }
        require(move(0) == [.forward] && move(20) == [.forward] && move(-25) == [.forward],
                "near-forward push strafed")
        require(move(45) == [.forward, .right] && move(-45) == [.forward, .left], "diagonal lost")
        require(move(90) == [.right] && move(75) == [.right] && move(-100) == [.left], "strafe not snapped")
        require(move(180) == [.back] && move(160) == [.back] && move(135) == [.back, .right], "back not snapped")
        require(UT99TouchMovement.directions(for: CGPoint(x: 0.02, y: 0.03), deadZone: 0.04).isEmpty,
                "dead zone ignored")

        // UT log lines.
        typealias Event = UT99EngineLogEvent
        func event(_ line: String) -> Event? { UT99EngineLogWatch.event(in: line) }
        require(event("Log: LoadMap: CTF-BT-Andacs?Name=Player?Class=Botpack.TMale1") == .map("CTF-BT-Andacs"),
                "LoadMap line not parsed")
        require(event("Log: Browse: DM-Deck16][.unr?Game=Botpack.DeathMatchPlus") == .map("DM-Deck16]["),
                "Browse map with .unr not parsed")
        require(event("Browse: 203.0.113.7:7777/?Name=Player") == .server("203.0.113.7:7777"), "server join not parsed")
        require(event("Log: Browse: unreal://203.0.113.7:7778/CTF-BT-x?Name=P") == .server("203.0.113.7:7778"),
                "unreal:// server join not parsed")
        require(event("Log: LoadMap: 203.0.113.7:7777/CTF-BT-Andacs?Name=P?Class=Botpack.TMale1") == .map("CTF-BT-Andacs"),
                "network client map load not parsed")
        require(event("LoadMap: unreal://bt.example.net:7777/CTF-BT-x.unr?Name=P") == .map("CTF-BT-x"),
                "network client map load by host name not parsed")
        require(event("Log: LoadMap: Entry") == .titleMap && event("Log: Browse: UT-Logo-Map.unr") == .titleMap,
                "title maps must be reported as title maps, not as a map to play")
        require(event("UT99 engine log map=CTF-BT-Andacs LoadMap: CTF-BT-Andacs") == nil,
                "the host's own log lines must be ignored")
        require(event("Log: Spawning game: Botpack.CTFGame") == nil, "unrelated line produced an event")
        require(!UT99EngineLogWatch.isServerAddress("300.1.1.1:7777") &&
                UT99EngineLogWatch.isServerAddress("1.2.3.4") &&
                !UT99EngineLogWatch.isServerAddress("1.2.3.4:99999"), "server address check wrong (port optional, must be valid)")

        // Recent servers: newest first, de-duplicated, bounded, map kept.
        var recent: [UT99RecentServer] = []
        recent = UT99RecentServer.recording("1.1.1.1:7777", map: "CTF-BT-A", in: recent)
        recent = UT99RecentServer.recording("2.2.2.2:7777", map: nil, in: recent)
        recent = UT99RecentServer.recording("1.1.1.1:7777", map: nil, in: recent)
        require(recent.map(\.address) == ["1.1.1.1:7777", "2.2.2.2:7777"], "recent servers not newest-first")
        require(recent[0].map == "CTF-BT-A", "rejoin lost the server's map")
        for index in 0..<10 {
            recent = UT99RecentServer.recording("10.0.0.\(index):7777", map: nil, in: recent)
        }
        require(recent.count == UT99RecentServer.maximumCount, "recent servers not bounded")
        UT99RecentServer.save(recent, to: defaults)
        require(UT99RecentServer.load(from: defaults) == recent, "recent servers did not persist")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("UT99 touch configuration FAIL: \(message)\n", stderr)
        exit(1)
    }
}
