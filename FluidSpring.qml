import QtQuick

// ===========================================================================
// FluidSpring — iOS fluid motion driver (analytic damped harmonic oscillator)
// ---------------------------------------------------------------------------
// One driver value, real spring physics, no fixed duration and no easing curve:
//
//     m x'' + c x' + k x = 0        x = value - target
//     w0   = 2π / response          (Apple's "response" = undamped period)
//     zeta = dampingFraction        (Apple's dampingFraction)
//
// The closed form solution is stepped against the wall clock, so retargeting
// mid-flight keeps BOTH value and velocity (C1 continuous — no visible kink,
// no restart from the beginning).
//
//  • tracking = true  -> value follows target 1:1 with zero smoothing (finger
//    down on a slider). Nothing is animated.
//  • tracking = false -> spring. Settles on target and emits settled().
//
// Reduced motion keeps direct manipulation but removes bounce and shortens the
// response (zeta 1.0). It never removes feedback entirely.
// ===========================================================================
Item {
  id: spring

  // ---- Inputs -------------------------------------------------------------
  // Where the value is heading.
  property real target: 0
  // Seconds. Smaller = faster. 0.2-0.3 small controls, 0.4-0.55 large surfaces.
  property real response: 0.4
  // zeta. 1.0 = critically damped (no overshoot), 0.7-0.85 = energetic release.
  property real dampingFraction: 1.0
  // Resting tolerance in value units (progress 0..1 vs pixel offsets differ).
  property real epsilon: 0.0005
  // true = 1:1 tracking, no spring (a finger owns the value).
  property bool tracking: false
  // Honour the platform reduced-motion preference.
  property bool reduceMotion: false

  // ---- Outputs ------------------------------------------------------------
  property real value: 0
  property real velocity: 0
  readonly property bool animating: ticker.running

  // Emitted once the spring has come to rest on `target`.
  signal settled()

  // ---- Helpers ------------------------------------------------------------
  // Jump straight to a value with no motion (initial state, resets).
  function snapTo(v) {
    ticker.stop()
    spring.velocity = 0
    spring.value = v
  }

  // Retarget carrying an explicit velocity (release of a flick, page snap).
  function retarget(v, v0) {
    spring.velocity = v0 || 0
    spring.target = v
    if (!spring.tracking) spring.start()
  }

  function start() {
    if (spring.tracking) return
    if (ticker.running) return
    spring.lastTick = Date.now()
    ticker.start()
  }

  function stop() {
    ticker.stop()
  }

  // ---- Internals ----------------------------------------------------------
  property double lastTick: 0
  property bool ready: false

  // Effective parameters (reduced motion shortens and damps the spring).
  readonly property real effResponse: spring.reduceMotion
    ? Math.min(Math.max(spring.response, 0.05), 0.25)
    : Math.max(spring.response, 0.05)
  readonly property real effZeta: spring.reduceMotion
    ? 1.0
    : Math.max(spring.dampingFraction, 0.05)
  readonly property real omega: 2 * Math.PI / spring.effResponse

  Component.onCompleted: {
    spring.value = spring.target
    spring.velocity = 0
    spring.ready = true
  }

  onTargetChanged: {
    if (!spring.ready) return
    if (spring.tracking) {
      // Tracking owns the value directly; keep the finger 1:1.
      spring.velocity = 0
      spring.value = spring.target
      return
    }
    spring.start()
  }

  onTrackingChanged: {
    if (spring.ready) {
      if (spring.tracking) {
        ticker.stop()
        spring.velocity = 0
        spring.value = spring.target
      } else {
        // Value was already placed by the finger: settle from rest, no fling.
        spring.velocity = 0
        spring.start()
      }
    }
  }

  // Response / damping changes are retargets too, never restarts.
  onResponseChanged: if (spring.ready && !spring.tracking) spring.start()
  onDampingFractionChanged: if (spring.ready && !spring.tracking) spring.start()

  Timer {
    id: ticker
    interval: 8
    repeat: true
    onTriggered: spring.step()
  }

  function step() {
    const now = Date.now()
    const dt = Math.max(0.001, Math.min((now - spring.lastTick) / 1000, 0.05))
    spring.lastTick = now
    spring.advance(dt)
  }

  // Closed-form solution of the damped oscillator for one time step.
  function advance(dt) {
    const w0 = spring.omega
    const zeta = spring.effZeta
    const x = spring.value - spring.target
    const v = spring.velocity
    let nextValue
    let nextVelocity

    if (zeta < 0.999) {
      let wd = w0 * Math.sqrt(1 - zeta * zeta)
      let decay = Math.exp(-zeta * w0 * dt)
      let cosw = Math.cos(wd * dt)
      let sinw = Math.sin(wd * dt)
      let amp = (v + zeta * w0 * x) / wd
      nextValue = spring.target + decay * (x * cosw + amp * sinw)
      nextVelocity = decay * ((amp * wd - zeta * w0 * x) * cosw
                              - (x * wd + zeta * w0 * amp) * sinw)
    } else {
      let decayC = Math.exp(-w0 * dt)
      let slope = v + w0 * x
      nextValue = spring.target + decayC * (x + slope * dt)
      nextVelocity = decayC * (slope - w0 * (x + slope * dt))
    }

    if (!isFinite(nextValue) || !isFinite(nextVelocity)) {
      spring.settle()
      return
    }

    const restX = Math.abs(nextValue - spring.target)
    const restV = Math.abs(nextVelocity)

    spring.value = nextValue
    spring.velocity = nextVelocity

    // Rest only when both position and velocity are quiet, otherwise a fast
    // pass through the target would read as "done" mid-flight.
    if (restX <= spring.epsilon && restV <= spring.epsilon * w0 * 2) spring.settle()
  }

  function settle() {
    ticker.stop()
    spring.velocity = 0
    spring.value = spring.target
    spring.settled()
  }
}
