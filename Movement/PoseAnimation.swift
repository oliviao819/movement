import Foundation

// Drives the workout demonstration figure. Every exercise is modeled as a
// jointed 3D skeleton (meters, floor at y = 0, figure facing +z) that moves
// through the real rep: limbs are posed with forward kinematics, and anything
// planted on the floor or a bench (feet in a squat, hands in a push-up) is
// solved with two-bone IK so it stays put while the body moves. The view
// layer only has to rotate and project the points, which is what makes the
// 360° turn and the motion work together.
//
// Pure Foundation, no SwiftUI, so it can be exercised outside the app.

// MARK: - Math

struct Vec3: Equatable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = Vec3(0, 0, 0)
    static let down = Vec3(0, -1, 0)

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }

    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: Vec3 {
        let len = length
        return len > 1e-9 ? self * (1 / len) : Vec3(0, 1, 0)
    }

    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    func mirroredX() -> Vec3 { Vec3(-x, y, z) }
}

/// Row-major 3×3 rotation matrix. Angles are in degrees.
struct Mat3 {
    var r0: Vec3
    var r1: Vec3
    var r2: Vec3

    static let identity = Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, 1, 0), r2: Vec3(0, 0, 1))

    static func * (m: Mat3, v: Vec3) -> Vec3 { Vec3(m.r0.dot(v), m.r1.dot(v), m.r2.dot(v)) }

    static func * (a: Mat3, b: Mat3) -> Mat3 {
        let c0 = a * (b * Vec3(1, 0, 0))
        let c1 = a * (b * Vec3(0, 1, 0))
        let c2 = a * (b * Vec3(0, 0, 1))
        return Mat3(r0: Vec3(c0.x, c1.x, c2.x), r1: Vec3(c0.y, c1.y, c2.y), r2: Vec3(c0.z, c1.z, c2.z))
    }

    /// Pitch: positive tips +y toward +z (leaning forward).
    static func rotX(_ deg: Double) -> Mat3 {
        let (s, c) = (sin(deg * .pi / 180), cos(deg * .pi / 180))
        return Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, c, -s), r2: Vec3(0, s, c))
    }

    static func rotY(_ deg: Double) -> Mat3 {
        let (s, c) = (sin(deg * .pi / 180), cos(deg * .pi / 180))
        return Mat3(r0: Vec3(c, 0, s), r1: Vec3(0, 1, 0), r2: Vec3(-s, 0, c))
    }

    /// Roll: positive swings a hanging limb toward +x.
    static func rotZ(_ deg: Double) -> Mat3 {
        let (s, c) = (sin(deg * .pi / 180), cos(deg * .pi / 180))
        return Mat3(r0: Vec3(c, -s, 0), r1: Vec3(s, c, 0), r2: Vec3(0, 0, 1))
    }
}

func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func mix(_ a: Vec3, _ b: Vec3, _ t: Double) -> Vec3 { a + (b - a) * t }

/// Smooth 0→1 ramp of `x` across [edge0, edge1].
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

private func easeInOut(_ t: Double) -> Double { 0.5 - 0.5 * cos(min(1, max(0, t)) * .pi) }

// MARK: - Skeleton & scene

/// Index 0 is the figure's right side (−x), index 1 its left side (+x).
struct Skeleton {
    var pelvis = Vec3.zero
    var spine = Vec3.zero
    var chest = Vec3.zero
    var neck = Vec3.zero
    var head = Vec3.zero
    var shoulder = [Vec3.zero, .zero]
    var elbow = [Vec3.zero, .zero]
    var wrist = [Vec3.zero, .zero]
    var grip = [Vec3.zero, .zero]
    var hip = [Vec3.zero, .zero]
    var knee = [Vec3.zero, .zero]
    var ankle = [Vec3.zero, .zero]
    var toe = [Vec3.zero, .zero]

    var allPoints: [Vec3] {
        [pelvis, spine, chest, neck, head] + shoulder + elbow + wrist + grip + hip + knee + ankle + toe
    }

    /// Reflects the figure left↔right, used to show the second side of
    /// one-sided moves.
    func mirrored() -> Skeleton {
        func flip(_ pair: [Vec3]) -> [Vec3] { [pair[1].mirroredX(), pair[0].mirroredX()] }
        var m = self
        m.pelvis = pelvis.mirroredX()
        m.spine = spine.mirroredX()
        m.chest = chest.mirroredX()
        m.neck = neck.mirroredX()
        m.head = head.mirroredX()
        m.shoulder = flip(shoulder)
        m.elbow = flip(elbow)
        m.wrist = flip(wrist)
        m.grip = flip(grip)
        m.hip = flip(hip)
        m.knee = flip(knee)
        m.ankle = flip(ankle)
        m.toe = flip(toe)
        return m
    }
}

struct Dumbbell {
    var center: Vec3
    var axis: Vec3
}

/// Axis-aligned prop such as a bench, step, or chair.
struct PropBox {
    var min: Vec3
    var max: Vec3
}

struct PoseFrame {
    var skeleton = Skeleton()
    var dumbbells: [Dumbbell] = []
    var boxes: [PropBox] = []
    var showsMat = false
    /// Briefly dips to 0 when a one-sided move switches sides.
    var opacity = 1.0
    /// What the figure is doing right now, e.g. "Curl up".
    var cue = ""

    func mirrored() -> PoseFrame {
        var m = self
        m.skeleton = skeleton.mirrored()
        m.dumbbells = dumbbells.map { Dumbbell(center: $0.center.mirroredX(), axis: $0.axis.mirroredX()) }
        m.boxes = boxes.map { PropBox(min: Vec3(-$0.max.x, $0.min.y, $0.min.z), max: Vec3(-$0.min.x, $0.max.y, $0.max.z)) }
        return m
    }
}

// MARK: - Body proportions

