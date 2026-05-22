import AppKit

final class MRUTracker {
    private(set) var order: [pid_t] = []
    private var observer: NSObjectProtocol?

    func start() {
        seedFromCurrent()
        let selfPid = getpid()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            guard app.processIdentifier != selfPid else { return }
            let policy = app.activationPolicy
            guard policy == .regular || policy == .accessory else { return }
            self?.bump(app.processIdentifier)
        }

        let termObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.remove(app.processIdentifier)
        }
        termObservers.append(termObs)
    }

    private var termObservers: [NSObjectProtocol] = []

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for o in termObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    private func seedFromCurrent() {
        let selfPid = getpid()
        let candidates = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != selfPid else { return false }
            return app.activationPolicy == .regular || app.activationPolicy == .accessory
        }
        order = candidates.map { $0.processIdentifier }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != selfPid {
            bump(front)
        }
    }

    func syncFrontmost() {
        let selfPid = getpid()
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              front != selfPid else { return }
        if order.first != front {
            NSLog("[BetterCmdTab] MRU.syncFrontmost: drift detected, front=\(front), was top=\(order.first ?? -1)")
            bump(front)
        }
    }

    private func bump(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
        NSLog("[BetterCmdTab] MRU.bump pid=\(pid) → order head=\(order.prefix(4).map(String.init).joined(separator: ","))")
    }

    private func remove(_ pid: pid_t) {
        order.removeAll { $0 == pid }
    }
}
