import Foundation
import Observation

@Observable
final class AppViewModel {
    var selectedFileURL: URL? = nil
    var editorText: String = ""
}
