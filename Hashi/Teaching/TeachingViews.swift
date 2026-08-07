import SwiftUI

// MARK: - Learn menu

/// The curriculum path: rules first, then one lesson per technique in order,
/// with mastery states alongside.
struct LearnMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        ZStack {
            SeaBackground()
            ScrollView {
                VStack(spacing: 12) {
                    lessonRow(technique: nil)
                    ForEach(Technique.allCases) { technique in
                        lessonRow(technique: technique)
                    }
                }
                .frame(maxWidth: Metrics.column)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Learn")
        .navigationTitleDisplay(.large)
    }

    private func lessonRow(technique: Technique?) -> some View {
        let state = technique.map { mastery.state(of: $0) } ?? .learned
        // Two different locks. Mastery-locked rows are genuinely unreachable,
        // so they stay disabled. Paywalled rows stay tappable — a dead row
        // neither teaches nor sells.
        let masteryLocked = technique.map { mastery.state(of: $0) == .locked } ?? false
        let paywalled = !FeatureGate.isLessonAvailable(technique,
                                                       unlocked: entitlements.isUnlocked)
        let dimmed = masteryLocked || paywalled
        return Button {
            if paywalled {
                paywall.present(.advancedLessons)
            } else {
                path.append(.tutorial(technique))
            }
        } label: {
            // Top-aligned: at accessibility text sizes the summary wraps to
            // several lines, and a centred badge drifts far from its title.
            HStack(alignment: .top, spacing: 14) {
                stateBadge(state, isRules: technique == nil, paywalled: paywalled)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TechniqueContent.lessonTitle(for: technique))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(technique.map { TechniqueContent.summary(for: $0) }
                         ?? "The rules, on one small board.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if paywalled {
                    Text("Unlock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.bridge)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.bridgeWash))
                        .padding(.top, 2)
                } else {
                    Image(systemName: masteryLocked ? "lock" : "chevron.right")
                        .font(.system(size: Metrics.glyph, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 8)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .opacity(dimmed ? 0.6 : 1)
        }
        .buttonStyle(.hashi)
        .disabled(masteryLocked)
        // The badge is accessibilityHidden, so without this every row reads
        // identically to VoiceOver.
        .accessibilityValue(rowState(state, paywalled: paywalled, masteryLocked: masteryLocked))
    }

    private func rowState(_ state: MasteryTracker.MasteryState,
                          paywalled: Bool, masteryLocked: Bool) -> String {
        if paywalled { return "locked, included in the full game" }
        if masteryLocked { return "locked, finish the earlier lessons first" }
        return state == .learned ? "learned" : "available"
    }

    private func stateBadge(_ state: MasteryTracker.MasteryState,
                            isRules: Bool, paywalled: Bool) -> some View {
        // A paywalled row never shows the green "learned" treatment — a
        // paid-but-previously-learned row would otherwise look complete.
        let learned = state == .learned && !paywalled
        return ZStack {
            Circle()
                .fill(learned ? Theme.foam.opacity(0.2) : Theme.bridgeWash)
            Image(systemName: paywalled ? "lock.fill"
                  : isRules ? "book"
                  : learned ? "checkmark"
                  : state == .locked ? "lock"
                  : "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(learned ? Theme.foam : Theme.bridge)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

// MARK: - Practice menu

struct PracticeMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        ZStack {
            SeaBackground()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Technique.allCases) { technique in
                        let record = mastery.record(for: technique)
                        let masteryLocked = record.state == .locked
                        // Drills are paid wholesale — mastery progress is
                        // itself a paid surface, so a free player sees neither
                        // the counts nor the states.
                        let paywalled = !FeatureGate.isAvailable(.practiceDrills,
                                                                 unlocked: entitlements.isUnlocked)
                        Button {
                            if paywalled {
                                paywall.present(.practiceDrills)
                            } else {
                                path.append(.practice(technique))
                            }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(technique.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    Text(paywalled ? "Included in the full game"
                                                   : progressLine(record))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                Spacer()
                                if paywalled {
                                    Text("Unlock")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.bridge)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Theme.bridgeWash))
                                } else {
                                    Image(systemName: masteryLocked ? "lock" : "chevron.right")
                                        .font(.system(size: Metrics.glyph, weight: .semibold))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                            .opacity(masteryLocked || paywalled ? 0.6 : 1)
                        }
                        .buttonStyle(.hashi)
                        // Mastery only. A paywalled row must stay tappable.
                        .disabled(masteryLocked)
                    }
                }
                .frame(maxWidth: Metrics.column)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Practice")
        .navigationTitleDisplay(.large)
    }

    private func progressLine(_ record: MasteryTracker.Record) -> String {
        switch record.state {
        case .locked: "Finish the earlier lessons to unlock."
        case .learned: "Learned · \(record.drillsCompleted) drills"
        default: "\(record.unaidedUses) of \(MasteryTracker.learnedThreshold) toward Learned"
        }
    }
}

// MARK: - Tutorial

struct TutorialView: View {
    let technique: Technique?
    @Environment(MasteryTracker.self) private var mastery
    @Environment(\.dismiss) private var dismiss

    @State private var engine: TutorialEngine?

    var body: some View {
        ZStack {
            SeaBackground(waves: true)
            if let engine {
                TutorialContent(engine: engine) {
                    if let technique = engine.lesson.technique {
                        mastery.recordLessonCompleted(technique)
                    }
                    dismiss()
                }
            }
        }
        .navigationTitle(TechniqueContent.lessonTitle(for: technique))
        .navigationTitleDisplay(.inline)
        .swipeBackDisabled()
        .onAppear {
            guard engine == nil else { return }
            engine = TutorialEngine(lesson: TutorialPuzzles.lesson(for: technique))
        }
    }
}

private struct TutorialContent: View {
    let engine: TutorialEngine
    let onFinished: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            BoardView(
                game: engine.game,
                highlightedIslands: engine.highlightedIslands,
                highlightedEdges: engine.highlightedEdges,
                onTapIsland: { engine.handleTapIsland($0) },
                onCycleEdge: { engine.handleCycleEdge($0) }
            )
            .frame(maxWidth: Metrics.boardWidth(regularWidth: horizontalSizeClass == .regular),
                   maxHeight: Metrics.boardWidth(regularWidth: horizontalSizeClass == .regular))
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            messageCard
        }
        .onChange(of: engine.finished) { _, finished in
            if finished { onFinished() }
        }
    }

    private var messageCard: some View {
        VStack(spacing: 12) {
            Text(engine.message)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: engine.stepIndex)
            if engine.showsNextButton {
                Button {
                    engine.next()
                } label: {
                    Text(isLastStep ? "Finish" : "Next")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.island)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bridge))
                }
                .buttonStyle(.hashi)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .offset(x: engine.wiggle ? 5 : 0)
        .animation(Motion.reject, value: engine.wiggle)
        .frame(maxWidth: Metrics.column)
    }

    private var isLastStep: Bool {
        if case .celebrate = engine.currentStep { return true }
        return false
    }
}

