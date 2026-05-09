import Foundation
import AppKit
import SwiftUI

@main
struct MCPEntryPoint {
    static func main() async {
        let arguments = CommandLine.arguments

        if arguments.count >= 2, arguments[1] == "mcp" {
            guard arguments.count >= 3 else {
                FileHandle.standardError.write(Data("usage: kobaamd mcp <vault-root>\n".utf8))
                exit(2)
            }

            let vaultRoot = URL(fileURLWithPath: arguments[2]).standardizedFileURL
            await MCPServer(vaultRoot: vaultRoot).run()
            exit(0)
        }

        kobaamdApp.main()
    }
}
