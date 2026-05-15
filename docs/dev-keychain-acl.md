# Development Keychain ACL

`kobaamd` stores API credentials as generic password items in the macOS Keychain under the service `com.kobaamd.apikeys`. In local development, repeated ad-hoc builds can make macOS treat the rebuilt app as a different code signature and show repeated Keychain access prompts.

Use the development helper to update partition lists for existing kobaamd Keychain items:

```bash
scripts/keychain/configure-dev-acl.sh
scripts/keychain/configure-dev-acl.sh --allow-unsigned-dev-app --apply
```

The first command is a dry run. The second command applies `apple-tool:,apple:,unsigned:` to the matching kobaamd API-key items. `unsigned:` is intentionally opt-in because it is appropriate only for a local development keychain with ad-hoc builds.

The helper never reads or prints API key values. When `--apply` is used, macOS may ask for the login keychain password through the `security` command.

Useful scoped variants:

```bash
scripts/keychain/configure-dev-acl.sh --account openai --allow-unsigned-dev-app --apply
scripts/keychain/configure-dev-acl.sh --service com.kobaamd.apikeys.tests --dry-run
```

Manual verification:

1. Build and bundle the app: `swift build && ./scripts/post-build.sh`.
2. Launch the app and save an API key once.
3. Re-run the helper with `--allow-unsigned-dev-app --apply`.
4. Quit and relaunch kobaamd. The saved key should load without repeated Keychain access prompts.

Do not add this helper to `post-build.sh`; Keychain ACL mutation is a local setup action, not a build artifact step.