// MARK: - Practice

struct PracticeView: View {
    let technique: Technique
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(\.dismiss) private var dismiss

    @State private var game: HashiGame?
    @State private var usedHint = false
    @State private var hint: Hint?
    @State private var completed = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let engine = HintEngine()

    private var boardSide: CGFloat {
        Metrics.boardWidth(regularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        ZStack {
            SeaBackground(waves: true)
            if !entitlements.isUnlocked {
                LockedFeatureView(feature: .practiceDrills)
            } else if let game {
                VStack(spacing: 0) {
                    Text(TechniqueContent.summary(for: technique))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    Spacer(minLength: 0)
                    BoardView(
                        game: game,
                        highlightedIslands: Set(hint?.highlightIslands ?? []),
                        highlightedEdges: Set(hint?.highlightEdges ?? []),
                        onTapIsland: { game.tapIsland($0) },
                        onCycleEdge: { cycle($0, game: game) }
                    )
                    .frame(maxWidth: boardSide, maxHeight: boardSide)
                    .padding(.horizontal, 8)
                    Spacer(minLength: 0)
                }
                .safeAreaInset(edge: .bottom) {
                    if let hint {
                        HintBanner(hint: hint,
                                   onMore: { escalate(game: game) },
                                   onApply: hint.level == .resolution ? { apply(game: game) } : nil,
                                   onDismiss: { self.hint = nil },
                                   onUnlock: { paywall.present(.teachingHints) })
                    }
                }
            }
        }
        .navigationTitle(technique.displayName)
        .navigationTitleDisplay(.inline)
        .swipeBackDisabled()
        .toolbar {
            ToolbarItem(placement: .primaryTrailing) {
                Button {
                    guard let game else { return }
                    usedHint = true
                    hint = engine.hint(for: game, mastery: mastery)
                } label: {
                    Image(systemName: "lightbulb")
                }
                .accessibilityLabel("Hint")
            }
        }
        .task(id: completed) {
            // Guard before generating: a drill search runs the generator with
            // an `accepts:` predicate, and this route is reachable with a stale
            // path after a refund.
            guard entitlements.isUnlocked else { return }
            guard game == nil || completed else { return }
            completed = false
            usedHint = false
            hint = nil
            let seed = UInt64.random(in: 0...UInt64.max)
            let generated = await Task.detached {
                PracticeDrills.drillPuzzle(for: technique, seed: seed)
            }.value
            game = HashiGame(puzzle: generated)
        }
        .onChange(of: game?.phase) { _, phase in
            guard phase == .won else { return }
            mastery.recordDrillCompleted(technique, unaided: !usedHint)
            Haptics.win()
            // Next drill after a beat.
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                completed = true
            }
        }
    }

