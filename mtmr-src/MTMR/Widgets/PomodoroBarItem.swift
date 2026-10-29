//
//  PomodoroBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 10.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class PomodoroBarItem: CustomButtonTouchBarItem, Widget {
    static let identifier = "com.toxblh.mtmr.pomodoro."
    static let name = "pomodoro"
    static let decoder: ParametersDecoder = { decoder in
        enum CodingKeys: String, CodingKey {
            case workTime
            case restTime
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let workTime = try container.decodeIfPresent(Double.self, forKey: .workTime)
        let restTime = try container.decodeIfPresent(Double.self, forKey: .restTime)

        return (
            item: .pomodoro(workTime: workTime ?? 1500.00, restTime: restTime ?? 300),
            actions: [],
            legacyAction: .none,
            legacyLongAction: .none,
            parameters: [:]
        )
    }

    private enum TimeTypes {
        case work
        case rest
        case none
    }

    typealias TimerState = PomodoroTimerCoordinator.State
    typealias TimerPhase = PomodoroTimerCoordinator.State.Phase
    private static let timerCoordinator = PomodoroTimerCoordinator.shared

    /// Accessed during launch so restored timers complete even when the active
    /// profile currently has no Pomodoro widget.
    static func restoreTimersAtLaunch() { _ = timerCoordinator }

    private let defaultTitle = "Focus"
    private let workTime: TimeInterval
    private let restTime: TimeInterval
    private let persistenceKey: String
    private var subscriptionID: UUID?
    private var typeTime: TimeTypes = .none

    private var timeLeft: Int = 0
    private var timeLeftString: String {
        return String(format: "%.2i:%.2i", timeLeft / 60, timeLeft % 60)
    }

    init(identifier: NSTouchBarItem.Identifier, workTime: TimeInterval, restTime: TimeInterval, persistenceKey: String? = nil) {
        self.workTime = workTime
        self.restTime = restTime
        self.persistenceKey = persistenceKey ?? identifier.rawValue
        super.init(identifier: identifier, title: defaultTitle)
        image = StudioControlStyle.image("pomodoro")
        subscriptionID = Self.timerCoordinator.attach(self, key: self.persistenceKey)
        actions.append(contentsOf: [
            ItemAction(trigger: .singleTap) { [weak self] in self?.startStopWork() },
            ItemAction(trigger: .longTap) { [weak self] in self?.startStopRest() }
        ])
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { if let subscriptionID { Self.timerCoordinator.detach(key: persistenceKey, subscriptionID: subscriptionID) } }

    @objc func startStopWork() {
        typeTime = .work
        startStopTimer()
    }

    @objc func startStopRest() {
        typeTime = .rest
        startStopTimer()
    }

    func startStopTimer() {
        Self.timerCoordinator.stateIsActive(key: persistenceKey) ? reset() : start(beep:true)
    }

    // Used by the lifecycle self-test to exercise cancellation without
    // beeping or waiting for a notification interval to complete.
    func startTimerForLifecycleCheck() {
        typeTime = .work
        Self.timerCoordinator.start(key: persistenceKey, phase: .work, duration: workTime)
        Self.timerCoordinator.stop(key: persistenceKey)
    }

    private func start(beep: Bool) {
        Self.timerCoordinator.start(key: persistenceKey, phase: typeTime == .work ? .work : .rest, duration: typeTime == .work ? workTime : restTime)
        if beep { NSSound.beep() }
    }

    private func reset() {
        Self.timerCoordinator.stop(key: persistenceKey)
    }

    fileprivate func show(_ state: TimerState) {
        typeTime = state.phase == .work ? .work : .rest
        timeLeft = state.remainingSeconds(now: Date())
        title = timeLeftString
    }

    fileprivate func showIdle() { typeTime = .none; title = defaultTitle }

    static func remainingSeconds(deadline: Date, now: Date) -> Int {
        max(0,Int(ceil(deadline.timeIntervalSince(now))))
    }

}

/// Holds active deadlines independently of Touch Bar views. The injected clock
/// and delivery closure let the executable lifecycle checks exercise transitions
/// without waiting or posting operating-system notifications.
final class PomodoroTimerCoordinator {
    struct State: Codable, Equatable {
        enum Phase: String, Codable { case work, rest }
        var phase: Phase
        var deadline: Date
        func remainingSeconds(now: Date) -> Int { max(0, Int(ceil(deadline.timeIntervalSince(now)))) }
        func hasFinished(now: Date) -> Bool { deadline <= now }
    }

    static let shared = PomodoroTimerCoordinator()
    private static let prefix = "MTMR.Pomodoro.state."
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let deliver: (State.Phase) -> Void
    private let drivesRunLoop: Bool
    private var states: [String: State] = [:]
    private struct WeakItem { weak var value: PomodoroBarItem? }
    private var observers: [String: [UUID: WeakItem]] = [:]
    private var timer: DispatchSourceTimer?

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }, drivesRunLoop: Bool = true, deliver: ((State.Phase) -> Void)? = nil) {
        self.defaults = defaults
        self.clock = clock
        self.drivesRunLoop = drivesRunLoop
        self.deliver = deliver ?? { phase in
            let notification = NSUserNotification()
            notification.title = "Pomodoro"
            notification.informativeText = phase == .work ? "it's time to rest your mind!" : "It's time to work!"
            notification.soundName = "Submarine"
            NSUserNotificationCenter.default.deliver(notification)
        }
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.prefix) {
            guard let data = value as? Data,
                  let state = try? JSONDecoder().decode(State.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            states[String(key.dropFirst(Self.prefix.count))] = state
        }
        processDeadlines()
        if !states.isEmpty { ensureTimer() }
    }

    func attach(_ item: PomodoroBarItem, key: String) -> UUID {
        let token = UUID()
        observers[key, default: [:]][token] = WeakItem(value: item)
        if let state = states[key] { item.show(state) } else { item.showIdle() }
        return token
    }
    func detach(key: String, subscriptionID: UUID) { observers[key]?.removeValue(forKey: subscriptionID) }
    func stateIsActive(key: String) -> Bool { states[key] != nil }

    func start(key: String, phase: State.Phase, duration: TimeInterval) {
        let state = State(phase: phase, deadline: clock().addingTimeInterval(duration))
        states[key] = state
        persist(state, key: key)
        notifyViews(key: key, state: state)
        ensureTimer()
    }
    func stop(key: String) {
        states.removeValue(forKey: key)
        defaults.removeObject(forKey: Self.prefix + key)
        notifyIdle(key: key)
        stopTimerIfIdle()
    }

    /// Deterministic transition entry point used by StudioControlChecks.
    func processDeadlines() {
        let now = clock()
        for (key, state) in Array(states) {
            if state.hasFinished(now: now) {
                states.removeValue(forKey: key)
                defaults.removeObject(forKey: Self.prefix + key)
                notifyIdle(key: key)
                deliver(state.phase)
            } else { notifyViews(key: key, state: state) }
        }
        observers = observers.mapValues { $0.filter { $0.value.value != nil } }.filter { !$0.value.isEmpty }
        stopTimerIfIdle()
    }

    private func persist(_ state: State, key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.prefix + key)
    }
    private func notifyViews(key: String, state: State) { observers[key]?.values.forEach { $0.value?.show(state) } }
    private func notifyIdle(key: String) { observers[key]?.values.forEach { $0.value?.showIdle() } }
    private func ensureTimer() {
        guard drivesRunLoop, timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.processDeadlines() }
        timer = source
        source.resume()
    }
    private func stopTimerIfIdle() {
        guard states.isEmpty else { return }
        timer?.cancel()
        timer = nil
    }
}
