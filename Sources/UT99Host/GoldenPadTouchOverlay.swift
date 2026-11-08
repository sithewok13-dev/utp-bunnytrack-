import UIKit

/// An EctoPad/SunPad-style control face mapped to UT-specific actions.
///
/// EctoPad's strength is its legible physical-controller hierarchy: one solid
/// translucent face, one restrained white rim, one centered mark, and an
/// obvious pressed state. Avoid stacking a symbol and caption into a badge.
private final class UT99TouchActionButton: UIButton {
    enum Role {
        case primary, secondary, utility, dPad, start
    }

    private let markView = UIImageView()
    private let actionLabel = UILabel()
    private var accent = UIColor.white
    private var foreground = UIColor.white
    private var visualRole: Role = .secondary
    private var pressed = false
    private var editing = false
    var onAccessibilityActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isOpaque = false
        layer.cornerCurve = .continuous

        markView.contentMode = .scaleAspectFit
        markView.isUserInteractionEnabled = false
        addSubview(markView)
        actionLabel.textAlignment = .center
        actionLabel.adjustsFontSizeToFitWidth = true
        actionLabel.minimumScaleFactor = 0.6
        actionLabel.numberOfLines = 2
        actionLabel.isUserInteractionEnabled = false
        addSubview(actionLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityActivate() -> Bool {
        guard let onAccessibilityActivate else { return super.accessibilityActivate() }
        onAccessibilityActivate()
        return true
    }

    func configure(symbol: String, title: String, accent: UIColor, foreground: UIColor, role: Role) {
        self.accent = accent
        self.foreground = foreground
        self.visualRole = role
        if role == .dPad {
            markView.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(weight: .bold)
            )
            actionLabel.text = nil
        } else {
            markView.image = nil
            actionLabel.text = title
        }
        setPressed(false)
    }

    func setPressed(_ pressed: Bool) {
        self.pressed = pressed
        applyAppearance()
    }

    func setEditing(_ editing: Bool) {
        self.editing = editing
        applyAppearance()
    }

    func setTitle(_ title: String) {
        guard visualRole != .dPad else { return }
        actionLabel.text = title
        accessibilityLabel = title
    }

    /// The house touch look (JK's `iosTouch.m`): a dark 22% face, a 1.5 pt
    /// white ring at 40% (FIRE's is warm red), white bold text at 85%. An
    /// untouched button sits at 65%, a touched one at 100%; OPACITY scales
    /// the whole overlay on top of that.
    static let idleAlpha: CGFloat = 0.65
    static let ringColor = UIColor(white: 1, alpha: 0.4)
    static let fireRingColor = UIColor(red: 1, green: 0.55, blue: 0.45, alpha: 0.6)

    private func applyAppearance() {
        backgroundColor = UIColor(white: pressed ? 1 : 0, alpha: pressed ? 0.18 : 0.22)
        markView.tintColor = UIColor(white: 1, alpha: 0.85)
        actionLabel.textColor = UIColor(white: 1, alpha: 0.85)
        layer.borderColor = editing
            ? UIColor(red: 0.35, green: 0.92, blue: 0.88, alpha: 0.96).cgColor
            : (visualRole == .primary ? Self.fireRingColor : Self.ringColor).cgColor
        layer.borderWidth = editing ? 3 : 1.5
        alpha = pressed || editing ? 1 : Self.idleAlpha
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        layer.cornerRadius = side / 2
        // The phone START/MENU surface is intentionally a wide EctoPad pill.
        // Its short side is below 54pt, but it must retain its caption; only
        // genuinely compact round controls collapse to an icon-only face.
        let compact = visualRole == .dPad
        let symbolSide = min(max(side * 0.34, 13), 22)
        markView.frame = CGRect(x: bounds.midX - symbolSide / 2,
                                y: bounds.midY - symbolSide / 2,
                                width: symbolSide,
                                height: symbolSide)
        // JK's IOSTouch_FontSize: 16 pt from a 40 pt radius, 13 from 25, else 10.
        let radius = side / 2
        let size: CGFloat = actionLabel.numberOfLines == 2 && actionLabel.text?.contains("\n") == true
            ? (radius >= 28 ? 10 : 9)
            : (radius >= 40 ? 16 : (radius >= 25 ? 13 : 10))
        actionLabel.font = .boldSystemFont(ofSize: size)
        actionLabel.frame = compact
            ? .zero
            : bounds.insetBy(dx: 4, dy: 3)
    }
}

/// The house wheel (JK and Sam, guide section 3.2): one slice per item,
/// clockwise from the bottom left, a cancel gap at the bottom, the game behind
/// dimmed. Outer radius at most 168 pt with a hole of 0.37 of it; the slice
/// pointed at pops out 10 pt; a light tick for each slice change.
final class UT99RadialWheelView: UIView {
    struct Item {
        let title: String
        var icon: UIImage? = nil
    }

    static let outerMax: CGFloat = 168
    static let innerFraction: CGFloat = 0.37
    static let pop: CGFloat = 10
    static let gapDegrees: CGFloat = 60
    static let deadRadius: CGFloat = 14
    static let cancel = -1

    var items: [Item] = [] { didSet { rebuild() } }
    var title = "" { didSet { refreshCenter() } }
    var tapHint = "tap one"
    var slideHint = "slide toward one"
    /// The item picked; nil when the wheel closes without a pick.
    var onFinish: ((Int?) -> Void)?
    /// Open to tap (true) or tracking a slide from the button (false).
    private(set) var tapMode = false
    private(set) var highlighted: Int?
    private var sliceLayers: [CAShapeLayer] = []
    private var sliceLabels: [UILabel] = []
    private var sliceIcons: [UIImageView?] = []
    private let centerTitle = UILabel()
    private let centerHint = UILabel()
    private let tick = UISelectionFeedbackGenerator()
    private var outerRadius: CGFloat = 0
    private var innerRadius: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        isHidden = true
        for label in [centerTitle, centerHint] {
            label.textAlignment = .center
            label.textColor = UIColor(white: 1, alpha: 0.9)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            addSubview(label)
        }
        centerTitle.font = .boldSystemFont(ofSize: 15)
        centerHint.font = .systemFont(ofSize: 10, weight: .medium)
        centerHint.textColor = UIColor(white: 1, alpha: 0.6)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOpen: Bool { !isHidden }

    func open(tapMode: Bool) {
        self.tapMode = tapMode
        highlighted = nil
        isHidden = false
        superview?.bringSubviewToFront(self)
        tick.prepare()
        setNeedsLayout()
        layoutIfNeeded()
        refreshLooks()
    }

    func close(picking index: Int?) {
        guard isOpen else { return }
        isHidden = true
        highlighted = nil
        onFinish?(index.flatMap { $0 >= 0 && $0 < items.count ? $0 : nil })
    }

    private var span: CGFloat { (360 - Self.gapDegrees) / CGFloat(max(items.count, 1)) }
    private var startDegrees: CGFloat { 90 + Self.gapDegrees / 2 }

    /// The slice at an angle in UIKit degrees (0 = right, 90 = down).
    func slice(atDegrees degrees: CGFloat) -> Int {
        var relative = (degrees - startDegrees).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        guard relative < 360 - Self.gapDegrees else { return Self.cancel }
        return min(items.count - 1, Int(relative / span))
    }

    /// Slide mode: point from where the finger went down to where it is.
    func track(from origin: CGPoint, to point: CGPoint) {
        let dx = point.x - origin.x, dy = point.y - origin.y
        let next: Int? = hypot(dx, dy) < Self.deadRadius ? nil : slice(atDegrees: atan2(dy, dx) * 180 / .pi)
        setHighlighted(next)
    }

    private func setHighlighted(_ next: Int?) {
        guard next != highlighted else { return }
        highlighted = next
        if next != nil { tick.selectionChanged() }
        refreshLooks()
    }

    private func item(at point: CGPoint) -> Int? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius + Self.pop else { return nil }
        return slice(atDegrees: atan2(dy, dx) * 180 / .pi)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        isOpen && tapMode ? self : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        setHighlighted(item(at: touch.location(in: self)))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        setHighlighted(item(at: touch.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // A slice picks it; the gap or anywhere else closes with no change.
        close(picking: item(at: touch.location(in: self)))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setHighlighted(nil)
    }

    private func rebuild() {
        sliceLayers.forEach { $0.removeFromSuperlayer() }
        sliceLabels.forEach { $0.removeFromSuperview() }
        sliceIcons.forEach { $0?.removeFromSuperview() }
        sliceIcons = items.map { item in
            guard let icon = item.icon else { return nil }
            let view = UIImageView(image: icon)
            view.contentMode = .scaleAspectFit
            addSubview(view)
            return view
        }
        sliceLayers = items.map { _ in
            let layer = CAShapeLayer()
            layer.lineWidth = 1.5
            self.layer.insertSublayer(layer, at: 0)
            return layer
        }
        sliceLabels = items.map { item in
            let label = UILabel()
            label.text = item.title
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: item.icon == nil ? 12 : 9)
            label.textColor = UIColor(white: 1, alpha: 0.9)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            addSubview(label)
            return label
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outerRadius = min(Self.outerMax, min(bounds.width, bounds.height) / 2 - 12)
        innerRadius = outerRadius * Self.innerFraction
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let labelRadius = (innerRadius + outerRadius) / 2
        for (index, label) in sliceLabels.enumerated() {
            let mid = (startDegrees + span * (CGFloat(index) + 0.5)) * .pi / 180
            label.bounds = CGRect(x: 0, y: 0, width: min(76, outerRadius - innerRadius), height: 18)
            let spot = CGPoint(x: center.x + cos(mid) * labelRadius, y: center.y + sin(mid) * labelRadius)
            if let icon = sliceIcons[index] {
                // Icon above its name, both centred on the slice.
                let width = min(44, (outerRadius - innerRadius) * 0.8)
                icon.bounds = CGRect(x: 0, y: 0, width: width, height: width / 2)
                icon.center = CGPoint(x: spot.x, y: spot.y - 6)
                label.center = CGPoint(x: spot.x, y: spot.y + width / 4 + 2)
            } else {
                label.center = spot
            }
        }
        centerTitle.frame = CGRect(x: center.x - innerRadius + 6, y: center.y - 14, width: (innerRadius - 6) * 2, height: 18)
        centerHint.frame = CGRect(x: center.x - innerRadius + 6, y: center.y + 4, width: (innerRadius - 6) * 2, height: 14)
        refreshLooks()
    }

    private func refreshLooks() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, layer) in sliceLayers.enumerated() {
            let a0 = (startDegrees + span * CGFloat(index)) * .pi / 180
            let a1 = a0 + span * .pi / 180
            let mid = (a0 + a1) / 2
            let pointed = highlighted == index
            let offset = pointed ? Self.pop : 0
            let c = CGPoint(x: center.x + cos(mid) * offset, y: center.y + sin(mid) * offset)
            let path = UIBezierPath(arcCenter: c, radius: outerRadius, startAngle: a0 + 0.012,
                                    endAngle: a1 - 0.012, clockwise: true)
            path.addArc(withCenter: c, radius: innerRadius, startAngle: a1 - 0.012,
                        endAngle: a0 + 0.012, clockwise: false)
            path.close()
            layer.path = path.cgPath
            layer.fillColor = UIColor(white: pointed ? 0.32 : 0, alpha: pointed ? 0.85 : 0.6).cgColor
            layer.strokeColor = UIColor(white: 1, alpha: pointed ? 0.9 : 0.4).cgColor
            let shift = CGAffineTransform(translationX: cos(mid) * offset, y: sin(mid) * offset)
            if index < sliceLabels.count { sliceLabels[index].transform = shift }
            if index < sliceIcons.count { sliceIcons[index]?.transform = shift }
        }
        refreshCenter()
    }

    private func refreshCenter() {
        if let highlighted, highlighted >= 0, highlighted < items.count {
            centerTitle.text = items[highlighted].title
            centerHint.text = tapMode ? "tap to select" : "lift to select"
        } else if highlighted == Self.cancel {
            centerTitle.text = title
            centerHint.text = "lift to cancel"
        } else {
            centerTitle.text = title
            centerHint.text = tapMode ? tapHint : slideHint
        }
    }
}

/// UT99's weapons for NEXT WPN's wheel, in the game's own weapon order
/// (InventoryGroup 1 to 10, then the Redeemer), with a drawn silhouette of
/// each: the app carries no game art. Picking one runs `getweapon <class>`.
enum UT99WeaponArt {
    struct Weapon {
        let id: String
        let title: String
        let className: String
    }

