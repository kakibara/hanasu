import Foundation

// 要件: REQ-COM-030, REQ-COM-025
// 設計判断: DEC-COM-172
/// llama-server を使う処理の順番を決める。サーバーを使っている処理と、起動を待っている処理を分けて数える
/// （待っている処理を使っている処理と同じに数えると、待つ処理どうしが止まり合うため）。
/// 判断だけを持ち、サーバーの起動・停止は LocalLLMServer が行う
struct LocalLLMGate {
    enum Decision: Equatable {
        /// 動いているサーバーをそのまま使う
        case proceed
        /// そのモデルでサーバーを起動する（違うモデルが動いていれば止めてから）
        case start
        /// 使っている処理が終わるのを待つ
        case wait
    }

    /// サーバーを使っている処理の数（起動中を含む）
    private(set) var active = 0
    /// 起動を待っている処理（来た順）
    private(set) var waiting: [UUID] = []

    var hasWaiting: Bool { !waiting.isEmpty }
    var isIdle: Bool { active == 0 && waiting.isEmpty }

    /// 処理が来たときに並ぶ
    mutating func enqueue(_ ticket: UUID) {
        waiting.append(ticket)
    }

    /// 待つのをやめた（期限・取り消し・失敗）
    mutating func leave(_ ticket: UUID) {
        waiting.removeAll { $0 == ticket }
    }

    /// 並んでいる処理が進むか。serving は使える状態で動いているモデル（起動中なら nil）。
    /// waitsForOtherModel が偽の処理（音声入力）は、違うモデルが使われていても待たずに起動し直す（今までどおり）
    func decision(for ticket: UUID, model: LocalLLMModel, serving: LocalLLMModel?, waitsForOtherModel: Bool) -> Decision {
        if serving == model { return .proceed }
        if !waitsForOtherModel { return .start }
        guard active == 0 else { return .wait }
        // 使っている処理がなければ、いちばん先に並んだ処理から起動する（同じモデルを待つ後ろの処理は、起動のあと proceed で通る）
        return waiting.first == ticket ? .start : .wait
    }

    /// 進むと決まった処理を、並びから使っている処理へ移す
    mutating func admit(_ ticket: UUID) {
        leave(ticket)
        active += 1
    }

    // 設計判断: DEC-COM-110
    /// 音声入力の録音中の先読みが、サーバーを起動し始めた。起動の間だけ使っている処理に数え、終わったら finish
    mutating func beginPrewarm() {
        active += 1
    }

    /// 使い終わった（または起動に失敗した）
    mutating func finish() {
        active = max(0, active - 1)
    }

    /// そのモデルの処理を送ったら待つことになるか（送る前に「ほかの処理が終わるのを待っています」と出すため）
    func wouldWait(for model: LocalLLMModel, serving: LocalLLMModel?, waitsForOtherModel: Bool) -> Bool {
        waitsForOtherModel && serving != model && (active > 0 || hasWaiting)
    }
}
