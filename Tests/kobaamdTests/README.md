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
└── Unit/TempWorkspaceTests.swift  TestSupport 自体のユニットテスト
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

CI では `main` への push 時のみ、別 job で上記と同等の実行を行います（`swift-test` job 成功後）。

## テスト実行

### CI（デフォルト: 全件）

`.github/workflows/unit-tests.yml` → `scripts/run-unit-tests.sh` は **フィルタなしで全テスト** を実行します。

```sh
./scripts/run-unit-tests.sh
```

### ローカル高速確認（安定サブセット）

開発中の素早い確認には `--stable-only` を使います。以下の suite 名正規表現にマッチするテストのみ実行します（約 88 件）。

```
E1Terminal|E1AgentStatus|ColorTheme|EnclosedSymbol|CSVParser|BacklinksScanner|AppState
```

```sh
./scripts/run-unit-tests.sh --stable-only
```

このフィルタにマッチする suite の **型名・@Suite 表示名は変更しないこと**。フィルタ内容の変更は `scripts/run-unit-tests.sh` の `STABLE_FILTER` を修正して別 PR で対応してください。

### 全件実行（直接）

```sh
bash scripts/prepare-build.sh && swift test --enable-swift-testing --no-parallel
```