    static let weapons: [Weapon] = [
        Weapon(id: "translocator", title: "TRANSLOC", className: "Botpack.Translocator"),
        Weapon(id: "impact", title: "HAMMER", className: "Botpack.ImpactHammer"),
        Weapon(id: "chainsaw", title: "CHAINSAW", className: "Botpack.ChainSaw"),
        Weapon(id: "enforcer", title: "ENFORCER", className: "Botpack.Enforcer"),
        Weapon(id: "bio", title: "BIO", className: "Botpack.UT_BioRifle"),
        Weapon(id: "shock", title: "SHOCK", className: "Botpack.ShockRifle"),
        Weapon(id: "pulse", title: "PULSE", className: "Botpack.PulseGun"),
        Weapon(id: "ripper", title: "RIPPER", className: "Botpack.Ripper"),
        Weapon(id: "minigun", title: "MINIGUN", className: "Botpack.Minigun2"),
        Weapon(id: "flak", title: "FLAK", className: "Botpack.UT_FlakCannon"),
        Weapon(id: "rocket", title: "ROCKET", className: "Botpack.UT_Eightball"),
        Weapon(id: "sniper", title: "SNIPER", className: "Botpack.SniperRifle"),
        Weapon(id: "redeemer", title: "REDEEMER", className: "Botpack.WarheadLauncher"),
    ]

    private enum Shape {
        case box(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)   // x, y, w, h, corner
        case oval(CGFloat, CGFloat, CGFloat, CGFloat)
        case poly([CGPoint])
        case ring(CGFloat, CGFloat, CGFloat, CGFloat)          // a hollow oval
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// Each weapon on a 48 x 24 canvas, pointing right; the accent colour
    /// follows the weapon's ammo family.
    private static let art: [String: (UIColor, [Shape])] = [
        "translocator": (UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1),
                         [.box(4, 9, 22, 7, 2), .box(10, 14, 5, 8, 1), .ring(26, 4, 17, 16)]),
        "impact": (UIColor(red: 1, green: 0.82, blue: 0.35, alpha: 1),
                   [.box(2, 10, 13, 5, 1.5), .box(14, 5, 22, 15, 3), .box(36, 3, 5, 19, 1.5)]),
        "chainsaw": (UIColor(red: 1, green: 0.62, blue: 0.3, alpha: 1),
                     [.box(2, 9, 13, 8, 2), .box(14, 8, 32, 9, 4.5),
                      .poly([p(16, 8), p(19, 4), p(22, 8), p(25, 4), p(28, 8), p(31, 4), p(34, 8), p(37, 4), p(40, 8)])]),
        "enforcer": (UIColor(white: 0.9, alpha: 1),
                     [.box(10, 5, 28, 7, 1.5), .box(38, 6, 5, 5, 1),
                      .poly([p(13, 11), p(23, 11), p(19, 22), p(10, 22)])]),
        "bio": (UIColor(red: 0.45, green: 1, blue: 0.4, alpha: 1),
                [.poly([p(2, 8), p(14, 8), p(14, 16), p(4, 19)]), .oval(13, 3, 19, 18), .box(30, 9, 15, 6, 2)]),
        "shock": (UIColor(red: 0.75, green: 0.55, blue: 1, alpha: 1),
                  [.box(2, 9, 8, 7, 1.5), .box(8, 8, 31, 8, 2), .box(15, 4, 4, 16, 2), .box(21, 4, 4, 16, 2),
                   .box(27, 4, 4, 16, 2), .box(38, 9, 8, 6, 1.5)]),
        "pulse": (UIColor(red: 0.5, green: 1, blue: 0.75, alpha: 1),
                  [.box(5, 6, 27, 12, 4), .box(31, 5, 11, 3, 1), .box(31, 10.5, 14, 3, 1), .box(31, 16, 11, 3, 1),
                   .box(12, 16, 5, 7, 1)]),
        "ripper": (UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1),
                   [.box(3, 9, 25, 8, 2), .box(9, 15, 5, 7, 1), .ring(27, 3, 18, 18)]),
        "minigun": (UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1),
                    [.oval(2, 4, 16, 16), .box(16, 6, 28, 3, 1.2), .box(16, 10.5, 30, 3, 1.2),
                     .box(16, 15, 28, 3, 1.2), .box(31, 4, 3, 16, 1)]),
        "flak": (UIColor(red: 1, green: 0.55, blue: 0.35, alpha: 1),
                 [.box(3, 5, 27, 14, 3), .box(29, 6, 16, 12, 1.5), .box(10, 17, 6, 6, 1)]),
        "rocket": (UIColor(red: 1, green: 0.45, blue: 0.4, alpha: 1),
                   [.box(5, 4, 33, 16, 3.5), .box(37, 6, 8, 12, 1.5), .box(14, 4, 2, 16, 0), .box(24, 4, 2, 16, 0)]),
        "sniper": (UIColor(red: 0.6, green: 0.9, blue: 1, alpha: 1),
                   [.poly([p(1, 10), p(10, 9), p(10, 16), p(3, 18)]), .box(9, 9, 15, 6, 1.5), .box(22, 10.5, 25, 3, 1),
                    .box(12, 4, 15, 4, 2)]),
        "redeemer": (UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1),
                     [.box(3, 7, 32, 10, 5), .poly([p(34, 6), p(47, 12), p(34, 18)]),
                      .poly([p(4, 7), p(9, 2), p(12, 7)]), .poly([p(4, 17), p(9, 22), p(12, 17)])]),
    ]

    private static var cache: [String: UIImage] = [:]

    static func icon(for id: String) -> UIImage? {
        if let image = cache[id] { return image }
        guard let entry = art[id] else { return nil }
        let (accent, shapes) = entry
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 24), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(accent.cgColor)
            cg.setShadow(offset: .zero, blur: 2, color: accent.withAlphaComponent(0.6).cgColor)
            for shape in shapes {
                switch shape {
                case let .box(x, y, w, h, corner):
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: corner).fill()
                case let .oval(x, y, w, h):
                    UIBezierPath(ovalIn: CGRect(x: x, y: y, width: w, height: h)).fill()
                case let .poly(points):
                    let path = UIBezierPath()
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.close()
                    path.fill()
                case let .ring(x, y, w, h):
                    let path = UIBezierPath(ovalIn: CGRect(x: x, y: y, width: w, height: h))
                    path.append(UIBezierPath(ovalIn: CGRect(x: x + w * 0.3, y: y + h * 0.3, width: w * 0.4, height: h * 0.4)))
                    path.usesEvenOddFillRule = true
                    path.fill()
                }
            }
        }
        cache[id] = image
        return image
    }
}

/// UIKit adaptation of EctoPad's current SunPad controller layout.
///
/// The overlay owns touch tracking and publishes semantic actions. The engine
/// input adapter can consume these values without knowing where a control was
/// drawn. This keeps the host UI and the original engine boundary separate.
final class GoldenPadTouchOverlay: UIView, UIGestureRecognizerDelegate {
    enum TouchProfile: String {
        case standard
        /// Legacy import aliases. New preferences and exports use `standard`.
        case ectoPad
        case goldenPad
        case compact
        case highVisibility

        var canonical: TouchProfile {
            switch self {
            case .ectoPad, .goldenPad: .standard
            default: self
            }
        }

        var title: String {
            switch self {
            case .standard, .ectoPad: "Standard"
            case .goldenPad: "Legacy"
            case .compact: "Compact"
            case .highVisibility: "High visibility"
            }
        }

        var scale: CGFloat {
            switch self {
            case .standard, .ectoPad, .goldenPad: 1.0
            case .compact: 0.86
            case .highVisibility: 1.12
            }
        }

        var opacity: CGFloat {
            switch self {
            // EctoPad's source default is 0.82. Keeping the same composed
            // opacity prevents solid action faces from reading as opaque HUD
            // panels over a visually dense arena.
            case .standard, .ectoPad, .goldenPad: 0.82
            case .compact: 0.68
            case .highVisibility: 0.96
            }
        }
    }

    enum Action: String, CaseIterable {
        case primaryFire, leftPrimaryFire, alternateFire, jump, crouch, dodge, walk
        case use, nextWeapon, previousWeapon, scoreboard, customCommand, pause
        /// One-tap forward dodge. Last, so the button tags of the others
        /// (their index here) do not change.
        case dodgeForward
        /// Top row (house standard's small 22 pt buttons). Bunny Track's
        /// checkpoint pair says BTPlusPlus's "!cp" / "!nocp"; SUICIDE and
        /// TEAM fire after a 0.3 s hold with a ring; MAP VOTE opens the
        /// server's BDBMapVote window; TAUNT opens the taunt wheel.
        case checkpoint, noCheckpoint, suicide, mapVote, team, taunt
        /// CAMERA (tap: a photo; slide off sideways: a burst; hold: a
        /// selfie), VIEW (first / third person) and the CHEAT emblem (shown
        /// while the cheat is on; hold 0.5 s to switch it off or on).
        case camera, view, cheat
        /// One-tap left dodge, for profiles where ALT keeps alternate fire.
        case dodgeLeft
    }

    /// Top-row actions that fire once, on lift (taps) or after a hold.
    static let commandActions: Set<Action> = [.checkpoint, .noCheckpoint, .suicide, .mapVote, .team, .view, .cheat]
    /// Top-row actions that need a hold with a ring (0.3 s; the CHEAT emblem
    /// 0.5 s, as JK's), so a stray touch cannot kill the player, move them to
    /// the other team or change the cheat.
    static let holdActions: Set<Action> = [.suicide, .team, .cheat]

    var onAction: ((Action, Bool) -> Void)?
    /// Dodges publish one direction per gesture instead of press/release
    /// edges through `onAction`. `undoLook` is true for a look-side flick,
    /// whose first frames already turned the view before it was recognized.
    var onDodge: ((UT99DodgeDirection, _ undoLook: Bool) -> Void)?
    /// A look touch began; the host starts counting look it may need to undo.
    var onLookBegan: (() -> Void)?
    /// MENU was held: the host opens its options tray.
    var onMenuHold: (() -> Void)?
    var onMove: ((CGPoint, Bool) -> Void)?
    /// CAMERA: a photo (tap), a burst starting / stopping (slide off
    /// sideways, then lift), a selfie (hold still 0.5 s).
    var onCameraPhoto: (() -> Void)?
    var onCameraBurst: ((Bool) -> Void)?
    var onCameraSelfie: (() -> Void)?
    /// A taunt picked on the taunt wheel.
    var onTaunt: ((UT99TouchCommand) -> Void)?
    var onMenuCursorNudge: ((CGPoint) -> Void)?
    var onLook: ((CGPoint, Bool) -> Void)?

