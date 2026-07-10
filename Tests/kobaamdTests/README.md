# kobaamd Tests

すべてのテストは Swift Testing (`@Suite` + `#expect`) で記述されています。XCTest は使用していません。

## ディレクトリ構成

```
Tests/kobaamdTests/
├── TestSupport/          共有ヘルパー（ファイル生成・非同期ポーリング）
│   ├── TempWorkspace.swift
│   └── AsyncPolling.swift
├── Unit/                 純粋ロジック（AppKit・ファイルI/O 不要）
├── Integration/          ファイルI/O を伴うサービス層テスト
├── ViewModel/            @Observable / @MainActor の ViewModel テスト
├── AppKitUI/             AppKit import または @MainActor 必須のテスト
├── Benchmarks/           ハイライト性能スモークテスト（通常実行は除外）
└── TempWorkspaceTests.swift  TestSupport 自体のユニットテスト
```

## TestSupport の使い方

### TempWorkspace

テスト suite に `let workspace: TempWorkspace` を持たせると、suite が破棄されるときに `deinit` が走り一時ディレクトリを自動削除します。

```swift
@Suite("MyService")
struct MyServiceTests {
    let workspace: TempWorkspace

    init() throws {
        workspace = try TempWorkspace()
    }

    var tmpDir: URL { workspace.root }
}
```

### eventually()

非同期条件が成立するまでポーリングします。タイムアウト（デフォルト 5 秒）で失敗します。

```swift
await eventually { vm.items.count > 0 }
await eventually(timeout: .seconds(2)) { !vm.isSearching }
```

## ベンチマークの実行

`HighlightBenchmarks` は通常のテスト実行から除外されています。実行するには環境変数 `RUN_BENCHMARKS=1` を設定します。

```sh
RUN_BENCHMARKS=1 swift test --filter HighlightBenchmarks
```

## CI フィルタとの関係

`.github/workflows/unit-tests.yml` → `scripts/run-unit-tests.sh` は以下の suite 名正規表現でフィルタしています。

```
E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState
```

このフィルタにマッチする suite の **型名・@Suite 表示名は変更しないこと**。追加フィルタは `scripts/run-unit-tests.sh` を修正して別 PR で対応してください。

## テストの全件実行

```sh
bash scripts/prepare-build.sh && swift test --enable-swift-testing --no-parallel
```
