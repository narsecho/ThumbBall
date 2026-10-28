import Foundation

final class ChineseEngine {
    private(set) var ready = false
    var items: [String] { (0..<Int(tb_rime_count())).map { String(cString: tb_rime_candidate(Int32($0))) } }
    var preedit: String { String(cString: tb_rime_preedit()) }
    init(shared: URL, user: URL, deploy: Bool = false) {
        do { try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true) }
        catch { return }
        ready = tb_rime_start(shared.path, user.path, deploy ? 1 : 0) != 0
    }
    func key(_ key: Int32) { if ready { _ = tb_rime_key(key) } }
    func clear() { if ready { tb_rime_clear() } }
    func select(_ index: Int) { if ready { _ = tb_rime_select(Int32(index)) } }
    func page(backward: Bool) -> Bool { ready && tb_rime_page(backward ? 1 : 0) != 0 }
    func takeCommit() -> String { ready ? String(cString: tb_rime_commit()) : "" }
    deinit { if ready { tb_rime_stop() } }
}