    private let movePad = UIView()
    private let moveRing = UIView()
    private let moveThumb = UIView()
    private let moveGlyph = UIImageView(image: UIImage(systemName: "figure.walk"))
    private let moveLabel = UILabel()
    private let lookPad = UIView()
    private let lookRing = UIView()
    private let lookThumb = UIView()
    private let lookGlyph = UIImageView(image: UIImage(systemName: "scope"))
    private let safeAreaGuide = UIView()
    private let weaponRail = UIView()
    private let weaponRailDivider = UIView()
    private var moveAnchor: CGPoint?
    private var lookAnchor: CGPoint?
    private var lookValue = CGPoint.zero
    private var lookDisplayLink: CADisplayLink?
    private var pointerLastLocation: CGPoint?
    private var accessibilityMovement = CGPoint.zero
    private var buttons: [Action: UT99TouchActionButton] = [:]
    private var activeActions = Set<Action>()
    private var menuInteractionActive = false
    private var placements: [String: UT99TouchPlacement] = [:]
    private let actionHaptic = UIImpactFeedbackGenerator(style: .light)
    private let dodgeHaptic = UIImpactFeedbackGenerator(style: .rigid)
    /// Where the current DODGE touch landed, in overlay coordinates. Nil when
    /// the pad is idle or this touch has already fired its one dodge.
    private var dodgeTouchOrigin: CGPoint?
    /// When the current look touch began, while it can still become a
    /// flick dodge. Nil once the flick window has passed or a dodge fired.
    private var lookFlickStart: CFTimeInterval?
    /// The current look touch already fired a flick dodge; it stops turning
    /// the view until the thumb lifts.
    private var lookSuppressed = false
    /// The MENU or CUSTOM press being timed, with its fill ring.
    private weak var holdButton: UT99TouchActionButton?
    private var holdAction: Action?
    private var holdStart: CFTimeInterval = 0
    private var holdFired = false
    private var holdLink: CADisplayLink?
    private let holdRing = CAShapeLayer()
    static let menuHoldSeconds: CFTimeInterval = 0.45
    /// UT99 player taunts (PlayerPawn's Taunt and Speech execs). VOICE plays
    /// one of the current voice pack's first four taunt lines at random.
    static let taunts: [(title: String, commands: [UT99TouchCommand])] = [
        ("WAVE", [.tauntWave]),
        ("VICTORY", [.tauntVictory]),
        ("TAUNT", [.tauntTaunt]),
        ("THRUST", [.tauntThrust]),
        ("VOICE", [.voice0, .voice1, .voice2, .voice3]),
    ]
    static let wheelOpenSlide: CGFloat = 10
    static let wheelHoldSeconds: CFTimeInterval = 0.3
    private let tauntWheel = UT99RadialWheelView()
    private let weaponWheel = UT99RadialWheelView()
    /// The wheel button being touched (TAUNT or NEXT WPN).
    private var wheelAction: Action?
    /// A weapon picked on NEXT WPN's wheel: its class, for getweapon.
    var onWeapon: ((String) -> Void)?
    static let cameraSelfieHold: CFTimeInterval = 0.5
    static let cameraBurstSlide: CGFloat = 20
    private enum CameraGesture { case idle, pending, burst, selfie }
    private var cameraGesture = CameraGesture.idle
    private var cameraOrigin = CGPoint.zero
    private var cameraDownTime: CFTimeInterval = 0
    private var cameraLink: CADisplayLink?
    private var wheelOrigin: CGPoint?
    private var wheelDownTime: CFTimeInterval = 0
    private var wheelLink: CADisplayLink?
    static let customHoldSeconds: CFTimeInterval = 0.3
    private(set) var editingLayout = false
    private(set) var testingLayout = false
    private let layoutBanner = UILabel()
    private let layoutDoneButton = UIButton(type: .system)
    private let layoutSizeControls = UIStackView()
    private let layoutSizeLabel = UILabel()
    private let layoutSizeSlider = UISlider()
    private var selectedLayoutKey = "move"
    private var moveDiameter: CGFloat = 172
    private var lookDiameter: CGFloat = 156
    private static let layoutDefaultsKey = "ut99.touch.layout.v1"
    /// Captured from the accepted physical iPhone 14 layout on 2026-08-25.
    /// These are device-class defaults only: an existing saved placement
    /// always wins, and the iPad reference layout remains unchanged.
    private static let phoneDefaultPlacements: [String: UT99TouchPlacement] = [
        "menuBack": .init(x: 0.8590047393364929, y: 0.3128205128205128, scale: 1),
        "menuSelect": .init(x: 0.7847551342812006, y: 0.5931623931623932, scale: 1),
        "move": .init(x: 0.15639810426540285, y: 0.7470085470085469, scale: 1),
        // JUMP and FIRE trade the accepted positions: JUMP takes the large
        // primary thumb spot. DUCK has no entry so it takes the reference
        // layout's lower-right corner.
        "jump": .init(x: 0.8175355450236966, y: 0.6376068376068377, scale: 1),
        "alternateFire": .init(x: 0.75, y: 0.5367521367521367, scale: 1),
        "primaryFire": .init(x: 0.8554502369668247, y: 0.4675213675213675, scale: 1.2872077226638794),
        // Up and right of FIRE, clear of the host's three-dot button above it.
        "dodge": .init(x: 0.905, y: 0.32, scale: 1),
        "previousWeapon": .init(x: 0.22946287519747235, y: 0.5863247863247864, scale: 1.1761363744735718),
        "nextWeapon": .init(x: 0.28080568720379145, y: 0.5923076923076923, scale: 1.226136326789856),
        "use": .init(x: 0.2531595576619273, y: 0.7059829059829059, scale: 1.3332443237304688),
    ]
    /// Captured from the accepted physical iPad Pro menu layout on
    /// 2026-08-26. Gameplay controls retain their reference geometry; only
    /// the independently editable SELECT and BACK menu controls are seeded.
    private static let tabletDefaultPlacements: [String: UT99TouchPlacement] = [
        "menuBack": .init(x: 0.9300878477306003, y: 0.53955078125, scale: 1),
        "menuSelect": .init(x: 0.8814055636896047, y: 0.63525390625, scale: 1),
    ]
    private(set) var touchProfile: TouchProfile

    private static let profileDefaultsKey = "ut99.touch.profile"
    private static let opacityDefaultsKey = "ut99.touch.opacity"
    private static let scaleDefaultsKey = "ut99.touch.scale"
    private(set) var touchOpacity: CGFloat
    private(set) var globalScale: CGFloat
    private(set) var touchConfiguration: UT99TouchConfiguration

    override init(frame: CGRect) {
        let savedProfile = TouchProfile(rawValue: UserDefaults.standard.string(forKey: Self.profileDefaultsKey) ?? "")
        touchProfile = (savedProfile ?? .standard).canonical
        let storedOpacity = UserDefaults.standard.object(forKey: Self.opacityDefaultsKey) as? Double
        touchOpacity = CGFloat(max(0.25, min(1.0, storedOpacity ?? Double(touchProfile.opacity))))
        let storedScale = UserDefaults.standard.object(forKey: Self.scaleDefaultsKey) as? Double
        globalScale = CGFloat(max(0.75, min(1.35, storedScale ?? 1.0)))
        touchConfiguration = UT99TouchConfiguration.load()
        super.init(frame: frame)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        loadPlacements()
        alpha = touchOpacity
        configureSurface()
        configureButtons()
        configureLayoutEditor()
        configureTauntWheel()
    }

    private func configureTauntWheel() {
        tauntWheel.items = Self.taunts.map { UT99RadialWheelView.Item(title: $0.title) }
        tauntWheel.title = "TAUNT"
        tauntWheel.tapHint = "tap a taunt"
        tauntWheel.slideHint = "slide toward a taunt"
        tauntWheel.onFinish = { [weak self] index in
            guard let self, let index, let command = Self.taunts[index].commands.randomElement() else { return }
            self.onTaunt?(command)
        }
        addSubview(tauntWheel)
        weaponWheel.items = UT99WeaponArt.weapons.map {
            UT99RadialWheelView.Item(title: $0.title, icon: UT99WeaponArt.icon(for: $0.id))
        }
        weaponWheel.title = "WEAPON"
        weaponWheel.tapHint = "tap a weapon"
        weaponWheel.slideHint = "slide toward a weapon"
        weaponWheel.onFinish = { [weak self] index in
            guard let self, let index else { return }
            self.onWeapon?(UT99WeaponArt.weapons[index].className)
        }
        addSubview(weaponWheel)
    }

    private func wheel(for action: Action) -> UT99RadialWheelView {
        action == .nextWeapon ? weaponWheel : tauntWheel
    }

    // MARK: CAMERA (JK's gestures, without Action Freeze)