    private func cycle(_ edge: Int, game: HashiGame) {
        let outcome = game.cycleBridge(edge: edge)
        switch outcome {
        case .drewSingle: Haptics.bridge()
        case .drewDouble: Haptics.bridgeDouble()
        case .cleared: Haptics.clear()
        case .blocked: Haptics.error()
        }
    }

    private func escalate(game: HashiGame) {
        guard let current = hint else { return }
        hint = engine.escalate(current, for: game, mastery: mastery)
    }

    private func apply(game: HashiGame) {
        guard let current = hint else { return }
        game.apply(current.application)
        hint = nil
    }
}

// MARK: - Hint banner

/// Bottom-inset hint UI: the current text, More to climb the ladder, Apply at
/// the resolution level.
struct HintBanner: View {
    let hint: Hint
    let onMore: () -> Void
    var onApply: (() -> Void)?
    let onDismiss: () -> Void
    /// Defaulted so callers that never show a locked hint compile unchanged.
    var onUnlock: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if !hint.isErrorHint && hint.level >= .technique {
                    Text(hint.application.technique.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.bridge)
                        .textCase(.uppercase)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .accessibilityLabel("Dismiss hint")
            }
            Text(hint.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                if hint.isLocked {
                    // A locked hint cannot escalate, so offering "Tell me more"
                    // would be a button that does nothing.
                    bannerButton("Unlock hints", filled: true, action: onUnlock)
                } else {
                    if let onApply {
                        bannerButton("Apply", filled: true, action: onApply)
                    }
                    if hint.level < .resolution {
                        bannerButton("Tell me more", filled: onApply == nil, action: onMore)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: Metrics.column)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func bannerButton(_ title: String, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filled ? Theme.island : Theme.bridge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(filled ? Theme.bridge : Theme.bridgeWash)
                )
        }
        .buttonStyle(.hashi)
    }
}
