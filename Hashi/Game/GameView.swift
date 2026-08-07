import SwiftUI

/// Hosts one game: board, chrome (timer, undo), persistence, and the win
/// moment (connectivity ripple → win card).
struct GameView: View {
    let game: HashiGame
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rippleDistances: [Int: Int]?
    @State private var showWinCard = false
    @State private var wasNewBest = false
    @State private var warningIslands: Set<Int> = []
    @State private var hint: Hint?
    /// Set when the win card should hand off to the paywall on its way out.
    @State private var pendingPaywall: PaidFeature?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let hintEngine = HintEngine()

    private var boardSide: CGFloat {
        Metrics.boardWidth(regularWidth: horizontalSizeClass == .regular)
    }

    /// Free players keep the error check ("something here is wrong"); the
    /// teaching ladder is part of the unlock.
    private var hintPolicy: HintPolicy {
        entitlements.isUnlocked ? .full : .errorsOnly
    }

    /// The weekend Daily hands a free player a large board. The moment they
    /// solve it is the one moment worth making the case.
    private var offersUnlock: Bool {
        FeatureGate.shouldOfferUnlock(afterSolving: boardSize,
                                      wasDaily: game.dailyKey != nil,
                                      unlocked: entitlements.isUnlocked)
    }

    var body: some View {
        ZStack {
            Theme.sea.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                BoardView(
                    game: game,
                    rippleDistances: rippleDistances,
                    highlightedIslands: Set(hint?.highlightIslands ?? []),
                    highlightedEdges: Set(hint?.highlightEdges ?? []),
                    warningIslands: warningIslands,
                    onTapIsland: { game.tapIsland($0) },
                    onCycleEdge: { cycle($0) }
                )
                .frame(maxWidth: boardSide, maxHeight: boardSide)
                .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
        }
        .navigationTitleDisplay(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryTrailing) {
                HStack(spacing: 2) {
                    Button {
                        withAnimation(Motion.overlay) {
                            hint = hintEngine.hint(for: game, mastery: mastery,
                                                   showErrors: progress.settings.showErrors,
                                                   policy: hintPolicy)
                        }
                    } label: {
                        Image(systemName: "lightbulb")
                    }
                    .disabled(game.phase != .playing)
                    .accessibilityLabel("Hint")
                    Button {
                        game.undo()
                        persist()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!game.canUndo || game.phase != .playing)
                    .accessibilityLabel("Undo")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let hint {
                HintBanner(
                    hint: hint,
                    onMore: {
                        withAnimation(Motion.overlay) {
                            self.hint = hintEngine.escalate(hint, for: game, mastery: mastery,
                                                            policy: hintPolicy)
                        }
                    },
                    onApply: hint.level == .resolution && !hint.isErrorHint ? {
                        game.apply(hint.application)
                        withAnimation(Motion.overlay) { self.hint = nil }
                    } : nil,
                    onDismiss: {
                        withAnimation(Motion.overlay) { self.hint = nil }
                    },
                    onUnlock: { paywall.present(.teachingHints) }
                )
            }
        }
        // The save must be written as the player works: board change, scene
        // backgrounding, and disappear. Saving only on phase change silently
        // loses everything — a game started and never paused never changes
        // phase. (Kakuro shipped that bug; both halves are pinned by tests.)
        .onChange(of: game.board) {
            persist()
            updateWarnings()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                game.pause()
                persist()
            } else {
                game.resume()
            }
        }
        .onAppear {
            game.showRemainingCapacity = progress.settings.showRemainingCount
            if progress.settings.autoCompleteForced {
                game.autoCompleteForcedIslands()
            }
        }
        .onDisappear {
            if game.phase != .won { persist() }
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .won { celebrate() }
        }
        .task {
            while !Task.isCancelled {
                game.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // The paywall sheet is rooted on the NavigationStack, so setting its
        // context while the win card is up presents nothing. Dismiss the win
        // card first and hand off on the way out.
        .sheet(isPresented: $showWinCard, onDismiss: {
            if let feature = pendingPaywall {
                pendingPaywall = nil
                paywall.present(feature)
            }
        }) {
            WinView(game: game, isNewBest: wasNewBest,
                    onUnlock: offersUnlock ? {
                        pendingPaywall = .largeBoards
                        showWinCard = false
                    } : nil)
                .mediumSheet()
        }
    }

    private var header: some View {
        HStack {
            Text(TimeFormatting.clock(game.elapsed))
                .font(Theme.numberFont(size: 17))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityLabel("Time \(TimeFormatting.clock(game.elapsed))")
            Spacer()
            // Size first, then difficulty — the same order the Daily card and
            // Stats use. Difficulty is the *requested* band, matching records.
            Text("\(boardSize.label) · \(game.difficultyForRecords.label)")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// The board's size band, derived from its grid — a puzzle carries its
    /// geometry, not a size tag.
    private var boardSize: BoardSize {
        switch game.puzzle.rows {
        case ...7: .small
        case ...10: .medium
        default: .large
        }
    }

    private func cycle(_ edge: Int) {
        let hadHint = hint != nil
        let outcome = game.cycleBridge(edge: edge)
        switch outcome {
        case .drewSingle: Haptics.bridge()
        case .drewDouble: Haptics.bridgeDouble()
        case .cleared: Haptics.clear()
        case .blocked: Haptics.error()
        }
        if outcome != .blocked,
           game.isSatisfied(game.puzzle.edges[edge].a) || game.isSatisfied(game.puzzle.edges[edge].b) {
            Haptics.islandComplete()
        }
        // Mastery: an unaided draw that matches the solver's next deduction
        // chain credits the chain's hardest technique — once per corridor per
        // game (the claim guard stops place/undo/replace farming). A visible
        // hint at any level makes the move aided.
        if outcome == .drewSingle || outcome == .drewDouble,
           !hadHint, game.claimMasteryCredit(edge: edge) {
            mastery.recordBridge(edge: edge, game: game, unaided: true)
        }
    }

    private func updateWarnings() {
        let component = game.satisfiedIsolatedComponent()
        withAnimation(Motion.selection) {
            warningIslands = component.map(Set.init) ?? []
        }
    }

    private func persist() {
        guard game.phase != .won else { return }
        progress.saveGame(game.snapshot)
    }

    /// The win: ripple sweeps the network from the last bridge, then the card.
    private func celebrate() {
        progress.clearSavedGame()
        let time = game.elapsed
        if let day = game.dailyKey {
            progress.recordDailyCompleted(day: day, time: time)
        }
        wasNewBest = progress.recordSolve(size: boardSize,
                                          difficulty: game.difficultyForRecords,
                                          time: time)
        Haptics.win()
        let origin = game.lastMoveIsland ?? 0
        let distances = game.rippleDistances(from: origin)
        rippleDistances = distances
        for hop in 0..<min(3, (distances.values.max() ?? 0) + 1) {
            let delay = Double(hop) * Motion.rippleStagger
            Task {
                try? await Task.sleep(for: .seconds(delay))
                Haptics.ripple()
            }
        }
        let totalHops = Double(distances.values.max() ?? 0)
        let rippleTime = reduceMotion ? 0.2 : totalHops * Motion.rippleStagger + 0.55
        Task {
            try? await Task.sleep(for: .seconds(rippleTime))
            showWinCard = true
        }
    }
}
