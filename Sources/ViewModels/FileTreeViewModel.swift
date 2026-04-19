import Foundation
import Observation

@Observable
class FileTreeViewModel {
    var rootURL: URL? = nil
    var nodes: [FileNode] = []
}