private enum Body {
    static let thigh = 0.44
    static let shin = 0.44
    static let upperArm = 0.29
    static let forearm = 0.27
    static let hand = 0.07
    static let foot = 0.16
    static let spineSegment = 0.27
    static let torso = spineSegment * 2
    static let shoulderHalfWidth = 0.19
    static let hipHalfWidth = 0.10
    static let ankleHeight = 0.08
    /// Hip-to-ankle distance for a leg that reads as straight.
    static let straightLeg = thigh + shin - 0.001
    /// Pelvis height standing tall.
    static let standingPelvis = ankleHeight + straightLeg
}

private let sideSign: [Double] = [-1, 1]

// MARK: - Rep timing

/// One rep split into four timed stages: moving toward the end position,
/// holding there, returning, and resting at the start.
private struct Rep {
    let toEnd: Double
    let holdEnd: Double
    let toStart: Double
    let holdStart: Double
    let labels: [String]

    var duration: Double { toEnd + holdEnd + toStart + holdStart }

    /// 0 = start position, 1 = end position, eased; plus the stage label.
    func sample(_ time: Double) -> (value: Double, cue: String) {
        var t = time.truncatingRemainder(dividingBy: duration)
        if t < 0 { t += duration }
        if t < toEnd { return (easeInOut(t / toEnd), labels[0]) }
        t -= toEnd
        if t < holdEnd { return (1, labels[1]) }
        t -= holdEnd
        if t < toStart { return (1 - easeInOut(t / toStart), labels[2]) }
        return (0, labels[3])
    }
}

// MARK: - Rig helpers

/// Two-bone IK: places the middle joint (elbow/knee) so the chain reaches
/// `target`, bending toward `hint`. Returns the middle joint and where the end
/// actually lands (short of the target if it's out of reach).
private func solveIK(root: Vec3, target: Vec3, upper: Double, lower: Double, hint: Vec3) -> (mid: Vec3, end: Vec3) {
    let toTarget = target - root
    let dir = toTarget.normalized
    let dist = min(max(toTarget.length, abs(upper - lower) + 1e-4), upper + lower - 1e-4)
    let along = (upper * upper + dist * dist - lower * lower) / (2 * dist)
    let height = max(0, upper * upper - along * along).squareRoot()
    let bend = (hint - dir * hint.dot(dir)).normalized
    return (root + dir * along + bend * height, root + dir * dist)
}

private struct TorsoFrames {
    let pelvis: Mat3
    let upper: Mat3
}

/// Builds pelvis → spine → chest → head plus shoulders and hips.
/// `pitch` tilts the whole trunk forward (90 = face down, −90 = face up),
/// `upperBend` curls the upper back further, `twist` rotates the chest
/// around the spine, `neck` nods the head forward.
@discardableResult
private func buildTorso(_ sk: inout Skeleton, pelvis: Vec3, pitch: Double, upperBend: Double = 0, twist: Double = 0, neck: Double = 0) -> TorsoFrames {
    let pelvisFrame = Mat3.rotX(pitch)
    let upper = pelvisFrame * Mat3.rotX(upperBend) * Mat3.rotY(twist)
    sk.pelvis = pelvis
    sk.spine = pelvis + pelvisFrame * Vec3(0, Body.spineSegment, 0)
    sk.chest = sk.spine + upper * Vec3(0, Body.spineSegment, 0)
    sk.neck = sk.chest + upper * Vec3(0, 0.07, 0)
    sk.head = sk.neck + upper * Mat3.rotX(neck) * Vec3(0, 0.12, 0.015)
    for i in 0..<2 {
        let s = sideSign[i]
        sk.shoulder[i] = sk.chest + upper * Vec3(s * Body.shoulderHalfWidth, -0.03, 0)
        sk.hip[i] = pelvis + pelvisFrame * Vec3(s * Body.hipHalfWidth, 0, 0)
    }
    return TorsoFrames(pelvis: pelvisFrame, upper: upper)
}

/// Arm by joint angles relative to the chest: `flex` raises it forward
/// (90 = straight ahead, 180 = overhead), `abduct` raises it out to the side,
/// `elbow` bends the forearm forward, `wrist` tips the hand further.
private func poseArm(_ sk: inout Skeleton, _ i: Int, frame: Mat3, flex: Double, abduct: Double = 0, elbow: Double = 0, wrist: Double = 0) {
    let base = frame * Mat3.rotX(-flex) * Mat3.rotZ(sideSign[i] * abduct)
    sk.elbow[i] = sk.shoulder[i] + base * Vec3.down * Body.upperArm
    sk.wrist[i] = sk.elbow[i] + base * Mat3.rotX(-elbow) * Vec3.down * Body.forearm
    sk.grip[i] = sk.wrist[i] + base * Mat3.rotX(-(elbow + wrist)) * Vec3.down * Body.hand
}

/// Arm reaching for a fixed point (bench, floor, dumbbell at the chest).
private func reachArm(_ sk: inout Skeleton, _ i: Int, to target: Vec3, elbowToward hint: Vec3, handDirection: Vec3? = nil) {
    let solved = solveIK(root: sk.shoulder[i], target: target, upper: Body.upperArm, lower: Body.forearm, hint: hint)
    sk.elbow[i] = solved.mid
    sk.wrist[i] = solved.end
    let handDir = handDirection ?? (solved.end - solved.mid)
    sk.grip[i] = solved.end + handDir.normalized * Body.hand
}

/// Straight arm pointing in a world direction.
private func pointArm(_ sk: inout Skeleton, _ i: Int, direction: Vec3) {
    let d = direction.normalized
    sk.elbow[i] = sk.shoulder[i] + d * Body.upperArm
    sk.wrist[i] = sk.elbow[i] + d * Body.forearm
    sk.grip[i] = sk.wrist[i] + d * Body.hand
}

