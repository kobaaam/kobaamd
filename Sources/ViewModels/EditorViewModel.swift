import Foundation
import Observation

@Observable
class EditorViewModel {
    var text: String = ""
    var fileURL: URL? = nil
}
