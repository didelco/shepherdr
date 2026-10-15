# AGENTS.md

## Check the backlog before starting

Before starting any task, look for an open issue or pull request on `theam/shepherdr` that already covers it:

```sh
gh pr list --repo theam/shepherdr --state open --search "<keywords>"
gh issue list --repo theam/shepherdr --state open --search "<keywords>"
```

Also skim the open pull requests by title: contributors' wording rarely matches yours.

- **A pull request already does it:** review and test it instead of writing a parallel fix. Build on it or suggest changes there.
- **An issue describes it:** reference it in the work (`Fixes #N` in the pull request) so it closes when the work lands.
- **Nothing covers it:** go ahead. Once the work lands, close or update any issue it settles.

This avoids duplicate work and keeps the backlog moving with what actually gets done.

## Keep the documentation current

Every change updates the documentation it affects, in the same commit or pull request. Before you call a change done, search `docs/` and the README for what it touches, such as a feature, setting, shortcut, message, command or Herdr requirement, and fix anything that no longer matches.

- `docs/GUIDE.md` and `docs/visual-guide.html`: what users see and do. The visual guide is in English and Spanish and ships inside the app, so update both languages.
- `docs/HERDR-INTEGRATION.md`: the Herdr commands, versions and behavior Shepherdr relies on.
- `docs/AGENT-TOOLS.md`: the `shepherdr` command, its skill and the letters protocol.
- `docs/DEVELOPMENT.md`: building, testing, dependencies and architecture.
- `docs/RELEASING.md` and `docs/INSTALL.txt`: the release workflow, signing and installation.
- `docs/VERIFICATION.md`: what was validated by hand, and how.
- `README.md`: the features and requirements at a glance.

`docs/RELEASE-NOTES.md` is written when a version is released, not with each change. When a change makes a screenshot in `docs/assets` outdated, regenerate it or say so in the pull request.