/// Leg by joint angles relative to the pelvis: `flex` lifts the thigh
/// forward, `knee` bends the shin back, `ankle` points the toes.
private func poseLeg(_ sk: inout Skeleton, _ i: Int, frame: Mat3, flex: Double, abduct: Double = 0, knee: Double = 0, ankle: Double = 0) {
    let base = frame * Mat3.rotX(-flex) * Mat3.rotZ(sideSign[i] * abduct)
    sk.knee[i] = sk.hip[i] + base * Vec3.down * Body.thigh
    let shinFrame = base * Mat3.rotX(knee)
    sk.ankle[i] = sk.knee[i] + shinFrame * Vec3.down * Body.shin
    sk.toe[i] = sk.ankle[i] + shinFrame * Mat3.rotX(-90 + ankle) * Vec3.down * Body.foot
}

/// Leg with the ankle planted at `target`.
private func plantLeg(_ sk: inout Skeleton, _ i: Int, ankle target: Vec3, kneeToward hint: Vec3, footDirection: Vec3 = Vec3(0, -0.12, 1)) {
    let solved = solveIK(root: sk.hip[i], target: target, upper: Body.thigh, lower: Body.shin, hint: hint)
    sk.knee[i] = solved.mid
    sk.ankle[i] = solved.end
    sk.toe[i] = solved.end + footDirection.normalized * Body.foot
}

/// Torso pitch that points the trunk along `up` (pelvis → chest).
private func pitch(along up: Vec3) -> Double {
    atan2(up.z, up.y) * 180 / .pi
}

/// Two stance feet, flat, hip-width apart.
private func standOnFloor(_ sk: inout Skeleton, width: Double = 0.12, z: Double = 0, toesOut: Double = 0) {
    for i in 0..<2 {
        let s = sideSign[i]
        plantLeg(&sk, i, ankle: Vec3(s * width, Body.ankleHeight, z), kneeToward: Vec3(s * toesOut, 0, 1), footDirection: Vec3(s * toesOut, -0.12, 1))
    }
}

/// Dumbbell lying across the palm, perpendicular to the forearm.
private func dumbbellInHand(_ sk: Skeleton, _ i: Int, axis: Vec3) -> Dumbbell {
    Dumbbell(center: mix(sk.wrist[i], sk.grip[i], 0.6), axis: axis.normalized)
}

// MARK: - Poses

enum PoseAnimator {
    static func frame(for pose: WorkoutPose, time: Double) -> PoseFrame {
        switch pose {
        case .wristCurl: return wristCurl(time)
        case .curl: return bicepsCurl(time, hammer: false)
        case .hammerCurl: return bicepsCurl(time, hammer: true)
        case .hold: return farmerHold(time)
        case .dip: return benchDip(time)
        case .overheadExtension: return overheadExtension(time)
        case .squat: return gobletSquat(time)
        case .stepUp: return stepUp(time)
        case .calfRaise: return calfRaise(time, singleLeg: false)
        case .singleLegCalfRaise: return calfRaise(time, singleLeg: true)
        case .hinge: return hipHinge(time)
        case .bridge: return bridgeWalkout(time)
        case .pushUp: return inclinePushUp(time)
        case .press: return floorPress(time)
        case .row: return bentRow(time)
        case .fly: return reverseFly(time)
        case .deadBug: return deadBug(time)
        case .plank: return forearmPlank(time)
        case .march: return marchAndPress(time)
        case .reach: return squatToReach(time)
        case .stretch: return worldsGreatestStretch(time)
        case .catCow: return catCow(time)
        }
    }

    // MARK: Arms