    @objc private func cameraTouchBegan(_ sender: UIButton, forEvent event: UIEvent) {
        guard !editingLayout, !menuInteractionActive, cameraGesture == .idle,
              let touch = event.touches(for: sender)?.first,
              let button = sender as? UT99TouchActionButton else { return }
        cameraGesture = .pending
        cameraOrigin = touch.location(in: self)
        cameraDownTime = CACurrentMediaTime()
        updateAppearance(of: button, for: .camera, pressed: true)
        holdRing.removeFromSuperlayer()
        let ringRadius = min(button.bounds.width, button.bounds.height) / 2 - 2.5
        holdRing.path = UIBezierPath(arcCenter: CGPoint(x: button.bounds.midX, y: button.bounds.midY),
                                     radius: max(ringRadius, 1), startAngle: -.pi / 2,
                                     endAngle: 1.5 * .pi, clockwise: true).cgPath
        holdRing.fillColor = UIColor.clear.cgColor
        holdRing.strokeColor = UIColor(red: 0.47, green: 0.78, blue: 1, alpha: 0.95).cgColor
        holdRing.lineWidth = 3
        holdRing.strokeEnd = 0
        button.layer.addSublayer(holdRing)
        cameraLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(cameraHoldTick))
        link.add(to: .main, forMode: .common)
        cameraLink = link
    }

    @objc private func cameraHoldTick() {
        guard cameraGesture == .pending else { return }
        let progress = (CACurrentMediaTime() - cameraDownTime) / Self.cameraSelfieHold
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holdRing.strokeEnd = CGFloat(min(progress, 1))
        CATransaction.commit()
        guard progress >= 1 else { return }
        cameraGesture = .selfie
        stopCameraTimer()
        actionHaptic.impactOccurred(intensity: 0.9)
        onCameraSelfie?()
    }

    private func stopCameraTimer() {
        cameraLink?.invalidate()
        cameraLink = nil
        holdRing.removeFromSuperlayer()
    }

    @objc private func cameraTouchMoved(_ sender: UIButton, forEvent event: UIEvent) {
        guard cameraGesture == .pending, let touch = event.touches(for: sender)?.first else { return }
        let point = touch.location(in: self)
        guard abs(point.x - cameraOrigin.x) >= Self.cameraBurstSlide else { return }
        cameraGesture = .burst
        stopCameraTimer()
        onCameraBurst?(true)
    }

    @objc private func cameraTouchEnded(_ sender: UIButton) {
        if let button = sender as? UT99TouchActionButton { updateAppearance(of: button, for: .camera, pressed: false) }
        stopCameraTimer()
        switch cameraGesture {
        case .pending: onCameraPhoto?()
        case .burst: onCameraBurst?(false)
        case .selfie, .idle: break
        }
        cameraGesture = .idle
    }

    // MARK: Taunt wheel button (house wheel gestures)

    @objc private func wheelTouchBegan(_ sender: UIButton, forEvent event: UIEvent) {
        guard !editingLayout, !menuInteractionActive, !tauntWheel.isOpen, !weaponWheel.isOpen,
              let touch = event.touches(for: sender)?.first,
              let button = sender as? UT99TouchActionButton,
              let action = action(for: sender.tag) else { return }
        wheelAction = action
        wheelOrigin = touch.location(in: self)
        wheelDownTime = CACurrentMediaTime()
        updateAppearance(of: button, for: action, pressed: true)
        wheelLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(wheelHoldTick))
        link.add(to: .main, forMode: .common)
        wheelLink = link
    }

    @objc private func wheelHoldTick() {
        guard wheelOrigin != nil, let action = wheelAction, !wheel(for: action).isOpen,
              CACurrentMediaTime() - wheelDownTime >= Self.wheelHoldSeconds else { return }
        stopWheelTimer()
        wheel(for: action).open(tapMode: true)
    }

    private func stopWheelTimer() {
        wheelLink?.invalidate()
        wheelLink = nil
    }

    @objc private func wheelTouchMoved(_ sender: UIButton, forEvent event: UIEvent) {
        guard let origin = wheelOrigin, let action = wheelAction,
              let touch = event.touches(for: sender)?.first else { return }
        let point = touch.location(in: self)
        let target = wheel(for: action)
        if !target.isOpen, hypot(point.x - origin.x, point.y - origin.y) >= Self.wheelOpenSlide {
            stopWheelTimer()
            target.open(tapMode: false)
        }
        if target.isOpen && !target.tapMode { target.track(from: origin, to: point) }
    }

    @objc private func wheelTouchEnded(_ sender: UIButton, forEvent event: UIEvent) {
        stopWheelTimer()
        let action = wheelAction ?? .taunt
        if let button = sender as? UT99TouchActionButton { updateAppearance(of: button, for: action, pressed: false) }
        defer {
            wheelOrigin = nil
            wheelAction = nil
        }
        guard wheelOrigin != nil else { return }
        let target = wheel(for: action)
        if target.isOpen && !target.tapMode {
            target.close(picking: target.highlighted)
        } else if !target.isOpen {
            if action == .nextWeapon {
                // A quick tap on NEXT WPN is one next weapon (house standard).
                onAction?(.nextWeapon, true)
                onAction?(.nextWeapon, false)
            } else {
                // A quick tap on TAUNT opens its wheel to tap.
                target.open(tapMode: true)
            }
        }
    }

    @objc private func wheelTouchCancelled(_ sender: UIButton) {
        stopWheelTimer()
        let action = wheelAction ?? .taunt
        if let button = sender as? UT99TouchActionButton { updateAppearance(of: button, for: action, pressed: false) }
        wheelOrigin = nil
        wheelAction = nil
        let target = wheel(for: action)
        if target.isOpen && !target.tapMode { target.close(picking: nil) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Keep the full-screen overlay visually composited without swallowing
    /// touches between controls. Those touches fall through to the host's
    /// game-surface pointer view and drive Unreal's original UWindow UI.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        tauntWheel.frame = bounds
        weaponWheel.frame = bounds

        if traitCollection.userInterfaceIdiom != .pad || size.height < 500 {
            layoutPhoneControls(in: size)
            return
        }

        updateSafeAreaGuide()
        let safe = bounds.inset(by: safeAreaInsets)
        let scale = touchProfile.scale * globalScale
        applyReferenceFrames(UT99EctoPadReferenceLayout.tabletFrames(
            safeRect: safe,
            scale: scale,
            leftHanded: touchConfiguration.leftHanded
        ))
        layoutLookZone()
        weaponRail.isHidden = true
    }

    /// EctoPad's phone layout scales from an 800x380 safe reference rather
    /// than shrinking the iPad coordinates. Retain that exact construction so
    /// notches and the home indicator do not crush the action cluster.
    private func layoutPhoneControls(in size: CGSize) {
        updateSafeAreaGuide()
        let safe = bounds.inset(by: safeAreaInsets)
        applyReferenceFrames(UT99EctoPadReferenceLayout.phoneFrames(
            safeRect: safe,
            profileScale: touchProfile.scale * globalScale,
            leftHanded: touchConfiguration.leftHanded
        ))
        layoutLookZone()
        weaponRail.isHidden = true
    }

    private func layoutLookZone() {
        lookPad.frame = touchConfiguration.leftHanded
            ? CGRect(x: 0, y: 0, width: bounds.midX, height: bounds.height)
            : CGRect(x: bounds.midX, y: 0, width: bounds.width - bounds.midX, height: bounds.height)
        lookDiameter = min(172, max(112, bounds.height * 0.19)) * touchProfile.scale * globalScale
        lookRing.bounds = CGRect(x: 0, y: 0, width: lookDiameter, height: lookDiameter)
        lookRing.layer.cornerRadius = lookDiameter / 2
        if lookAnchor == nil {
            lookRing.center = CGPoint(x: lookPad.bounds.midX, y: lookPad.bounds.height * 0.70)
        }
        let thumbDiameter = lookDiameter * 0.42
        lookThumb.bounds = CGRect(x: 0, y: 0, width: thumbDiameter, height: thumbDiameter)
        lookThumb.center = CGPoint(x: lookRing.bounds.midX, y: lookRing.bounds.midY)
        lookThumb.layer.cornerRadius = thumbDiameter / 2
        let glyphSide = min(22, max(14, thumbDiameter * 0.34))
        lookGlyph.bounds = CGRect(x: 0, y: 0, width: glyphSide, height: glyphSide)
        lookGlyph.center = CGPoint(x: lookThumb.bounds.midX, y: lookThumb.bounds.midY)
        lookRing.isHidden = menuInteractionActive || (!testingLayout && lookAnchor == nil)
    }

    private func applyReferenceFrames(_ frames: [String: CGRect]) {
        if let frame = frames["move"] {
            placeStick(movePad, ring: moveRing, key: "move",
                       center: CGPoint(x: frame.midX, y: frame.midY), diameter: frame.width)
        }
        for action in Action.allCases {
            guard let frame = frames[action.rawValue] else { continue }
            setButton(action, center: CGPoint(x: frame.midX, y: frame.midY), size: frame.size)
        }
    }

    private func placeStick(_ view: UIView, ring: UIView, key: String, center fallback: CGPoint, diameter: CGFloat) {
        let placement = resolvedPlacement(for: key)
        let resolvedCenter = placement.map { CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) } ??
            UT99TouchLayoutGeometry.mirroredCenter(fallback, canvasWidth: bounds.width, leftHanded: false)
        let resolvedDiameter = diameter * (placement?.scale ?? 1)
        moveDiameter = resolvedDiameter
        // The movement surface is a forgiving half-screen activation zone.
        // Its visual stick is independent and appears wherever the thumb lands.
        view.frame = touchConfiguration.leftHanded
            ? CGRect(x: bounds.midX, y: 0, width: bounds.width - bounds.midX, height: bounds.height)
            : CGRect(x: 0, y: 0, width: bounds.midX, height: bounds.height)
        ring.bounds = CGRect(x: 0, y: 0, width: resolvedDiameter, height: resolvedDiameter)
        if moveAnchor == nil {
            ring.center = CGPoint(x: resolvedCenter.x - view.frame.minX, y: resolvedCenter.y - view.frame.minY)
        }
        ring.layer.cornerRadius = resolvedDiameter / 2
        let thumbDiameter = resolvedDiameter * 0.42
        moveThumb.bounds = CGRect(x: 0, y: 0, width: thumbDiameter, height: thumbDiameter)
        moveThumb.center = CGPoint(x: moveRing.bounds.midX, y: moveRing.bounds.midY)
        moveThumb.layer.cornerRadius = thumbDiameter / 2
        let glyphSide = min(22, max(14, thumbDiameter * 0.34))
        moveGlyph.bounds = CGRect(x: 0, y: 0, width: glyphSide, height: glyphSide)
        moveGlyph.center = CGPoint(x: moveThumb.bounds.midX, y: moveThumb.bounds.midY)
        if moveAnchor == nil {
            moveThumb.transform = stickThumbTransform(
                value: accessibilityMovement,
                surface: moveRing,
                thumb: moveThumb,
                invertY: true
            )
        }
        moveRing.isHidden = !editingLayout && !testingLayout && moveAnchor == nil
    }

    private func configureSurface() {
        safeAreaGuide.isHidden = true
        safeAreaGuide.isUserInteractionEnabled = false
        safeAreaGuide.backgroundColor = UIColor(red: 0.35, green: 0.92, blue: 0.88, alpha: 0.035)
        safeAreaGuide.layer.borderColor = UIColor(red: 0.35, green: 0.92, blue: 0.88, alpha: 0.70).cgColor
        safeAreaGuide.layer.borderWidth = 1
        safeAreaGuide.layer.cornerRadius = 14
        addSubview(safeAreaGuide)

        movePad.backgroundColor = .clear
        movePad.isOpaque = false
        movePad.isAccessibilityElement = true
        movePad.accessibilityLabel = "Movement"
        movePad.accessibilityValue = "Stopped"
        movePad.accessibilityHint = "Choose a direction from Actions. Choose Stop movement to release it."
        movePad.accessibilityIdentifier = "ut99.touch.move"
        movePad.accessibilityCustomActions = [
            movementAccessibilityAction(name: "Move forward", value: CGPoint(x: 0, y: 1)),
            movementAccessibilityAction(name: "Move backward", value: CGPoint(x: 0, y: -1)),
            movementAccessibilityAction(name: "Strafe left", value: CGPoint(x: -1, y: 0)),
            movementAccessibilityAction(name: "Strafe right", value: CGPoint(x: 1, y: 0)),
            menuCursorNudgeAccessibilityAction(name: "Nudge up", offset: CGPoint(x: 0, y: -24)),
            menuCursorNudgeAccessibilityAction(name: "Nudge down", offset: CGPoint(x: 0, y: 24)),
            menuCursorNudgeAccessibilityAction(name: "Nudge left", offset: CGPoint(x: -24, y: 0)),
            menuCursorNudgeAccessibilityAction(name: "Nudge right", offset: CGPoint(x: 24, y: 0)),
            movementAccessibilityAction(name: "Stop movement", value: .zero)
        ]
        addSubview(movePad)

        // The ring is a floating stick: invisible at rest, centered under the
        // player's thumb on contact, and removed immediately on release.
        moveRing.backgroundColor = UIColor(white: 0.13, alpha: 0.86)
        moveRing.layer.cornerRadius = 100
        moveRing.layer.borderWidth = 2
        moveRing.layer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor
        moveRing.isUserInteractionEnabled = false
        moveThumb.backgroundColor = UIColor(white: 0.58, alpha: 0.94)
        moveThumb.layer.cornerRadius = 100
        moveRing.addSubview(moveThumb)
        moveGlyph.tintColor = UIColor.white.withAlphaComponent(0.80)
        moveGlyph.contentMode = .scaleAspectFit
        moveThumb.addSubview(moveGlyph)
        moveRing.isHidden = true
        movePad.addSubview(moveRing)
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(moveChanged(_:)))
        movePan.delegate = self
        movePad.addGestureRecognizer(movePan)
        let movePinch = UIPinchGestureRecognizer(target: self, action: #selector(layoutZonePinchChanged(_:)))
        movePinch.cancelsTouchesInView = false
        movePad.addGestureRecognizer(movePinch)

        lookPad.backgroundColor = .clear
        lookPad.isOpaque = false
        lookPad.isMultipleTouchEnabled = true
        lookPad.accessibilityIdentifier = "ut99.touch.lookStick"
        lookPad.accessibilityLabel = "Look"
        lookPad.accessibilityHint = "Touch anywhere on this side and move the floating stick to look around."
        addSubview(lookPad)
        lookRing.backgroundColor = UIColor(red: 0.08, green: 0.23, blue: 0.30, alpha: 0.84)
        lookRing.layer.borderWidth = 2
        lookRing.layer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor
        lookRing.isUserInteractionEnabled = false
        lookThumb.backgroundColor = UIColor(red: 0.28, green: 0.72, blue: 0.78, alpha: 0.94)
        lookRing.addSubview(lookThumb)
        lookGlyph.tintColor = UIColor.white.withAlphaComponent(0.86)
        lookGlyph.contentMode = .scaleAspectFit
        lookThumb.addSubview(lookGlyph)
        lookRing.isHidden = true
        lookPad.addSubview(lookRing)
        let lookPan = UIPanGestureRecognizer(target: self, action: #selector(lookChanged(_:)))
        lookPan.delegate = self
        lookPad.addGestureRecognizer(lookPan)

        weaponRail.isUserInteractionEnabled = false
        weaponRail.isOpaque = false
        weaponRail.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        weaponRail.layer.borderWidth = 0.8
        weaponRail.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
        weaponRail.layer.cornerCurve = .continuous
        weaponRail.clipsToBounds = true
        weaponRailDivider.isUserInteractionEnabled = false
        weaponRailDivider.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        weaponRail.addSubview(weaponRailDivider)
        addSubview(weaponRail)

        // SDL's renderer window is intentionally non-interactive so the host
        // owns touch/menu input. Keep iPad trackpad/mouse aiming on the same
        // host path by converting hover deltas into relative-look events;
        // touch pan gestures remain independent.
        let pointer = UIHoverGestureRecognizer(target: self, action: #selector(pointerChanged(_:)))
        pointer.cancelsTouchesInView = false
        addGestureRecognizer(pointer)
    }

    private func movementAccessibilityAction(name: String, value: CGPoint) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: name) { [weak self] _ in
            guard let self, !self.editingLayout else { return false }
            self.accessibilityMovement = value
            self.moveRing.isHidden = value == .zero
            self.moveThumb.transform = self.stickThumbTransform(
                value: value,
                surface: self.moveRing,
                thumb: self.moveThumb,
                invertY: true
            )
            self.movePad.accessibilityValue = value == .zero ? "Stopped" : name
            self.onMove?(value, value != .zero)
            return true
        }
    }

    private func menuCursorNudgeAccessibilityAction(
        name: String,
        offset: CGPoint
    ) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: name) { [weak self] _ in
            guard let self, !self.editingLayout, self.menuInteractionActive else { return false }
            self.onMenuCursorNudge?(offset)
            self.movePad.accessibilityValue = name
            return true
        }
    }

    private func stickThumbTransform(value: CGPoint, surface: UIView, thumb: UIView, invertY: Bool) -> CGAffineTransform {
        let travel = max(0, surface.bounds.width * 0.5 - thumb.bounds.width * 0.5 - 4)
        return CGAffineTransform(
            translationX: value.x * travel,
            y: (invertY ? -value.y : value.y) * travel
        )
    }

    private func configureButtons() {
        for action in Action.allCases {
            let button = UT99TouchActionButton(frame: .zero)
            button.configure(
                symbol: symbol(for: action),
                title: title(for: action),
                accent: tint(for: action),
                foreground: foreground(for: action),
                role: visualRole(for: action)
            )
            updateAppearance(of: button, for: action, pressed: false)
            button.layer.cornerRadius = 44
            button.layer.cornerCurve = .continuous
            button.isHidden = false // the host's three-dot button remains a separate host surface
            button.accessibilityLabel = title(for: action)
            button.accessibilityHint = accessibilityHint(for: action)
            button.accessibilityIdentifier = "ut99.touch.\(action.rawValue)"
            if action == .dodge {
                // The swipe keeps tracking after the thumb leaves the pad, so
                // DODGE must not release on touchDragExit like a held button.
                button.addTarget(self, action: #selector(dodgeTouchBegan(_:forEvent:)), for: .touchDown)
                button.addTarget(self, action: #selector(dodgeTouchMoved(_:forEvent:)),
                                 for: [.touchDragInside, .touchDragOutside])
                button.addTarget(self, action: #selector(dodgeTouchEnded(_:)),
                                 for: [.touchUpInside, .touchUpOutside, .touchCancel])
                button.accessibilityCustomActions = UT99DodgeDirection.allCases.map { direction in
                    UIAccessibilityCustomAction(name: "Dodge \(direction.rawValue)") { [weak self] _ in
                        guard let self, !self.editingLayout, !self.menuInteractionActive else { return false }
                        self.onDodge?(direction, false)
                        return true
                    }
                }
            } else if action == .camera {
                button.addTarget(self, action: #selector(cameraTouchBegan(_:forEvent:)), for: .touchDown)
                button.addTarget(self, action: #selector(cameraTouchMoved(_:forEvent:)),
                                 for: [.touchDragInside, .touchDragOutside])
                button.addTarget(self, action: #selector(cameraTouchEnded(_:)),
                                 for: [.touchUpInside, .touchUpOutside, .touchCancel])
            } else if action == .taunt || action == .nextWeapon {
                // TAUNT: slide 10 pt to open the wheel at once and lift on a
                // taunt; a tap or a 0.3 s hold opens it to tap (house wheel).
                button.addTarget(self, action: #selector(wheelTouchBegan(_:forEvent:)), for: .touchDown)
                button.addTarget(self, action: #selector(wheelTouchMoved(_:forEvent:)),
                                 for: [.touchDragInside, .touchDragOutside])
                button.addTarget(self, action: #selector(wheelTouchEnded(_:forEvent:)),
                                 for: [.touchUpInside, .touchUpOutside])
                button.addTarget(self, action: #selector(wheelTouchCancelled(_:)), for: [.touchCancel])
            } else if Self.commandActions.contains(action) {
                // Fire once: on lift for a tap, or when a hold's ring fills.
                button.addTarget(self, action: #selector(holdTouchBegan(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(holdTouchEnded(_:)), for: [.touchUpInside])
                button.addTarget(self, action: #selector(holdTouchCancelled(_:)),
                                 for: [.touchUpOutside, .touchCancel, .touchDragExit])
            } else if action == .pause || action == .customCommand {
                // MENU: tap for UT's menu, hold for the options tray.
                // CUSTOM: hold to confirm (optional). Sliding off cancels.
                button.addTarget(self, action: #selector(holdTouchBegan(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(holdTouchEnded(_:)), for: [.touchUpInside])
                button.addTarget(self, action: #selector(holdTouchCancelled(_:)),
                                 for: [.touchUpOutside, .touchCancel, .touchDragExit])
                if action == .pause {
                    button.accessibilityCustomActions = [
                        UIAccessibilityCustomAction(name: "Options") { [weak self] _ in
                            guard let self, !self.editingLayout else { return false }
                            self.onMenuHold?()
                            return true
                        }
                    ]
                }
            } else {
                button.addTarget(self, action: #selector(buttonDown(_:)), for: [.touchDown, .touchDragEnter])
                button.addTarget(self, action: #selector(buttonUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            }
            button.tag = actionTag(action)
            if action != .dodge {
                button.onAccessibilityActivate = { [weak self, weak button] in
                    guard let self, let button, !self.activeActions.contains(action) else { return }
                    // The original SDL entry owns the main thread once gameplay
                    // starts, so a main-queue delayed release cannot be trusted.
                    // Queue both edges synchronously; SDL preserves their order.
                    self.buttonDown(button)
                    self.buttonUp(button)
                }
            }
            let layoutPan = UIPanGestureRecognizer(target: self, action: #selector(layoutPanChanged(_:)))
            layoutPan.cancelsTouchesInView = false
            button.addGestureRecognizer(layoutPan)
            let layoutPinch = UIPinchGestureRecognizer(target: self, action: #selector(layoutPinchChanged(_:)))
            layoutPinch.cancelsTouchesInView = false
            button.addGestureRecognizer(layoutPinch)
            let layoutSelect = UITapGestureRecognizer(target: self, action: #selector(layoutControlSelected(_:)))
            layoutSelect.cancelsTouchesInView = false
            button.addGestureRecognizer(layoutSelect)
            buttons[action] = button
            addSubview(button)
        }
    }

    private func configureLayoutEditor() {
        layoutBanner.text = "EDIT TOUCH LAYOUT"
        layoutBanner.textColor = .white.withAlphaComponent(0.88)
        layoutBanner.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        layoutBanner.textAlignment = .center
        layoutBanner.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layoutBanner.layer.cornerRadius = 8
        layoutBanner.clipsToBounds = true
        layoutBanner.isHidden = true
        layoutBanner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutBanner)

        layoutDoneButton.setTitle("DONE", for: .normal)
        layoutDoneButton.setTitleColor(.white, for: .normal)
        layoutDoneButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        layoutDoneButton.backgroundColor = UIColor(red: 0.10, green: 0.52, blue: 0.48, alpha: 0.92)
        layoutDoneButton.layer.cornerRadius = 8
        layoutDoneButton.isHidden = true
        layoutDoneButton.translatesAutoresizingMaskIntoConstraints = false
        layoutDoneButton.addTarget(self, action: #selector(finishLayoutEditing), for: .touchUpInside)
        addSubview(layoutDoneButton)

        layoutSizeLabel.textColor = .white
        layoutSizeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        layoutSizeLabel.text = "SIZE · MOVE"
        layoutSizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        layoutSizeSlider.minimumValue = 0.70
        layoutSizeSlider.maximumValue = 1.50
        layoutSizeSlider.value = 1
        layoutSizeSlider.minimumTrackTintColor = UIColor(red: 0.35, green: 0.92, blue: 0.88, alpha: 1)
        layoutSizeSlider.accessibilityLabel = "Selected control size"
        layoutSizeSlider.addTarget(self, action: #selector(layoutSizeChanged(_:)), for: .valueChanged)
        layoutSizeSlider.addTarget(self, action: #selector(layoutSizeFinished(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        layoutSizeControls.addArrangedSubview(layoutSizeLabel)
        layoutSizeControls.addArrangedSubview(layoutSizeSlider)
        layoutSizeControls.axis = .horizontal
        layoutSizeControls.alignment = .center
        layoutSizeControls.spacing = 12
        layoutSizeControls.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        layoutSizeControls.layer.cornerRadius = 10
        layoutSizeControls.isLayoutMarginsRelativeArrangement = true
        layoutSizeControls.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        layoutSizeControls.isHidden = true
        layoutSizeControls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutSizeControls)

        let moveSelect = UITapGestureRecognizer(target: self, action: #selector(layoutMoveSelected(_:)))
        moveSelect.cancelsTouchesInView = false
        movePad.addGestureRecognizer(moveSelect)
        NSLayoutConstraint.activate([
            // Center the two editor controls as one compact strip. Side-based
            // placement collides with MENU when the southpaw preset mirrors it;
            // SCORE moves just below this strip while a layout mode is active.
            layoutBanner.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor, constant: -128),
            layoutBanner.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            layoutBanner.widthAnchor.constraint(equalToConstant: 170),
            layoutBanner.heightAnchor.constraint(equalToConstant: 32),
            layoutDoneButton.leadingAnchor.constraint(equalTo: layoutBanner.trailingAnchor, constant: 10),
            layoutDoneButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            layoutDoneButton.widthAnchor.constraint(equalToConstant: 76),
            layoutDoneButton.heightAnchor.constraint(equalToConstant: 32),
            layoutSizeControls.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            layoutSizeControls.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            layoutSizeControls.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -32),
            layoutSizeControls.widthAnchor.constraint(equalToConstant: 360),
            layoutSizeControls.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func setButton(_ action: Action, center: CGPoint, size: CGSize, scale: CGFloat = 1) {
        guard let button = buttons[action] else { return }
        // In UT's menus only MENU (BACK) stays; menus are tapped directly.
        button.isHidden = menuInteractionActive
            ? action != .pause
            : touchConfiguration.hiddenActions.contains(action.rawValue)
        if menuInteractionActive && action == .pause {
            let safe = bounds.inset(by: safeAreaInsets).insetBy(dx: 18, dy: 18)
            let menuSize = action == .primaryFire
                ? CGSize(width: 104, height: 104)
                : CGSize(width: 132, height: 64)
            let fallbackCenter = action == .primaryFire
                ? CGPoint(x: safe.maxX - menuSize.width * 0.5, y: safe.midY)
                : CGPoint(
                    x: safe.maxX - menuSize.width * 0.5,
                    // The host menu starts 40 points below the safe-area top
                    // and is 40 points tall. Keep BACK below its full target.
                    y: max(safe.minY, safeAreaInsets.top + 40 + 40 + 12) + menuSize.height * 0.5
                )
            let placement = resolvedPlacement(for: layoutKey(for: action)) ?? UT99TouchPlacement(
                x: fallbackCenter.x / max(bounds.width, 1),
                y: fallbackCenter.y / max(bounds.height, 1),
                scale: 1
            )
            button.bounds.size = CGSize(
                width: menuSize.width * placement.scale,
                height: menuSize.height * placement.scale
            )
            button.center = CGPoint(x: placement.x * bounds.width, y: placement.y * bounds.height)
            button.center.x = min(max(button.center.x, safe.minX + button.bounds.width * 0.5),
                                  safe.maxX - button.bounds.width * 0.5)
            button.center.y = min(max(button.center.y, safe.minY + button.bounds.height * 0.5),
                                  safe.maxY - button.bounds.height * 0.5)
            keepButtonBelowHostMenu(button)
            button.layer.cornerRadius = min(button.bounds.width, button.bounds.height) / 2
            updateAppearance(of: button, for: action, pressed: activeActions.contains(action))
            return
        }
        let fallback = UT99TouchPlacement(x: center.x / max(bounds.width, 1), y: center.y / max(bounds.height, 1), scale: 1)
        let placement = resolvedPlacement(for: action.rawValue) ?? fallback
        button.bounds.size = CGSize(width: size.width * scale * placement.scale,
                                    height: size.height * scale * placement.scale)
        button.center = CGPoint(x: placement.x * bounds.width, y: placement.y * bounds.height)
        if action == .pause { keepButtonBelowHostMenu(button) }
        button.layer.cornerRadius = min(button.bounds.width, button.bounds.height) / 2
        updateAppearance(of: button, for: action, pressed: activeActions.contains(action))
    }

    private func layoutKey(for action: Action) -> String {
        guard menuInteractionActive else { return action.rawValue }
        if action == .primaryFire { return "menuSelect" }
        if action == .pause { return "menuBack" }
        return action.rawValue
    }

    private func action(forLayoutKey key: String) -> Action? {
        if key == "menuSelect" { return .primaryFire }
        if key == "menuBack" { return .pause }
        return Action(rawValue: key)
    }

    private func keepButtonBelowHostMenu(_ button: UIButton) {
        let safe = bounds.inset(by: safeAreaInsets)
        let hostButton = CGRect(
            x: safe.maxX - 52,
            y: safe.minY + 40,
            width: 40,
            height: 40
        ).insetBy(dx: -8, dy: -8)
        guard button.frame.intersects(hostButton) else { return }
        button.center.y = min(
            safe.maxY - button.bounds.height * 0.5 - 8,
            hostButton.maxY + 8 + button.bounds.height * 0.5
        )
    }

    private func layoutWeaponRail() {
        guard let previous = buttons[.previousWeapon], let next = buttons[.nextWeapon] else {
            weaponRail.isHidden = true
            return
        }
        guard !previous.isHidden, !next.isHidden else {
            weaponRail.isHidden = true
            return
        }
        let hasCustomPlacement = placements[Action.previousWeapon.rawValue] != nil ||
            placements[Action.nextWeapon.rawValue] != nil
        weaponRail.isHidden = editingLayout || hasCustomPlacement
        guard !weaponRail.isHidden else { return }
        let union = previous.frame.union(next.frame)
        weaponRail.frame = union.insetBy(dx: -7, dy: -3)
        weaponRail.layer.cornerRadius = weaponRail.bounds.height / 2
        weaponRailDivider.frame = CGRect(
            x: weaponRail.bounds.midX - 0.5,
            y: weaponRail.bounds.height * 0.24,
            width: 1,
            height: weaponRail.bounds.height * 0.52
        )
        sendSubviewToBack(weaponRail)
    }

    private func center(forKey key: String, in size: CGSize, fallback: CGPoint) -> CGPoint {
        if let placement = resolvedPlacement(for: key) {
            return CGPoint(x: placement.x * size.width, y: placement.y * size.height)
        }
        return UT99TouchLayoutGeometry.mirroredCenter(
            fallback,
            canvasWidth: size.width,
            leftHanded: touchConfiguration.leftHanded
        )
    }

    private func resolvedPlacement(for key: String) -> UT99TouchPlacement? {
        if let placement = placements[key] { return placement }
        let defaults = traitCollection.userInterfaceIdiom == .phone
            ? Self.phoneDefaultPlacements
            : Self.tabletDefaultPlacements
        guard var placement = defaults[key] else { return nil }
        if touchConfiguration.leftHanded { placement.x = 1 - placement.x }
        return placement
    }

    private func loadPlacements() {
        guard let data = UserDefaults.standard.data(forKey: Self.layoutDefaultsKey),
              let saved = try? JSONDecoder().decode([String: UT99TouchPlacement].self, from: data) else { return }
        placements = saved
    }

    private func savePlacements() {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        UserDefaults.standard.set(data, forKey: Self.layoutDefaultsKey)
        NSLog("UT99 touch layout persisted entries=%lu", placements.count)
    }

    func makeTouchProfile(named name: String) throws -> UT99TouchProfileDocument {
        let defaults = UserDefaults.standard
        return try UT99TouchProfileStore.validated(UT99TouchProfileDocument(
            name: name,
            preset: touchProfile.rawValue,
            opacity: touchOpacity,
            globalScale: globalScale,
            configuration: touchConfiguration,
            lookSensitivity: defaults.double(forKey: "ut99.input.lookSensitivity"),
            invertLookY: defaults.bool(forKey: "ut99.input.invertLookY"),
            placements: placements
        ))
    }

    func applyTouchProfileDocument(_ source: UT99TouchProfileDocument) throws {
        let profile = try UT99TouchProfileStore.validated(source)
        guard let preset = TouchProfile(rawValue: profile.preset) else {
            throw UT99TouchProfileError.unsupportedPreset(profile.preset)
        }
        releaseActiveInputs()
        editingLayout = false
        testingLayout = false
        touchProfile = preset
        touchOpacity = profile.opacity
        globalScale = profile.globalScale
        touchConfiguration = profile.configuration.sanitized()
        placements = profile.placements

        let defaults = UserDefaults.standard
        defaults.set(touchProfile.rawValue, forKey: Self.profileDefaultsKey)
        defaults.set(Double(touchOpacity), forKey: Self.opacityDefaultsKey)
        defaults.set(Double(globalScale), forKey: Self.scaleDefaultsKey)
        defaults.set(profile.lookSensitivity, forKey: "ut99.input.lookSensitivity")
        defaults.set(profile.invertLookY, forKey: "ut99.input.invertLookY")
        touchConfiguration.save(to: defaults)
        savePlacements()
        refreshActionTitles()
        alpha = touchOpacity
        updateLayoutModeAppearance()
        NSLog("UT99 touch named profile applied name=%@ preset=%@ placements=%lu",
              profile.name, profile.preset, placements.count)
    }

    func resetTouchLayout() {
        releaseActiveInputs()
        placements.removeAll()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.layoutDefaultsKey)
        touchProfile = .standard
        touchOpacity = TouchProfile.standard.opacity
        globalScale = 1.0
        defaults.set(touchProfile.rawValue, forKey: Self.profileDefaultsKey)
        defaults.set(Double(touchOpacity), forKey: Self.opacityDefaultsKey)
        defaults.set(Double(globalScale), forKey: Self.scaleDefaultsKey)
        touchConfiguration = .standard
        touchConfiguration.save(to: defaults)
        refreshActionTitles()
        alpha = touchOpacity
        setNeedsLayout()
    }

    /// One-tap Bunny Track setup: the jump-first default positions, combat
    /// clutter hidden, a slower look curve, and look-side flick dodging.
    /// WALK takes the duplicate FIRE position the preset hides.
    func applyBunnyTrackLayout() {
        releaseActiveInputs()
        placements.removeAll()
        touchConfiguration = touchConfiguration.applyingBunnyTrackPreset()
        touchConfiguration.save()
        refreshActionTitles()
        setNeedsLayout()
        layoutIfNeeded()
        _ = placeBunnyTrackButtons()
        savePlacements()
        setNeedsLayout()
        NSLog("UT99 touch Bunny Track layout applied hidden=%lu", touchConfiguration.hiddenActions.count)
    }

    /// The DM (Standard) layout: the house right-thumb cluster (a big FIRE in
    /// the corner, ALT to its left, JUMP up-left, DUCK above it, ◀ ▲ ▶ DODGE
    /// around JUMP's top) and NEXT WPN
    /// first on the top row, where its weapon wheel opens.
    func applyDeathmatchLayout() {
        releaseActiveInputs()
        placements.removeAll()
        touchConfiguration = touchConfiguration.applyingDeathmatchPreset()
        touchConfiguration.save()
        refreshActionTitles()
        setNeedsLayout()
        layoutIfNeeded()
        _ = placeDeathmatchButtons()
        savePlacements()
        setNeedsLayout()
        NSLog("UT99 touch DM layout applied")
    }

    @discardableResult
    func placeDeathmatchButtons() -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let safe = bounds.inset(by: safeAreaInsets)
        let frames = referenceFrames()
        let k = min(1.3, max(0.8, safe.height / 400)) * touchProfile.scale * globalScale
        let leftHanded = touchConfiguration.leftHanded
        func place(_ action: Action, fromRight: CGFloat, up: CGFloat, diameter: CGFloat) {
            guard let base = frames[action.rawValue]?.width, base > 0 else { return }
            let x = leftHanded ? safe.minX + fromRight * k : safe.maxX - fromRight * k
            placements[action.rawValue] = UT99TouchPlacement(
                x: x / bounds.width, y: (safe.maxY - up * k) / bounds.height,
                scale: diameter * k / base)
        }
        place(.primaryFire, fromRight: 70, up: 72, diameter: 84)
        place(.alternateFire, fromRight: 176, up: 52, diameter: 56)
        place(.jump, fromRight: 160, up: 140, diameter: 62)
        place(.crouch, fromRight: 38, up: 165, diameter: 54)
        // ◀ and DODGE ▶ level either side of JUMP's top, ▲ DODGE just above it.
        place(.dodgeLeft, fromRight: 222, up: 198, diameter: 52)
        place(.dodge, fromRight: 100, up: 198, diameter: 52)
        place(.dodgeForward, fromRight: 160, up: 222, diameter: 52)
        // NEXT WPN in CUSTOM's top-left slot (CUSTOM is hidden here).
        if let slot = frames[Action.customCommand.rawValue], let base = frames[Action.nextWeapon.rawValue]?.width,
           base > 0 {
            placements[Action.nextWeapon.rawValue] = UT99TouchPlacement(
                x: slot.midX / bounds.width, y: slot.midY / bounds.height, scale: slot.width / base)
        }
        savePlacements()
        setNeedsLayout()
        return true
    }

    /// The frames the current device class lays out from (before placements).
    private func referenceFrames() -> [String: CGRect] {
        let safe = bounds.inset(by: safeAreaInsets)
        if traitCollection.userInterfaceIdiom != .pad || bounds.height < 500 {
            return UT99EctoPadReferenceLayout.phoneFrames(
                safeRect: safe, profileScale: touchProfile.scale * globalScale,
                leftHanded: touchConfiguration.leftHanded)
        }
        return UT99EctoPadReferenceLayout.tabletFrames(
            safeRect: safe, scale: touchProfile.scale * globalScale,
            leftHanded: touchConfiguration.leftHanded)
    }

    /// Bunny Track's right-thumb cluster, all in the lower right: a big
    /// JUMP, DUCK in the corner, FIRE and WALK to JUMP's left, and ◀ ▲ ▶
    /// DODGE above JUMP like arrow keys. Points are measured from the safe
    /// area's lower-right corner on a 400 pt tall reference and scale with
    /// the screen. Returns false (placing nothing) before the overlay has a
    /// size.
    @discardableResult
    func placeBunnyTrackButtons() -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let safe = bounds.inset(by: safeAreaInsets)
        let frames = referenceFrames()
        let k = min(1.3, max(0.8, safe.height / 400)) * touchProfile.scale * globalScale
        let leftHanded = touchConfiguration.leftHanded
        func place(_ action: Action, fromRight: CGFloat, up: CGFloat, diameter: CGFloat) {
            guard let base = frames[action.rawValue]?.width, base > 0 else { return }
            let x = leftHanded ? safe.minX + fromRight * k : safe.maxX - fromRight * k
            placements[action.rawValue] = UT99TouchPlacement(
                x: x / bounds.width, y: (safe.maxY - up * k) / bounds.height,
                scale: diameter * k / base)
        }
        place(.jump, fromRight: 110, up: 112, diameter: 84)
        place(.crouch, fromRight: 38, up: 40, diameter: 58)
        place(.primaryFire, fromRight: 214, up: 72, diameter: 62)
        place(.walk, fromRight: 226, up: 160, diameter: 50)
        place(.alternateFire, fromRight: 170, up: 205, diameter: 58)
        place(.dodge, fromRight: 50, up: 205, diameter: 58)
        place(.dodgeForward, fromRight: 110, up: 262, diameter: 58)
        savePlacements()
        setNeedsLayout()
        return true
    }

    func setLeftHanded(_ enabled: Bool) {
        guard touchConfiguration.leftHanded != enabled else { return }
        releaseActiveInputs()
        touchConfiguration.leftHanded = enabled
        touchConfiguration.save()
        // Handedness is a complete spatial preset. Clear custom coordinates so
        // it always produces a coherent mirror instead of a half-custom mix.
        placements.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.layoutDefaultsKey)
        setNeedsLayout()
    }

    func isActionVisible(_ action: Action) -> Bool {
        !touchConfiguration.hiddenActions.contains(action.rawValue)
    }

    func setAction(_ action: Action, visible: Bool) {
        if visible {
            touchConfiguration.hiddenActions.remove(action.rawValue)
        } else {
            if activeActions.remove(action) != nil { onAction?(action, false) }
            touchConfiguration.hiddenActions.insert(action.rawValue)
        }
        touchConfiguration.save()
        setNeedsLayout()
    }

    func setTouchConfiguration(_ source: UT99TouchConfiguration) {
        releaseActiveInputs()
        touchConfiguration = source.sanitized()
        touchConfiguration.save()
        refreshActionTitles()
        setNeedsLayout()
    }

    func displayTitle(for action: Action) -> String { title(for: action) }

    /// Where a visible button is, in overlay coordinates (nil when hidden).
    func buttonFrame(_ action: Action) -> CGRect? {
        guard let button = buttons[action], !button.isHidden else { return nil }
        return button.frame
    }

    func setTouchOpacity(_ value: CGFloat) {
        // The house OPACITY range: 20% to 100% (untouched buttons are 65% of it).
        touchOpacity = max(0.2, min(1.0, value))
        UserDefaults.standard.set(Double(touchOpacity), forKey: Self.opacityDefaultsKey)
        alpha = touchOpacity
    }

    func setGlobalScale(_ value: CGFloat) {
        globalScale = max(0.75, min(1.35, value))
        UserDefaults.standard.set(Double(globalScale), forKey: Self.scaleDefaultsKey)
        setNeedsLayout()
    }

    func setLayoutEditing(_ editing: Bool) {
        releaseActiveInputs()
        editingLayout = editing
        testingLayout = false
        updateLayoutModeAppearance()
    }

    func setLayoutTesting(_ testing: Bool) {
        releaseActiveInputs()
        editingLayout = false
        testingLayout = testing
        updateLayoutModeAppearance()
    }

    func setMenuInteractionActive(_ active: Bool) {
        guard menuInteractionActive != active else { return }
        releaseActiveInputs()
        menuInteractionActive = active
        // Menus are tapped directly, so neither stick may claim the touch.
        movePad.isHidden = active
        lookPad.isHidden = active
        movePad.accessibilityLabel = active ? "Menu cursor" : "Movement"
        movePad.accessibilityHint = active
            ? "Move the Unreal Tournament menu cursor."
            : "Choose a direction from Actions. Choose Stop movement to release it."
        for (action, button) in buttons {
            button.isHidden = active
                ? action != .pause
                : touchConfiguration.hiddenActions.contains(action.rawValue)
        }
        refreshActionTitles()
        buttons[.primaryFire]?.accessibilityHint = active
            ? "Clicks the current Unreal Tournament menu item."
            : accessibilityHint(for: .primaryFire)
        buttons[.pause]?.setTitle(active ? "BACK" : "MENU")
        setNeedsLayout()
    }

    private func updateLayoutModeAppearance() {
        let active = editingLayout || testingLayout
        layoutBanner.text = editingLayout ? "EDIT TOUCH LAYOUT" : "TEST TOUCH LAYOUT"
        backgroundColor = editingLayout
            ? UIColor.black.withAlphaComponent(0.28)
            : (testingLayout ? UIColor.black.withAlphaComponent(0.08) : .clear)
        safeAreaGuide.isHidden = !active
        layoutBanner.isHidden = !active
        layoutDoneButton.isHidden = !active
        layoutSizeControls.isHidden = !editingLayout
        if editingLayout { selectLayoutControl(selectedLayoutKey) }
        for button in buttons.values {
            button.isUserInteractionEnabled = true
            button.setEditing(editingLayout)
        }
        weaponRail.isHidden = true
        movePad.backgroundColor = editingLayout ? UIColor.black.withAlphaComponent(0.12) : .clear
        movePad.layer.borderWidth = editingLayout ? 1 : 0
        movePad.layer.borderColor = UIColor(red: 0.35, green: 0.92, blue: 0.88, alpha: 0.42).cgColor
        movePad.layer.cornerRadius = 14
        moveRing.isHidden = !active && moveAnchor == nil && accessibilityMovement == .zero
        lookRing.isHidden = !testingLayout && lookAnchor == nil
        setNeedsLayout()
    }

    private func updateSafeAreaGuide() {
        safeAreaGuide.frame = bounds.inset(by: safeAreaInsets).insetBy(dx: 8, dy: 8)
    }

    @objc private func finishLayoutEditing() {
        if editingLayout { savePlacements() }
        editingLayout = false
        testingLayout = false
        updateLayoutModeAppearance()
    }

    @objc private func layoutControlSelected(_ gesture: UITapGestureRecognizer) {
        guard editingLayout, let button = gesture.view as? UIButton,
              let action = action(for: button.tag) else { return }
        selectLayoutControl(layoutKey(for: action))
    }

    @objc private func layoutMoveSelected(_ gesture: UITapGestureRecognizer) {
        guard editingLayout else { return }
        selectLayoutControl("move")
    }

    private func selectLayoutControl(_ key: String) {
        selectedLayoutKey = key
        let title: String
        if key == "move" {
            title = "MOVE"
        } else if key == "menuSelect" {
            title = "SELECT"
        } else if key == "menuBack" {
            title = "BACK"
        } else if let action = Action(rawValue: key) {
            title = self.title(for: action)
        } else {
            title = key.uppercased()
        }
        layoutSizeLabel.text = "SIZE · \(title)"
        layoutSizeSlider.value = Float(resolvedPlacement(for: key)?.scale ?? 1)
        layoutSizeSlider.accessibilityValue = "\(Int(layoutSizeSlider.value * 100)) percent"
    }

    @objc private func layoutSizeChanged(_ sender: UISlider) {
        guard editingLayout, bounds.width > 0, bounds.height > 0 else { return }
        var placement: UT99TouchPlacement
        if let existing = resolvedPlacement(for: selectedLayoutKey) {
            placement = existing
        } else if selectedLayoutKey == "move" {
            let center = CGPoint(x: movePad.frame.minX + moveRing.center.x,
                                 y: movePad.frame.minY + moveRing.center.y)
            placement = UT99TouchPlacement(x: center.x / bounds.width, y: center.y / bounds.height, scale: 1)
        } else if let action = action(forLayoutKey: selectedLayoutKey), let button = buttons[action] {
            placement = UT99TouchPlacement(x: button.center.x / bounds.width,
                                           y: button.center.y / bounds.height,
                                           scale: 1)
        } else {
            return
        }
        placement.scale = CGFloat(sender.value)
        placements[selectedLayoutKey] = placement
        sender.accessibilityValue = "\(Int(sender.value * 100)) percent"
        setNeedsLayout()
    }

    @objc private func layoutSizeFinished(_ sender: UISlider) {
        guard editingLayout else { return }
        savePlacements()
    }

    @objc private func layoutPanChanged(_ gesture: UIPanGestureRecognizer) {
        guard editingLayout, let button = gesture.view as? UIButton,
              let action = action(for: button.tag), bounds.width > 0, bounds.height > 0 else { return }
        let point = gesture.location(in: self)
        let halfWidth = button.bounds.width / 2
        let halfHeight = button.bounds.height / 2
        let x = min(max(point.x, halfWidth), bounds.width - halfWidth) / bounds.width
        let y = min(max(point.y, halfHeight), bounds.height - halfHeight) / bounds.height
        let key = layoutKey(for: action)
        var placement = resolvedPlacement(for: key) ?? UT99TouchPlacement(x: x, y: y, scale: 1)
        placement.x = x
        placement.y = y
        placements[key] = placement
        selectLayoutControl(key)
        button.center = CGPoint(x: x * bounds.width, y: y * bounds.height)
        if gesture.state == .ended || gesture.state == .cancelled {
            NSLog("UT99 touch layout moved action=%@ x=%.3f y=%.3f", key, placement.x, placement.y)
            savePlacements()
        }
    }

    @objc private func layoutPinchChanged(_ gesture: UIPinchGestureRecognizer) {
        guard editingLayout, let button = gesture.view as? UIButton,
              let action = action(for: button.tag) else { return }
        let key = layoutKey(for: action)
        var placement = resolvedPlacement(for: key) ?? UT99TouchPlacement(
            x: button.center.x / max(bounds.width, 1),
            y: button.center.y / max(bounds.height, 1),
            scale: 1
        )
        placement.scale = min(max(placement.scale * gesture.scale, 0.70), 1.50)
        placements[key] = placement
        selectLayoutControl(key)
        button.bounds.size = CGSize(width: button.bounds.width * gesture.scale,
                                    height: button.bounds.height * gesture.scale)
        button.layer.cornerRadius = button.bounds.width / 2
        gesture.scale = 1
        if gesture.state == .ended || gesture.state == .cancelled { savePlacements() }
    }

    @objc private func layoutZonePinchChanged(_ gesture: UIPinchGestureRecognizer) {
        guard editingLayout, let view = gesture.view else { return }
        let key = "move"
        var placement = resolvedPlacement(for: key) ?? UT99TouchPlacement(
            x: view.center.x / max(bounds.width, 1),
            y: view.center.y / max(bounds.height, 1),
            scale: 1
        )
        placement.scale = min(max(placement.scale * gesture.scale, 0.70), 1.40)
        placements[key] = placement
        selectLayoutControl(key)
        gesture.scale = 1
        setNeedsLayout()
        if gesture.state == .ended || gesture.state == .cancelled { savePlacements() }
    }

    @objc private func moveChanged(_ gesture: UIPanGestureRecognizer) {
        if editingLayout {
            let point = gesture.location(in: self)
            let radius = moveDiameter / 2
            let zone = movePad.frame
            let clampedX = min(max(point.x, zone.minX + radius), zone.maxX - radius)
            let clampedY = min(max(point.y, radius), bounds.height - radius)
            let x = clampedX / max(bounds.width, 1)
            let y = clampedY / max(bounds.height, 1)
            let scale = resolvedPlacement(for: "move")?.scale ?? 1
            placements["move"] = UT99TouchPlacement(x: x, y: y, scale: scale)
            moveRing.center = CGPoint(x: clampedX - zone.minX, y: clampedY)
            selectLayoutControl("move")
            if gesture.state == .ended || gesture.state == .cancelled { savePlacements() }
            return
        }
        // Direct stick input takes ownership from any held accessibility
        // direction. Without this reset, a later layout pass could redraw a
        // stale assistive direction after the physical pan had released it.
        accessibilityMovement = .zero
        movePad.accessibilityValue = gesture.state == .ended || gesture.state == .cancelled
            ? "Stopped"
            : "Touch input"
        let point = gesture.location(in: movePad)
        if gesture.state == .began || moveAnchor == nil {
            moveAnchor = point
            moveRing.center = point
            moveRing.isHidden = false
            moveThumb.transform = .identity
            onMove?(.zero, true)
        }
        guard let anchor = moveAnchor else { return }
        let value = normalizedStickValue(
            point: point,
            center: anchor,
            radius: moveDiameter * 0.5,
            invertY: true
        )
        let travel = max(0, moveDiameter * 0.5 - moveThumb.bounds.width * 0.5 - 4)
        moveThumb.transform = CGAffineTransform(translationX: value.x * travel,
                                                y: -value.y * travel)
        onMove?(value, gesture.state != .ended && gesture.state != .cancelled)
        if gesture.state == .ended || gesture.state == .cancelled {
            moveAnchor = nil
            moveThumb.transform = .identity
            moveRing.isHidden = true
            onMove?(.zero, false)
        }
    }

    @objc private func lookChanged(_ gesture: UIPanGestureRecognizer) {
        guard !editingLayout, !menuInteractionActive else { return }
        let point = gesture.location(in: lookPad)
        if gesture.state == .began || lookAnchor == nil {
            lookAnchor = point
            lookValue = .zero
            lookRing.center = point
            lookRing.isHidden = false
            lookThumb.transform = .identity
            lookSuppressed = false
            lookFlickStart = touchConfiguration.flickDodgeEnabled ? CACurrentMediaTime() : nil
            if touchConfiguration.flickDodgeEnabled && touchConfiguration.dodgeHaptics { dodgeHaptic.prepare() }
            onLookBegan?()
            startLookDisplayLink()
        }
        guard let anchor = lookAnchor else { return }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            finishLookInput()
            return
        }
        if lookSuppressed { return }
        if let start = lookFlickStart {
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if let direction = UT99FlickDodge.direction(
                for: CGPoint(x: point.x - anchor.x, y: point.y - anchor.y),
                elapsedMilliseconds: elapsed,
                distance: CGFloat(touchConfiguration.flickDodgeDistance),
                windowMilliseconds: Double(touchConfiguration.flickDodgeMilliseconds)
            ) {
                // A fast sideways flick: dodge, hand back the view it turned,
                // and stop looking until this thumb lifts.
                lookFlickStart = nil
                lookSuppressed = true
                lookValue = .zero
                lookThumb.transform = .identity
                if touchConfiguration.dodgeHaptics { dodgeHaptic.impactOccurred(intensity: 0.9) }
                onDodge?(direction, true)
                return
            }
            if elapsed > Double(touchConfiguration.flickDodgeMilliseconds) { lookFlickStart = nil }
        }
        lookValue = normalizedStickValue(
            point: point,
            center: anchor,
            radius: lookDiameter * 0.5,
            invertY: false
        )
        let travel = max(0, lookDiameter * 0.5 - lookThumb.bounds.width * 0.5 - 4)
        lookThumb.transform = CGAffineTransform(
            translationX: lookValue.x * travel,
            y: lookValue.y * travel
        )
    }

    private func startLookDisplayLink() {
        guard lookDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(publishFloatingLook))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        lookDisplayLink = link
    }

    @objc private func publishFloatingLook() {
        guard lookAnchor != nil else { return }
        // The engine bridge consumes relative mouse deltas. Convert the
        // floating stick's held displacement into a small per-frame value so
        // movement is smooth and simultaneous with the independent left stick.
        onLook?(UT99TouchInputTuning.floatingStickLook(lookValue), true)
    }

    private func finishLookInput() {
        lookDisplayLink?.invalidate()
        lookDisplayLink = nil
        lookAnchor = nil
        lookValue = .zero
        lookFlickStart = nil
        lookSuppressed = false
        lookThumb.transform = .identity
        lookRing.isHidden = !testingLayout
        onLook?(.zero, false)
    }

    private func normalizedStickValue(point: CGPoint, center: CGPoint, radius: CGFloat, invertY: Bool) -> CGPoint {
        let safeRadius = max(radius, 1)
        var x = (point.x - center.x) / safeRadius
        var y = (point.y - center.y) / safeRadius
        let length = hypot(x, y)
        if length > 1 {
            x /= length
            y /= length
        }
        return CGPoint(x: x, y: invertY ? -y : y)
    }

    @objc private func pointerChanged(_ gesture: UIHoverGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            pointerLastLocation = point
        case .changed:
            guard let previous = pointerLastLocation else {
                pointerLastLocation = point
                return
            }
            pointerLastLocation = point
            let value = CGPoint(
                x: (point.x - previous.x) / max(bounds.width, 1),
                y: (previous.y - point.y) / max(bounds.height, 1)
            )
            guard abs(value.x) > 0.0001 || abs(value.y) > 0.0001 else { return }
            onLook?(value, true)
        case .ended, .cancelled, .failed:
            pointerLastLocation = nil
            onLook?(.zero, false)
        default:
            break
        }
    }

    /// With button dodging on, ALT is a one-tap left dodge in gameplay and
    /// the DODGE button a one-tap right dodge (see `dodgeTouchBegan`). FIRE
    /// always shoots: it joins the game and hits BT targets.
    private func dodgeDirection(for action: Action) -> UT99DodgeDirection? {
        guard !menuInteractionActive else { return nil }
        if action == .dodgeForward { return .forward }
        if action == .dodgeLeft { return .left }
        guard touchConfiguration.fireButtonsDodge else { return nil }
        return action == .alternateFire ? .left : nil
    }

    @objc private func buttonDown(_ rawSender: UIButton) {
        guard !editingLayout else { return }
        guard let sender = rawSender as? UT99TouchActionButton else { return }
        guard let action = action(for: sender.tag) else { return }
        if let direction = dodgeDirection(for: action) {
            // A dodge is a single gesture: publish it on touch-down and hold
            // no engine input, so the release below only restores the face.
            if touchConfiguration.dodgeHaptics { dodgeHaptic.impactOccurred(intensity: 0.9) }
            updateAppearance(of: sender, for: action, pressed: true)
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            onDodge?(direction, false)
            return
        }
        activeActions.insert(action)
        actionHaptic.impactOccurred(intensity: action == .primaryFire ? 0.72 : 0.46)
        updateAppearance(of: sender, for: action, pressed: true)
        UIView.animate(
            withDuration: 0.09,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            // Match the reference control's unmistakable down state while the
            // haptic confirms the press under the player's thumb.
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        onAction?(action, true)
    }

    @objc private func buttonUp(_ rawSender: UIButton) {
        guard !editingLayout else { return }
        guard let sender = rawSender as? UT99TouchActionButton else { return }
        guard let action = action(for: sender.tag) else { return }
        let wasHeld = activeActions.remove(action) != nil
        updateAppearance(of: sender, for: action, pressed: false)
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.6,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            sender.transform = .identity
        }
        // A FIRE/ALT dodge never pressed an engine input, so there is nothing
        // to release.
        if !wasHeld && dodgeDirection(for: action) != nil { return }
        onAction?(action, false)
    }

    private func holdDuration(for action: Action) -> CFTimeInterval {
        switch action {
        case .pause: Self.menuHoldSeconds
        case .cheat: 0.5
        default: Self.customHoldSeconds
        }
    }

    /// A top-row command that needs no hold fires on its tap's lift.
    private func isTapCommand(_ action: Action) -> Bool {
        Self.commandActions.contains(action) && !Self.holdActions.contains(action)
    }

    @objc private func holdTouchBegan(_ rawSender: UIButton) {
        guard !editingLayout, let sender = rawSender as? UT99TouchActionButton,
              let action = action(for: sender.tag) else { return }
        if action == .customCommand && !touchConfiguration.customHoldToConfirm {
            buttonDown(sender)
            return
        }
        if isTapCommand(action) {
            updateAppearance(of: sender, for: action, pressed: true)
            actionHaptic.impactOccurred(intensity: 0.46)
            return
        }
        finishHold(cancelled: true)
        holdButton = sender
        holdAction = action
        holdStart = CACurrentMediaTime()
        holdFired = false
        updateAppearance(of: sender, for: action, pressed: true)
        actionHaptic.prepare()
        holdRing.removeFromSuperlayer()
        // JK's IOSTouch_MakeHoldRing: a blue ring 2.5 pt inside the edge,
        // filling clockwise from the top.
        let ringRadius = min(sender.bounds.width, sender.bounds.height) / 2 - 2.5
        holdRing.path = UIBezierPath(arcCenter: CGPoint(x: sender.bounds.midX, y: sender.bounds.midY),
                                     radius: max(ringRadius, 1), startAngle: -.pi / 2,
                                     endAngle: 1.5 * .pi, clockwise: true).cgPath
        holdRing.fillColor = UIColor.clear.cgColor
        holdRing.strokeColor = UIColor(red: 0.47, green: 0.78, blue: 1, alpha: 0.95).cgColor
        holdRing.lineWidth = 3
        holdRing.strokeEnd = 0
        sender.layer.addSublayer(holdRing)
        let link = CADisplayLink(target: self, selector: #selector(holdTick))
        link.add(to: .main, forMode: .common)
        holdLink = link
    }

    @objc private func holdTick() {
        guard let action = holdAction, !holdFired else { return }
        let progress = (CACurrentMediaTime() - holdStart) / holdDuration(for: action)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holdRing.strokeEnd = CGFloat(min(progress, 1))
        CATransaction.commit()
        guard progress >= 1 else { return }
        holdFired = true
        actionHaptic.impactOccurred(intensity: 0.9)
        if action == .pause {
            onMenuHold?()
        } else {
            onAction?(action, true)
            onAction?(action, false)
        }
        finishHold(cancelled: false)
    }

    @objc private func holdTouchEnded(_ rawSender: UIButton) {
        guard let sender = rawSender as? UT99TouchActionButton, let action = action(for: sender.tag) else { return }
        if action == .customCommand && !touchConfiguration.customHoldToConfirm && holdAction == nil {
            buttonUp(sender)
            return
        }
        if isTapCommand(action) {
            updateAppearance(of: sender, for: action, pressed: false)
            if !editingLayout && !menuInteractionActive {
                onAction?(action, true)
                onAction?(action, false)
            }
            return
        }
        // A short MENU tap is UT's own menu (Escape); a short CUSTOM tap is
        // deliberately nothing.
        let tapped = holdAction == action && !holdFired
        finishHold(cancelled: true)
        if tapped && action == .pause {
            onAction?(.pause, true)
            onAction?(.pause, false)
        }
    }

    @objc private func holdTouchCancelled(_ rawSender: UIButton) {
        guard let sender = rawSender as? UT99TouchActionButton, let action = action(for: sender.tag) else { return }
        if isTapCommand(action) {
            updateAppearance(of: sender, for: action, pressed: false)
            return
        }
        if action == .customCommand && !touchConfiguration.customHoldToConfirm && holdAction == nil {
            buttonUp(sender)
            return
        }
        finishHold(cancelled: true)
    }

    private func finishHold(cancelled: Bool) {
        holdLink?.invalidate()
        holdLink = nil
        holdRing.removeFromSuperlayer()
        if let button = holdButton, let action = holdAction {
            updateAppearance(of: button, for: action, pressed: false)
        }
        holdButton = nil
        holdAction = nil
    }

    /// FIRE and ALT read as dodge buttons while FIRE/ALT dodging is on.
    private func refreshActionTitles() {
        buttons[.primaryFire]?.setTitle(menuInteractionActive ? "SELECT" : title(for: .primaryFire))
        buttons[.primaryFire]?.accessibilityLabel = menuInteractionActive ? "Select" : title(for: .primaryFire)
        for action in [Action.alternateFire, .dodge] {
            buttons[action]?.setTitle(title(for: action))
            buttons[action]?.accessibilityLabel = title(for: action)
        }
        for action in [Action.primaryFire, .alternateFire, .dodge] where !menuInteractionActive {
            buttons[action]?.accessibilityHint = accessibilityHint(for: action)
        }
    }

    @objc private func dodgeTouchBegan(_ sender: UIButton, forEvent event: UIEvent) {
        guard !editingLayout, !menuInteractionActive,
              let button = sender as? UT99TouchActionButton else { return }
        updateAppearance(of: button, for: .dodge, pressed: true)
        // DODGE ▶: one tap, no swipe, to pair with ◀ DODGE (the swipe pad is
        // gone; dodgeTouchMoved only acts if a swipe origin is ever set).
        dodgeTouchOrigin = nil
        if touchConfiguration.dodgeHaptics { dodgeHaptic.impactOccurred(intensity: 0.9) }
        onDodge?(.right, false)
    }

    @objc private func dodgeTouchMoved(_ sender: UIButton, forEvent event: UIEvent) {
        guard !editingLayout, let origin = dodgeTouchOrigin,
              let button = sender as? UT99TouchActionButton,
              let touch = event.touches(for: sender)?.first else { return }
        let location = touch.location(in: self)
        guard let direction = UT99DodgeGesture.direction(
            for: CGPoint(x: location.x - origin.x, y: location.y - origin.y),
            threshold: CGFloat(touchConfiguration.dodgeSwipeDistance),
            sideOnly: touchConfiguration.dodgeSideOnly
        ) else { return }
        // Fire the moment the swipe commits rather than on lift, and only
        // once per touch: a second dodge needs a fresh swipe.
        dodgeTouchOrigin = nil
        if touchConfiguration.dodgeHaptics { dodgeHaptic.impactOccurred(intensity: 0.9) }
        onDodge?(direction, false)
        updateAppearance(of: button, for: .dodge, pressed: false)
    }

    @objc private func dodgeTouchEnded(_ sender: UIButton) {
        dodgeTouchOrigin = nil
        guard let button = sender as? UT99TouchActionButton else { return }
        updateAppearance(of: button, for: .dodge, pressed: false)
    }

    /// Release every host-owned gameplay input before a menu, lifecycle
    /// transition, or controller takeover. UIKit does not guarantee that a
    /// button receives touchUp after another view becomes interactive, so the
    /// bridge must not depend on UIButton's normal end-of-touch callbacks.
    func releaseActiveInputs() {
        let actions = activeActions
        activeActions.removeAll()
        for action in actions {
            onAction?(action, false)
            if let button = buttons[action] {
                button.transform = .identity
                updateAppearance(of: button, for: action, pressed: false)
            }
        }
        moveAnchor = nil
        finishHold(cancelled: true)
        stopWheelTimer()
        wheelOrigin = nil
        wheelAction = nil
        tauntWheel.close(picking: nil)
        weaponWheel.close(picking: nil)
        if cameraGesture == .burst { onCameraBurst?(false) }
        cameraGesture = .idle
        cameraLink?.invalidate()
        cameraLink = nil
        dodgeTouchOrigin = nil
        if let dodge = buttons[.dodge] { updateAppearance(of: dodge, for: .dodge, pressed: false) }
        finishLookInput()
        accessibilityMovement = .zero
        pointerLastLocation = nil
        moveThumb.transform = .identity
        movePad.accessibilityValue = "Stopped"
        moveRing.isHidden = !(editingLayout || testingLayout)
        onMove?(.zero, false)
        onLook?(.zero, false)
    }

    func applyTouchProfile(_ profile: TouchProfile) {
        releaseActiveInputs()
        let canonical = profile.canonical
        touchProfile = canonical
        UserDefaults.standard.set(canonical.rawValue, forKey: Self.profileDefaultsKey)
        setTouchOpacity(canonical.opacity)
        setNeedsLayout()
    }

    private func actionTag(_ action: Action) -> Int { Action.allCases.firstIndex(of: action) ?? 0 }
    private func action(for tag: Int) -> Action? { Action.allCases.indices.contains(tag) ? Action.allCases[tag] : nil }

    private func title(for action: Action) -> String {
        switch action {
        case .dodge: "DODGE ▶"
        case .dodgeLeft: "◀ DODGE"
        case .alternateFire where touchConfiguration.fireButtonsDodge: "◀ DODGE"
        case .dodgeForward: "▲ DODGE"
        case .primaryFire, .leftPrimaryFire: "FIRE"
        case .alternateFire: "ALT"
        case .jump: "JUMP"
        case .use: "USE"
        case .crouch: "DUCK"
        case .walk: "WALK"
        case .customCommand: "CUSTOM"
        case .nextWeapon: "NEXT\nWPN"
        case .previousWeapon: "WPN −"
        case .scoreboard: "SCORE"
        case .pause: "MENU"
        case .checkpoint: "CP"
        case .noCheckpoint: "NO CP"
        case .suicide: "SUICIDE"
        case .mapVote: "MAP\nVOTE"
        case .team: "TEAM"
        case .taunt: "TAUNT"
        case .camera: "CAMERA"
        case .view: "VIEW"
        case .cheat: "CHEAT"
        }
    }

    private func symbol(for action: Action) -> String {
        switch action {
        case .primaryFire, .leftPrimaryFire: "scope"
        case .alternateFire: "bolt.fill"
        case .jump: "arrow.up"
        case .use: "hand.tap.fill"
        case .crouch: "arrow.down"
        case .dodge: "arrow.left.and.right"
        case .dodgeForward: "arrow.up.to.line"
        case .dodgeLeft: "arrow.left"
        case .walk: "figure.walk"
        case .customCommand: "star.fill"
        case .nextWeapon: "chevron.forward"
        case .previousWeapon: "chevron.backward"
        case .scoreboard: "list.number"
        case .pause: "pause.fill"
        case .checkpoint: "flag.fill"
        case .noCheckpoint: "flag.slash"
        case .suicide: "xmark.octagon"
        case .mapVote: "checklist"
        case .team: "arrow.left.arrow.right"
        case .taunt: "face.smiling"
        case .camera: "camera.fill"
        case .view: "eye"
        case .cheat: "bolt.shield.fill"
        }
    }

    private func visualRole(for action: Action) -> UT99TouchActionButton.Role {
        switch action {
        case .primaryFire, .cheat: .primary
        case .camera: .dPad
        case .leftPrimaryFire: .secondary
        case .pause: .start
        case .scoreboard, .nextWeapon, .previousWeapon, .use: .utility
        case .alternateFire: .secondary
        default: .utility
        }
    }

    private func accessibilityHint(for action: Action) -> String {
        switch action {
        case .dodge: "Dodges right"
        case .dodgeLeft: "Dodges left"
        case .alternateFire where touchConfiguration.fireButtonsDodge: "Dodges left"
        case .dodgeForward: "Dodges forward"
        case .primaryFire, .leftPrimaryFire: "Shoots the current weapon"
        case .alternateFire: "Uses the current weapon's alternate fire"
        case .jump: "Jumps"
        case .use: "Activates doors, lifts, and inventory"
        case .crouch: "Crouches while held"
        case .walk: "Walks slowly and precisely while held"
        case .customCommand: "Runs the console command set in Controls and Display"
        case .nextWeapon: "Selects the next weapon"
        case .previousWeapon: "Selects the previous weapon"
        case .scoreboard: "Shows the match scoreboard"
        case .pause: "Opens the original Unreal Tournament menu. Hold for options."
        case .checkpoint: "Says !cp: sets a Bunny Track checkpoint"
        case .noCheckpoint: "Says !nocp: removes your Bunny Track checkpoint"
        case .suicide: "Hold to respawn"
        case .mapVote: "Opens the server's map vote"
        case .team: "Hold to switch between the red and blue team"
        case .taunt: "Opens the taunt wheel"
        case .camera: "Tap for a photo, slide off sideways for a burst, hold for a selfie"
        case .view: "Switches between first and third person"
        case .cheat: "Hold to switch the cheat off or on"
        }
    }

    private func updateAppearance(of button: UT99TouchActionButton, for action: Action, pressed: Bool) {
        button.setPressed(pressed)
        button.setEditing(editingLayout)
    }

    private func tint(for action: Action) -> UIColor {
        switch action {
        case .primaryFire, .leftPrimaryFire: UIColor(red: 0.08, green: 0.56, blue: 0.29, alpha: 0.92)
        case .alternateFire: UIColor(red: 0.78, green: 0.10, blue: 0.13, alpha: 0.92)
        case .jump, .crouch: UIColor(white: 0.72, alpha: 0.92)
        case .dodge, .dodgeForward, .dodgeLeft: UIColor(red: 0.10, green: 0.40, blue: 0.62, alpha: 0.92)
        case .use, .scoreboard, .nextWeapon, .previousWeapon, .walk, .customCommand: UIColor(white: 0.22, alpha: 0.88)
        case .pause: UIColor(white: 0.28, alpha: 0.92)
        case .checkpoint, .noCheckpoint, .suicide, .mapVote, .team, .taunt, .camera, .view, .cheat:
            UIColor(white: 0.22, alpha: 0.88)
        }
    }

    private func foreground(for action: Action) -> UIColor {
        switch action {
        case .jump, .crouch: UIColor(white: 0.12, alpha: 1)
        default: .white
        }
    }

}
