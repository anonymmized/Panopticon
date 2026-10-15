import AppKit

/// AX calls can wait on another process. Do not put that wait in the UI pulse.
final class BadgePoller {
    private let queue = DispatchQueue(label: "NewMacBar.badges", qos: .utility)
    private var inFlight = false
    private var generation = 0
    func refresh(enabled: Bool, receive: @escaping ([String: String]) -> Void) {
        guard enabled && AX.trusted else {
            generation += 1
            receive([:])
            return
        }
        guard !inFlight else { return }
        inFlight = true
        let token = generation
        queue.async { [weak self] in
            let badges = AX.dockBadges()
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard token == self.generation else { return }
                receive(badges)
            }
        }
    }
    func stop() { generation += 1 }
}
