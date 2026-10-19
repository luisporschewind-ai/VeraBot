import SwiftUI
import VeraBotCore

private struct GameKeySize: PreferenceKey {
  static let defaultValue = CGSize.zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Touch cancellation is separate from release: an interrupted touch cannot restart on resume.
struct GameKey<Label: View>: View {
  let shape: AnyShape
  var heavyImpact = false
  var accessibilityLabelText: String?
  let action: () -> Void
  var onRelease: () -> Void
  let label: Label
  @State private var isPressing = false
  @State private var blockedUntilRelease = false
  @State private var size = CGSize.zero
  @GestureState private var tracking = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    shape: AnyShape, heavyImpact: Bool = false,
    accessibilityLabelText: String? = nil,
    action: @escaping () -> Void, onRelease: @escaping () -> Void = {},
    @ViewBuilder label: () -> Label
  ) {
    self.shape = shape
    self.heavyImpact = heavyImpact
    self.accessibilityLabelText = accessibilityLabelText
    self.action = action
    self.onRelease = onRelease
    self.label = label()
  }

  private var pressed: Bool { isPressing && isEnabled }

  var body: some View {
    decoratedLabel
      .gesture(touchGesture)
      .onChange(of: tracking) { _, active in if !active { cancelPress(block: false) } }
      .onChange(of: isEnabled) { _, enabled in if !enabled { cancelPress(block: tracking) } }
      .onChange(of: scenePhase) { _, phase in if phase != .active { cancelPress(block: tracking) } }
      .onDisappear { cancelPress(block: false) }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabelText ?? "")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction {
        if isEnabled {
          action()
          onRelease()
        }
      }
  }

  private var decoratedLabel: some View {
    label
      .foregroundStyle(Color.brand)
      .frame(minWidth: 44, minHeight: 44)
      .background(Color.sectionFill, in: shape)
      .overlay { shape.fill(Color.primary.opacity(pressed ? 0.07 : 0)).allowsHitTesting(false) }
      .overlay {
        shape.stroke(Color.primary.opacity(pressed ? 0.17 : 0.08), lineWidth: 1).allowsHitTesting(
          false)
      }
      .offset(y: pressed && !reduceMotion ? 2 : 0)
      .background { shape.fill(Color.primary.opacity(0.16)).offset(y: 3) }
      .background {
        GeometryReader { proxy in Color.clear.preference(key: GameKeySize.self, value: proxy.size) }
      }
      .onPreferenceChange(GameKeySize.self) { size = $0 }
      .contentShape(shape)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.7), value: pressed)
      .hapticFeedback(
        .impact(weight: heavyImpact ? .heavy : .medium, intensity: heavyImpact ? 0.85 : 0.65),
        trigger: isPressing
      ) { old, new in
        isEnabled && !old && new
      }
  }

  private var touchGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .updating($tracking) { _, active, _ in active = true }
      .onChanged { value in
        guard isEnabled, !blockedUntilRelease else { return }
        guard CGRect(origin: .zero, size: size).contains(value.location) else {
          cancelPress(block: true)
          return
        }
        if !isPressing {
          isPressing = true
          action()
        }
      }
      .onEnded { _ in cancelPress(block: false) }
  }
  private func cancelPress(block: Bool) {
    if isPressing {
      isPressing = false
      onRelease()
    }
    blockedUntilRelease = block
  }
}

private struct DpadCross: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addRect(CGRect(x: rect.width / 3, y: 0, width: rect.width / 3, height: rect.height))
    path.addRect(CGRect(x: 0, y: rect.height / 3, width: rect.width, height: rect.height / 3))
    return path
  }
}

