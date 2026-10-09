# CLAUDE.md

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
