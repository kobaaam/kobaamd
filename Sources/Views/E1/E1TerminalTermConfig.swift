import Foundation

/// E1 PTY の TERM 設定。
///
/// `xterm-kitty` では zsh が kitty keyboard を有効化し raw DEL と不整合で BS 空白化する（H2 実機確認）。
/// `xterm-256color` ではシェル行編集が正常。IME は Ghostty 既定経路に任せる。
enum E1TerminalTermConfig {
    static let shellTermName = "xterm-256color"
}