/// A single repeat clock and last-pressed direction prevent two keys from driving at once.
struct GameDpad: View {
  var onUp: (() -> Void)? = nil
  let onDown: () -> Void
  let onLeft: () -> Void
  let onRight: () -> Void
  var repeatEnabled = true
  var inputEpoch = 0
  @State private var input = TetrisInputState()
  @State private var task: Task<Void, Never>?
  @State private var generation = UUID()
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.scenePhase) private var scenePhase
  private let key: CGFloat = 44
  private var now: Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

  var body: some View {
    VStack(spacing: 0) {
      if let onUp {
        GameKey(
          shape: AnyShape(RoundedRectangle(cornerRadius: 8)), accessibilityLabelText: "向上",
          action: onUp
        ) {
          Image(systemName: "chevron.up").frame(width: key, height: key)
        }
      } else {
        Color.clear.frame(width: key, height: key).accessibilityHidden(true)
      }
      HStack(spacing: 0) {
        arm("chevron.left", "向左", action: .moveLeft)
        Circle().fill(Color.primary.opacity(0.08)).frame(width: 14, height: 14)
          .frame(width: key, height: key).accessibilityHidden(true)
        arm("chevron.right", "向右", action: .moveRight)
      }
      arm("chevron.down", "向下缓降", action: .softDrop)
    }
    .background { DpadCross().fill(Color.primary.opacity(0.08)) }
    .onChange(of: isEnabled) { _, enabled in if !enabled { cancel() } }
    .onChange(of: inputEpoch) { _, _ in cancel() }
    .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
    .onDisappear { cancel() }
  }
  private func arm(_ symbol: String, _ label: String, action: TetrisAction) -> some View {
    GameKey(
      shape: AnyShape(RoundedRectangle(cornerRadius: 8)), accessibilityLabelText: label,
      action: { begin(action) }, onRelease: { release(action) }
    ) {
      Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(
        width: key, height: key)
    }
  }
  private func dispatch(_ action: TetrisAction) {
    switch action {
    case .moveLeft: onLeft()
    case .moveRight: onRight()
    default: onDown()
    }
  }
  private func begin(_ action: TetrisAction) {
    guard isEnabled else { return }
    guard repeatEnabled else {
      dispatch(action)
      return
    }
    let actions = input.press(action, atMilliseconds: now)
    guard !actions.isEmpty else { return }
    actions.forEach(dispatch)
    task?.cancel()
    let token = UUID()
    generation = token
    task = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(10))
        guard !Task.isCancelled, generation == token else { return }
        input.advance(toMilliseconds: now).forEach(dispatch)
      }
    }
  }
  private func release(_ action: TetrisAction) {
    input.release(action)
    if input.heldAction == nil {
      task?.cancel()
      task = nil
      generation = UUID()
    }
  }
  private func cancel() {
    input.cancel()
    task?.cancel()
    task = nil
    generation = UUID()
  }
}

/// 右侧斜排圆形 A / B。A 旋转（右上），B 直接落下（左下）；中文标签放在圆外。
struct GameFaceCluster: View {
  let onA: () -> Void
  let onB: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(spacing: 4) {
        Button(action: onB) {
          Text("B")
            .font(.title3.bold().monospacedDigit())
            .frame(width: 56, height: 56)
        }
        .buttonStyle(GameButtonStyle(heavyImpact: true, shape: AnyShape(Circle())))
        .accessibilityLabel("直接落下")
        Text("直接落下").font(.caption2).foregroundStyle(.secondary)
      }
      .padding(.top, 22)
      VStack(spacing: 4) {
        Button(action: onA) {
          Text("A")
            .font(.title3.bold().monospacedDigit())
            .frame(width: 64, height: 64)
        }
        .buttonStyle(GameButtonStyle(shape: AnyShape(Circle())))
        .accessibilityLabel("旋转")
        Text("旋转").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

/// 下中小胶囊键（START / SELECT）。
struct GamePillKey: View {
  let title: String
  let systemImage: String
  var heavyImpact = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }
    .buttonStyle(GameButtonStyle(heavyImpact: heavyImpact, shape: AnyShape(Capsule())))
  }
}
