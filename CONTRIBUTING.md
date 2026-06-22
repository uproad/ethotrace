# Contributing

*日本語版は [CONTRIBUTING_JP.md](CONTRIBUTING_JP.md) を参照してください。*

Thank you for your interest in contributing to Ethotrace. This document describes how to
open issues and pull requests, and the conventions we follow.

## Getting started

- Please report bugs and propose features via **Issues**. Including reproduction steps, the
  expected behavior, and the actual behavior is a big help.
- Do **not** report security vulnerabilities through public issues. Use the private channel
  instead (see [`SECURITY.md`](SECURITY.md)).
- For larger changes, please open an issue to discuss the approach before implementing — it
  helps avoid wasted work.

## Development environment

Ruby >= 3.2 is required. The root `Gemfile` bundles every gem in the monorepo.

```bash
bundle install          # Resolve dependencies
bundle exec rake        # spec + RuboCop for all gems (full, CI-equivalent check)
bundle exec rake spec   # Tests only
bundle exec rake rubocop
```

Keep **every commit green (tests + RuboCop) and buildable** so that `git bisect` stays usable.

## Branches and pull requests

- `main` is protected and **cannot be pushed to directly**. All changes land on `main` through
  pull requests.
- External contributors should **fork** the repository, work on a topic branch, and open a PR
  against `main`.
- We merge with **merge commits only** (squash / rebase merges are disabled). This preserves a
  history of meaningful commits, which we treat as a project asset.

## Commit conventions

We treat the commit log as **the narrative a reviewer reads to understand a change**. The full
rules live in [`docs/commit-guidelines.md`](docs/commit-guidelines.md) (written in Japanese);
**please read it before opening a PR**. The key points:

- **1 PR = one unit of functionality, 1 commit = one logical change.** Squashing all the work
  into a single final commit violates the policy; commit as each logical unit is completed.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf` / `ci`). The scope is the
  short gem name (`core` / `rspec` / `mcp` / `rbs`, etc.).
- The subject says *what* changed; the body explains *why*.
- Separate **behavioral changes from refactoring**, **mechanical changes from hand-written
  ones**, and **dependency additions from their use** into distinct commits.
- Include tests in the same commit as the implementation they cover.

## Coding conventions

- Comments are written in Japanese; code itself (identifiers, `it` descriptions, etc.) is in
  English.
- Style is enforced by RuboCop (`bundle exec rake rubocop`).

## License

By contributing, you agree that your contributions will be licensed under the project's
[MIT License](LICENSE).
