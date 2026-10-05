# Contributing

Shepherdr is an independent macOS dashboard and terminal client for Herdr. Issues and pull requests are welcome.

Use Swift 6 and Xcode 16 or later. Run `swift test` and the Xcode build/test command in [DEVELOPMENT](docs/DEVELOPMENT.md) before opening a pull request. Keep SwiftUI separate from transport and DTOs, preserve unknown-field compatibility, and include regression coverage for protocol or store behavior. Test fixtures must contain synthetic data, not real project paths or SSH profiles.

SwiftTerm supplies the native terminal renderer; keep transport and state independent of it. Avoid additional dependencies without a concrete need. Do not copy Herdr or herdrm implementation code. Describe which supported public API your change uses and how it behaves when a machine is unavailable. Terminal tests must use mocks or a separate disposable Herdr configuration, never a user's active workspaces. Closing a terminal connection must only detach that client, and must never terminate a pane/server. Taking over another client's input must only ever follow an explicit user action.

The project uses the MIT License. Contributions are accepted under that license.