    private static func wristCurl(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.1, holdEnd: 0.3, toStart: 1.5, holdStart: 0.3, labels: ["Curl wrists up", "Squeeze", "Lower slowly", "Forearms rest on thighs"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        // Seated on a bench, leaning forward so the forearms rest on the thighs.
        buildTorso(&sk, pelvis: Vec3(0, 0.55, -0.08), pitch: 30, neck: 18)
        for i in 0..<2 {
            plantLeg(&sk, i, ankle: Vec3(sideSign[i] * 0.15, Body.ankleHeight, 0.40), kneeToward: Vec3(0, 1, 1))
        }
        let palmAngle = mix(-60, 48, t) * .pi / 180
        for i in 0..<2 {
            let s = sideSign[i]
            let knee = sk.knee[i]
            let wrist = Vec3(s * 0.12, knee.y + 0.06, knee.z + 0.05)
            reachArm(&sk, i, to: wrist, elbowToward: Vec3(s * 0.2, -1, -0.3), handDirection: Vec3(0, sin(palmAngle), cos(palmAngle)))
            f.dumbbells.append(dumbbellInHand(sk, i, axis: Vec3(1, 0, 0)))
        }
        f.skeleton = sk
        f.boxes = [PropBox(min: Vec3(-0.24, 0, -0.38), max: Vec3(0.24, 0.45, 0.10))]
        return f
    }

    private static func bicepsCurl(_ time: Double, hammer: Bool) -> PoseFrame {
        // Tempo curl: two counts up, pause, three counts down.
        let rep = hammer
            ? Rep(toEnd: 1.3, holdEnd: 0.3, toStart: 1.7, holdStart: 0.4, labels: ["Curl up, thumbs high", "Squeeze", "Lower with control", "Arms long"])
            : Rep(toEnd: 2.0, holdEnd: 0.6, toStart: 3.0, holdStart: 0.4, labels: ["Curl up · 2 counts", "Pause", "Lower · 3 counts", "Arms long"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let frames = buildTorso(&sk, pelvis: Vec3(0, Body.standingPelvis, 0), pitch: 0)
        standOnFloor(&sk)
        for i in 0..<2 {
            // Elbows stay pinned at the sides; only the forearm travels.
            poseArm(&sk, i, frame: frames.upper, flex: mix(2, 10, t), abduct: 7, elbow: mix(6, 138, t))
            let forearm = (sk.wrist[i] - sk.elbow[i]).normalized
            let lateral = frames.upper * Vec3(1, 0, 0)
            let axis = hammer ? lateral.cross(forearm) : lateral
            f.dumbbells.append(dumbbellInHand(sk, i, axis: axis))
        }
        f.skeleton = sk
        return f
    }

    private static func farmerHold(_ time: Double) -> PoseFrame {
        let breath = 0.5 - 0.5 * cos(time * 2 * .pi / 4)
        var f = PoseFrame(cue: breath > 0.5 ? "Grow tall · inhale" : "Stay braced · exhale")
        var sk = Skeleton()
        let frames = buildTorso(&sk, pelvis: Vec3(0, Body.standingPelvis + 0.004 * breath, 0), pitch: 0, upperBend: -2 * breath)
        standOnFloor(&sk)
        for i in 0..<2 {
            poseArm(&sk, i, frame: frames.upper, flex: 2, abduct: 8 + breath, elbow: 4)
            f.dumbbells.append(dumbbellInHand(sk, i, axis: Vec3(0, 0, 1)))
        }
        f.skeleton = sk
        return f
    }

    private static func benchDip(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.6, holdEnd: 0.3, toStart: 1.2, holdStart: 0.4, labels: ["Bend elbows back", "Hold", "Press through palms", "Chest broad"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        // Hands on the bench edge behind the hips; the body lowers straight down.
        let handY = 0.46
        let chestZ = -0.02
        let shoulderY = handY + mix(0.49, 0.25, t)
        let tilt = 6.0
        let up = Vec3(0, cos(tilt * .pi / 180), sin(tilt * .pi / 180))
        let chest = Vec3(0, shoulderY + 0.03, chestZ)
        buildTorso(&sk, pelvis: chest - up * Body.torso, pitch: tilt)
        for i in 0..<2 {
            let s = sideSign[i]
            reachArm(&sk, i, to: Vec3(s * 0.20, handY, -0.25), elbowToward: Vec3(s * 0.1, 0, -1), handDirection: Vec3(0, 0, -1))
            plantLeg(&sk, i, ankle: Vec3(s * 0.13, Body.ankleHeight, 0.62), kneeToward: Vec3(0, 1, 0.3))
        }
        f.skeleton = sk
        f.boxes = [PropBox(min: Vec3(-0.36, 0, -0.62), max: Vec3(0.36, 0.45, -0.20))]
        return f
    }

    private static func overheadExtension(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.6, holdEnd: 0.2, toStart: 1.2, holdStart: 0.4, labels: ["Bend elbows, weight behind head", "Elbows point up", "Extend overhead", "Ribs stacked"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        buildTorso(&sk, pelvis: Vec3(0, Body.standingPelvis, 0), pitch: 0)
        standOnFloor(&sk)
        // Upper arms stay still beside the ears; only the elbows bend.
        let bend = mix(4, 135, t) * .pi / 180
        for i in 0..<2 {
            let s = sideSign[i]
            sk.elbow[i] = sk.shoulder[i] + Vec3(-s * 0.26, 1, 0.06).normalized * Body.upperArm
            let forearm = Vec3(-s * 0.14, cos(bend), -sin(bend)).normalized
            sk.wrist[i] = sk.elbow[i] + forearm * Body.forearm
            sk.grip[i] = sk.wrist[i] + forearm * Body.hand
        }
        let forearm = (sk.wrist[0] - sk.elbow[0] + sk.wrist[1] - sk.elbow[1]).normalized
        f.dumbbells = [Dumbbell(center: mix(sk.grip[0], sk.grip[1], 0.5) + forearm * 0.06, axis: forearm)]
        f.skeleton = sk
        return f
    }

    // MARK: Legs

    private static func gobletSquat(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.8, holdEnd: 0.3, toStart: 1.4, holdStart: 0.5, labels: ["Sit hips down", "Hold the bottom", "Press the floor away", "Stand tall"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let frames = buildTorso(&sk, pelvis: Vec3(0, mix(0.93, 0.50, t), mix(0, -0.20, t)), pitch: mix(4, 34, t))
        for i in 0..<2 {
            let s = sideSign[i]
            // Knees track out over the toes.
            plantLeg(&sk, i, ankle: Vec3(s * 0.17, Body.ankleHeight, 0.02), kneeToward: Vec3(s * 0.35, 0, 1), footDirection: Vec3(s * 0.3, -0.12, 1))
        }
        // Weight held vertically at the chest, cupped in both hands.
        let forward = frames.upper * Vec3(0, 0, 1)
        let downward = frames.upper * Vec3.down
        let bell = sk.chest + forward * 0.2 + downward * 0.14
        for i in 0..<2 {
            let s = sideSign[i]
            reachArm(&sk, i, to: bell + frames.upper * Vec3(s * 0.05, 0.05, -0.02), elbowToward: frames.upper * Vec3(s * 0.3, -1, 0.2), handDirection: frames.upper * Vec3(-s, 0.3, 0.3))
        }
        f.dumbbells = [Dumbbell(center: bell, axis: frames.upper * Vec3(0, 1, 0))]
        f.skeleton = sk
        return f
    }

    private static func stepUp(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.5, holdEnd: 0.4, toStart: 1.7, holdStart: 0.5, labels: ["Drive through the heel", "Stand tall", "Step down with control", "Foot fully on the step"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let stepHeight = 0.35
        let lead = 1, trail = 0
        let rise = smoothstep(0, 0.85, t)
        let pelvis = mix(Vec3(0, 0.80, 0.05), Vec3(0, stepHeight + 0.94, 0.30), rise)
        let frames = buildTorso(&sk, pelvis: pelvis, pitch: mix(14, 3, rise))
        plantLeg(&sk, lead, ankle: Vec3(0.11, stepHeight + Body.ankleHeight, 0.32), kneeToward: Vec3(0, 0, 1))
        // Trailing foot pushes off, then comes up to meet the lead foot.
        let travel = smoothstep(0.2, 1.0, t)
        let trailAnkle = mix(Vec3(-0.11, Body.ankleHeight, -0.16), Vec3(-0.11, stepHeight + Body.ankleHeight, 0.32), travel) + Vec3(0, sin(travel * .pi) * 0.14, 0)
        plantLeg(&sk, trail, ankle: trailAnkle, kneeToward: Vec3(0, 0, 1), footDirection: Vec3(0, -0.12 - 0.4 * sin(travel * .pi), 1))
        for i in 0..<2 {
            poseArm(&sk, i, frame: frames.upper, flex: (i == lead ? -1 : 1) * 14 * (1 - rise) + 6, abduct: 6, elbow: 25)
        }
        f.skeleton = sk
        f.boxes = [PropBox(min: Vec3(-0.32, 0, 0.12), max: Vec3(0.32, stepHeight, 0.62))]
        return f
    }

    private static func calfRaise(_ time: Double, singleLeg: Bool) -> PoseFrame {
        let rep = Rep(toEnd: 1.0, holdEnd: 0.7, toStart: 1.6, holdStart: 0.4, labels: ["Rise onto the balls of the feet", "Pause at the top", "Lower slowly", "Heels down"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let lift = mix(0, 34, t) * .pi / 180
        let standing = singleLeg ? [1] : [0, 1]
        // The ball of the foot stays planted; the heel and the whole body rise.
        var ankles: [Vec3] = []
        for i in standing {
            let ball = Vec3(sideSign[i] * (singleLeg ? 0.07 : 0.11), 0.02, 0.13)
            let offset = Vec3(0, 0.06 * cos(lift) + 0.13 * sin(lift), 0.06 * sin(lift) - 0.13 * cos(lift))
            ankles.append(ball + offset)
        }
        let base = ankles.reduce(Vec3.zero, +) * (1 / Double(ankles.count))
        let frames = buildTorso(&sk, pelvis: Vec3(singleLeg ? 0.03 : 0, base.y + Body.straightLeg, base.z), pitch: 3)
        for (n, i) in standing.enumerated() {
            let ball = Vec3(ankles[n].x, 0.02, 0.13)
            plantLeg(&sk, i, ankle: ankles[n], kneeToward: Vec3(0, 0, 1), footDirection: ball + Vec3(0, 0, 0.03) - ankles[n])
        }
        if singleLeg {
            poseLeg(&sk, 0, frame: frames.pelvis, flex: 12, knee: 80, ankle: 20)
        }
        // Fingertips rest on a chair back for balance.
        for i in 0..<2 {
            let s = sideSign[i]
            reachArm(&sk, i, to: Vec3(s * 0.20, 1.03, 0.43), elbowToward: Vec3(s * 0.4, -1, -0.3), handDirection: Vec3(0, -0.3, 1))
        }
        f.skeleton = sk
        f.boxes = [
            PropBox(min: Vec3(-0.25, 0.45, 0.42), max: Vec3(0.25, 1.0, 0.47)),
            PropBox(min: Vec3(-0.25, 0.40, 0.42), max: Vec3(0.25, 0.45, 0.88))
        ]
        return f
    }

    private static func hipHinge(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.6, holdEnd: 0.3, toStart: 1.3, holdStart: 0.5, labels: ["Send hips back", "Long spine", "Squeeze glutes to stand", "Stand tall"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let lean = mix(0, 70, t)
        let frames = buildTorso(&sk, pelvis: Vec3(0, mix(Body.standingPelvis - 0.01, 0.88, t), mix(0, -0.18, t)), pitch: lean)
        standOnFloor(&sk, z: 0.02)
        for i in 0..<2 {
            // Arms hang straight down so the weights slide along the thighs.
            poseArm(&sk, i, frame: frames.upper, flex: lean * 0.92, abduct: 4)
            f.dumbbells.append(dumbbellInHand(sk, i, axis: Vec3(1, 0, 0)))
        }
        f.skeleton = sk
        return f
    }

    private static func bridgeWalkout(_ time: Double) -> PoseFrame {
        let duration = 9.0
        var c = time.truncatingRemainder(dividingBy: duration) / duration
        if c < 0 { c += 1 }
        var f = PoseFrame(showsMat: true)
        var sk = Skeleton()

        let stepLength = 0.14
        let startFeetZ = 0.42
        // Four small alternating steps out (right, left, right, left), then back.
        func feetZ(stepsProgress p: Double) -> [Double] {
            var z = [startFeetZ, startFeetZ]
            for step in 0..<4 {
                let local = min(1, max(0, p * 4 - Double(step)))
                z[step % 2] += stepLength * easeInOut(local)
            }
            return z
        }
        var hipsUp = 1.0
        var feet: [Double]
        var stepping: (foot: Int, phase: Double)?
        switch c {
        case ..<0.12:
            hipsUp = easeInOut(c / 0.12)
            feet = [startFeetZ, startFeetZ]
            f.cue = "Lift hips"
        case ..<0.44:
            let p = (c - 0.12) / 0.32
            feet = feetZ(stepsProgress: p)
            stepping = (Int(min(3, p * 4)) % 2, (p * 4).truncatingRemainder(dividingBy: 1))
            f.cue = "Walk heels out"
        case ..<0.56:
            feet = feetZ(stepsProgress: 1)
            f.cue = "Keep hips lifted"
        case ..<0.88:
            let p = (c - 0.56) / 0.32
            feet = feetZ(stepsProgress: 1 - p)
            stepping = (Int(min(3, (1 - p) * 4)) % 2, ((1 - p) * 4).truncatingRemainder(dividingBy: 1))
            f.cue = "Walk back in"
        default:
            hipsUp = 1 - easeInOut((c - 0.88) / 0.12)
            feet = [startFeetZ, startFeetZ]
            f.cue = "Lower with control"
        }

        // Shoulders stay on the mat; the hips lift and lower a bit as the feet travel out.
        let chest = Vec3(0, 0.12, -0.50)
        let liftedHeight = 0.40 - ((feet[0] + feet[1]) / 2 - startFeetZ) * 0.4
        let rise = mix(0.10, liftedHeight, hipsUp) - chest.y
        let pelvis = Vec3(0, chest.y + rise, chest.z + (Body.torso * Body.torso - rise * rise).squareRoot())
        let trunk = pitch(along: chest - pelvis)
        buildTorso(&sk, pelvis: pelvis, pitch: trunk, neck: -90 - trunk)
        for i in 0..<2 {
            let s = sideSign[i]
            var lift = 0.0
            if let stepping, stepping.foot == i { lift = sin(stepping.phase * .pi) * 0.04 }
            plantLeg(&sk, i, ankle: Vec3(s * 0.12, Body.ankleHeight + lift, feet[i]), kneeToward: Vec3(0, 1, 0.3))
            reachArm(&sk, i, to: Vec3(s * 0.30, 0.03, -0.08), elbowToward: Vec3(s, 0.3, 0), handDirection: Vec3(0, 0, 1))
        }
        f.skeleton = sk
        return f
    }

    // MARK: Upper body

    private static func inclinePushUp(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.5, holdEnd: 0.2, toStart: 1.1, holdStart: 0.5, labels: ["Lower chest to the bench", "Body in one line", "Press away", "Arms long"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let benchTop = 0.45
        let hands = Vec3(0, benchTop + 0.02, 0.62)
        let ankles = Vec3(0, 0.12, -0.92)
        let reach = Body.straightLeg + Body.torso
        // Pivot the rigid body around the toes until the shoulders sit the
        // right distance from the hands (arms long at the top, chest near the bench at the bottom).
        let wanted = mix(0.53, 0.27, t)
        var angle = 70.0
        while angle > 0 {
            let chest = ankles + Vec3(0, sin(angle * .pi / 180), cos(angle * .pi / 180)) * reach
            if (chest - hands).length <= wanted { break }
            angle -= 0.25
        }
        let up = Vec3(0, sin(angle * .pi / 180), cos(angle * .pi / 180))
        buildTorso(&sk, pelvis: ankles + up * Body.straightLeg, pitch: pitch(along: up))
        for i in 0..<2 {
            let s = sideSign[i]
            reachArm(&sk, i, to: hands + Vec3(s * 0.27, 0, 0), elbowToward: Vec3(s * 0.5, 0.5, -0.7), handDirection: Vec3(0, 0, 1))
            plantLeg(&sk, i, ankle: ankles + Vec3(s * 0.10, 0, 0), kneeToward: Vec3(0, -1, 0), footDirection: Vec3(0, -0.10, 0.12))
        }
        f.skeleton = sk
        f.boxes = [PropBox(min: Vec3(-0.42, 0, 0.52), max: Vec3(0.42, benchTop, 0.95))]
        return f
    }

    private static func floorPress(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.2, holdEnd: 0.3, toStart: 1.6, holdStart: 0.4, labels: ["Press above the chest", "Wrists over elbows", "Lower until arms touch the floor", "Elbows rest"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(showsMat: true, cue: cue)
        var sk = Skeleton()
        buildTorso(&sk, pelvis: Vec3(0, 0.10, 0.04), pitch: -90)
        let chestZ = sk.chest.z
        for i in 0..<2 {
            let s = sideSign[i]
            plantLeg(&sk, i, ankle: Vec3(s * 0.14, Body.ankleHeight, 0.44), kneeToward: Vec3(0, 1, 0.3))
            let wrist = mix(Vec3(s * 0.31, 0.33, chestZ + 0.08), Vec3(s * 0.17, 0.64, chestZ + 0.05), t)
            reachArm(&sk, i, to: wrist, elbowToward: Vec3(s, -0.8, 0.3), handDirection: Vec3(0, 1, 0))
            f.dumbbells.append(Dumbbell(center: mix(sk.wrist[i], sk.grip[i], 0.6), axis: Vec3(1, 0, 0)))
        }
        f.skeleton = sk
        return f
    }

    private static func bentRow(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.2, holdEnd: 0.4, toStart: 1.5, holdStart: 0.4, labels: ["Pull elbows to back pockets", "Squeeze shoulder blades", "Lower without rounding", "Arms long"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let lean = 50.0
        let frames = buildTorso(&sk, pelvis: Vec3(0, 0.88, -0.14), pitch: lean)
        standOnFloor(&sk, z: 0.03)
        for i in 0..<2 {
            // Forearms stay vertical: elbow bend makes up for the upper arm swinging back.
            let flex = mix(lean, -25, t)
            poseArm(&sk, i, frame: frames.upper, flex: flex, abduct: mix(4, 14, t), elbow: lean - flex)
            f.dumbbells.append(dumbbellInHand(sk, i, axis: Vec3(0, 0, 1)))
        }
        f.skeleton = sk
        return f
    }

    private static func reverseFly(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.2, holdEnd: 0.4, toStart: 1.5, holdStart: 0.4, labels: ["Open arms wide", "Shoulders down", "Lower with control", "Soft elbows"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let lean = 45.0
        let frames = buildTorso(&sk, pelvis: Vec3(0, 0.89, -0.12), pitch: lean)
        standOnFloor(&sk, z: 0.03)
        for i in 0..<2 {
            poseArm(&sk, i, frame: frames.upper, flex: lean, abduct: mix(6, 82, t), elbow: 16)
            f.dumbbells.append(dumbbellInHand(sk, i, axis: Vec3(0, 0, 1)))
        }
        f.skeleton = sk
        return f
    }

    private static func deadBug(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 1.6, holdEnd: 0.3, toStart: 1.4, holdStart: 0.4, labels: ["Lower opposite arm and leg", "Low back stays down", "Return to tabletop", "Arms up, knees over hips"])
        // Alternate sides each rep: right arm with left leg, then the reverse.
        let repIndex = Int(floor(time / rep.duration))
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(showsMat: true, cue: cue)
        var sk = Skeleton()
        let frames = buildTorso(&sk, pelvis: Vec3(0, 0.11, 0.04), pitch: -90)
        let movingArm = repIndex % 2 == 0 ? 0 : 1
        for i in 0..<2 {
            let reaching = i == movingArm
            poseArm(&sk, i, frame: frames.upper, flex: reaching ? mix(90, 172, t) : 90, abduct: 4)
            let extending = i != movingArm
            poseLeg(&sk, i, frame: frames.pelvis, flex: extending ? mix(90, 14, t) : 90, knee: extending ? mix(90, 4, t) : 90, ankle: 10)
        }
        f.skeleton = sk
        return f
    }

    private static func forearmPlank(_ time: Double) -> PoseFrame {
        let breath = 0.5 - 0.5 * cos(time * 2 * .pi / 4)
        var f = PoseFrame(showsMat: true, cue: breath > 0.5 ? "Push the floor away" : "Breathe · hips level")
        var sk = Skeleton()
        let chest = Vec3(0, 0.36, 0.30)
        let ankles = Vec3(0, 0.12, 0)
        let length = Body.straightLeg + Body.torso
        let run = (length * length - (chest.y - ankles.y) * (chest.y - ankles.y)).squareRoot()
        let anchor = Vec3(0, ankles.y, chest.z - run)
        let up = (chest - anchor).normalized
        buildTorso(&sk, pelvis: anchor + up * Body.straightLeg + Vec3(0, 0.008 * breath, 0), pitch: pitch(along: up))
        for i in 0..<2 {
            let s = sideSign[i]
            // Elbows stacked under the shoulders, forearms flat and pointing forward.
            let elbow = Vec3(sk.shoulder[i].x - s * 0.02, 0.05, sk.shoulder[i].z)
            sk.elbow[i] = elbow
            sk.wrist[i] = elbow + Vec3(-s * 0.06, -0.01, 0.26)
            sk.grip[i] = sk.wrist[i] + Vec3(-s * 0.02, 0, 0.07)
            plantLeg(&sk, i, ankle: anchor + Vec3(s * 0.10, 0, 0), kneeToward: Vec3(0, -1, 0), footDirection: Vec3(0, -0.10, 0.12))
        }
        f.skeleton = sk
        return f
    }

    // MARK: Full body

    private static func marchAndPress(_ time: Double) -> PoseFrame {
        let cycle = 2.2
        let phase = time / cycle * 2 * .pi
        var f = PoseFrame(cue: "March and press overhead")
        var sk = Skeleton()
        let press = abs(sin(phase))
        let frames = buildTorso(&sk, pelvis: Vec3(0, Body.standingPelvis + 0.012 * press, 0), pitch: -2)
        for i in 0..<2 {
            let s = sideSign[i]
            let knee = max(0, sin(phase + (i == 0 ? 0 : .pi)))
            let lift = easeInOut(knee)
            poseLeg(&sk, i, frame: frames.pelvis, flex: 72 * lift, knee: 88 * lift + 2, ankle: 12 * lift)
            let low = sk.shoulder[i] + Vec3(s * 0.08, 0.04, 0.10)
            let high = sk.shoulder[i] + Vec3(s * 0.01, 0.55, 0.02)
            reachArm(&sk, i, to: mix(low, high, easeInOut(press)), elbowToward: Vec3(s, -0.7, 0.2), handDirection: Vec3(0, 1, 0))
        }
        f.skeleton = sk
        return f
    }

    private static func squatToReach(_ time: Double) -> PoseFrame {
        let duration = 5.0
        var c = time.truncatingRemainder(dividingBy: duration) / duration
        if c < 0 { c += 1 }
        var squat = 0.0
        var reach = 0.0
        var cue = ""
        switch c {
        case ..<0.30: squat = easeInOut(c / 0.30); cue = "Squat comfortably"
        case ..<0.38: squat = 1; cue = "Sit tall at the bottom"
        case ..<0.66:
            let p = easeInOut((c - 0.38) / 0.28)
            squat = 1 - p; reach = p; cue = "Rise and reach overhead"
        case ..<0.80: reach = 1; cue = "Reach tall, ribs down"
        default: reach = 1 - easeInOut((c - 0.80) / 0.20); cue = "Arms down, reset"
        }
        var f = PoseFrame(cue: cue)
        var sk = Skeleton()
        let frames = buildTorso(&sk, pelvis: Vec3(0, mix(Body.standingPelvis - 0.01, 0.52, squat), mix(0, -0.20, squat)), pitch: mix(1, 32, squat))
        for i in 0..<2 {
            let s = sideSign[i]
            plantLeg(&sk, i, ankle: Vec3(s * 0.16, Body.ankleHeight, 0.02), kneeToward: Vec3(s * 0.3, 0, 1), footDirection: Vec3(s * 0.25, -0.12, 1))
            // Arms float forward for balance in the squat, then sweep overhead.
            poseArm(&sk, i, frame: frames.upper, flex: 80 * squat * (1 - reach) + 172 * reach, abduct: 8 + 6 * reach, elbow: 6)
        }
        f.skeleton = sk
        return f
    }

    private static func worldsGreatestStretch(_ time: Double) -> PoseFrame {
        let sideDuration = 6.0
        let total = sideDuration * 2
        var c = time.truncatingRemainder(dividingBy: total)
        if c < 0 { c += total }
        let secondSide = c >= sideDuration
        let l = (secondSide ? c - sideDuration : c) / sideDuration
        var open = 0.0
        var cue = ""
        switch l {
        case ..<0.15: cue = "Lunge, hand inside front foot"
        case ..<0.45: open = easeInOut((l - 0.15) / 0.30); cue = "Rotate the top arm open"
        case ..<0.65: open = 1; cue = "Turn through the upper back"
        case ..<0.90: open = 1 - easeInOut((l - 0.65) / 0.25); cue = "Return the hand down"
        default: cue = "Switch sides"
        }
        var f = PoseFrame(showsMat: true, cue: cue)
        var sk = Skeleton()
        // Left foot forward, right hand down, left arm opens toward the ceiling.
        let front = 1, back = 0
        buildTorso(&sk, pelvis: Vec3(0, 0.42, 0), pitch: 76, twist: 62 * open, neck: -10 - 15 * open)
        plantLeg(&sk, front, ankle: Vec3(0.14, Body.ankleHeight, 0.50), kneeToward: Vec3(0.2, 1, 0.6))
        plantLeg(&sk, back, ankle: Vec3(-0.12, 0.12, -0.62), kneeToward: Vec3(0, -1, 0.2), footDirection: Vec3(0, -0.10, 0.10))
        reachArm(&sk, back, to: Vec3(0.0, 0.03, 0.48), elbowToward: Vec3(-0.5, 0.2, -0.5), handDirection: Vec3(0, -0.2, 1))
        pointArm(&sk, front, direction: mix(Vec3(0.05, -1, 0.1), Vec3(0.35, 1, -0.05), open))

        f.skeleton = sk
        // Fade between sides so the switch reads as a reset rather than a jump.
        f.opacity = min(1, min(l, 1 - l) / 0.05)
        return secondSide ? f.mirrored() : f
    }

    private static func catCow(_ time: Double) -> PoseFrame {
        let rep = Rep(toEnd: 2.2, holdEnd: 0.6, toStart: 2.2, holdStart: 0.6, labels: ["Exhale, round the spine (cat)", "Chin to chest", "Inhale, arch the spine (cow)", "Gaze forward"])
        let (t, cue) = rep.sample(time)
        var f = PoseFrame(showsMat: true, cue: cue)
        var sk = Skeleton()
        // On hands and knees: wrists under shoulders, knees under hips.
        let pelvis = Vec3(0, 0.53, -0.30)
        let chest = Vec3(0, 0.60, 0.24)
        let spineDir = (chest - pelvis).normalized
        sk.pelvis = pelvis
        sk.chest = chest
        sk.spine = mix(pelvis, chest, 0.5) + Vec3(0, mix(-0.06, 0.09, t), 0)
        sk.neck = chest + spineDir * 0.07
        let gaze = mix(Vec3(0, 0.07, 0.10), Vec3(0, -0.11, 0.05), t)
        sk.head = sk.neck + gaze.normalized * 0.12
        for i in 0..<2 {
            let s = sideSign[i]
            sk.shoulder[i] = chest + Vec3(s * Body.shoulderHalfWidth, -0.02, 0)
            sk.hip[i] = pelvis + Vec3(s * Body.hipHalfWidth, 0, 0)
            reachArm(&sk, i, to: Vec3(s * 0.19, 0.03, 0.26), elbowToward: Vec3(0, 0, -1), handDirection: Vec3(0, -0.2, 1))
            plantLeg(&sk, i, ankle: Vec3(s * 0.11, 0.06, -0.74), kneeToward: Vec3(0, -1, 0.6), footDirection: Vec3(0, -0.15, -1))
        }
        f.skeleton = sk
        return f
    }
}

// MARK: - Camera

/// How much room a pose needs on screen, measured once across its whole
/// motion (both sides, all props) so the figure never drifts out of frame.
struct PoseFraming {
    let pivot: Vec3
    /// Farthest horizontal reach from the pivot, which bounds the figure at any rotation.
    let radius: Double
    let topY: Double
    let minZ: Double
    let maxZ: Double
    /// Floor work is viewed from a little higher so it reads even end-on.
    let tilt: Double

    static func of(_ pose: WorkoutPose) -> PoseFraming {
        cache[pose] ?? measure(pose)
    }

    private static let cache: [WorkoutPose: PoseFraming] = Dictionary(uniqueKeysWithValues: WorkoutPose.allCases.map { ($0, measure($0)) })

    private static func measure(_ pose: WorkoutPose) -> PoseFraming {
        var points: [Vec3] = []
        for step in 0..<64 {
            let frame = PoseAnimator.frame(for: pose, time: Double(step) * 0.2)
            points += frame.skeleton.allPoints
            for box in frame.boxes {
                points += [box.min, box.max, Vec3(box.min.x, 0, box.max.z), Vec3(box.max.x, 0, box.min.z)]
            }
        }
        let xs = points.map(\.x), ys = points.map(\.y), zs = points.map(\.z)
        let pivot = Vec3(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, 0, ((zs.min() ?? 0) + (zs.max() ?? 0)) / 2)
        let radius = points.map { Vec3($0.x - pivot.x, 0, $0.z - pivot.z).length }.max() ?? 1
        let top = (ys.max() ?? 1.8) + 0.12
        return PoseFraming(pivot: pivot, radius: radius, topY: top, minZ: zs.min() ?? -1, maxZ: zs.max() ?? 1, tilt: top < 1.2 ? 24 : 12)
    }
}

/// Turns the figure by `rotation` degrees around the vertical axis, tips the
/// view down slightly, and projects with mild perspective into a view of the
/// given size. `depth` grows toward the viewer.
struct PoseCamera {
    let yaw: Double
    let tilt: Double
    let pivot: Vec3
    let scale: Double
    let centerX: Double
    let centerY: Double
    private let midY: Double
    private static let viewerDistance = 5.0

    init(rotation: Double, framing: PoseFraming, width: Double, height: Double) {
        yaw = rotation * .pi / 180
        tilt = framing.tilt * .pi / 180
        pivot = framing.pivot
        midY = framing.topY / 2
        let across = 2 * framing.radius + 0.2
        let tall = framing.topY * cos(tilt) + 2 * framing.radius * sin(tilt) + 0.1
        scale = min(width / across, height / tall) / 1.12
        centerX = width / 2
        centerY = height / 2
    }

    func project(_ p: Vec3) -> (x: Double, y: Double, depth: Double, size: Double) {
        let q = Vec3(p.x - pivot.x, p.y - midY, p.z - pivot.z)
        let x1 = q.x * cos(yaw) + q.z * sin(yaw)
        let z1 = -q.x * sin(yaw) + q.z * cos(yaw)
        let y2 = q.y * cos(tilt) - z1 * sin(tilt)
        let depth = q.y * sin(tilt) + z1 * cos(tilt)
        let perspective = Self.viewerDistance / (Self.viewerDistance - depth)
        let size = scale * perspective
        return (centerX + x1 * size, centerY - y2 * size, depth, size)
    }

    /// Whether a surface with this outward normal faces the viewer.
    func faces(_ normal: Vec3) -> Bool {
        let z1 = -normal.x * sin(yaw) + normal.z * cos(yaw)
        return normal.y * sin(tilt) + z1 * cos(tilt) > 0
    }
}
