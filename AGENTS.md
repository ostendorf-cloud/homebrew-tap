# homebrew-tap

Homebrew formulae for ostendorf-cloud tools. The baseline rules apply and are not repeated here.

## Layout

- `Formula/`: one formula per tool, each written by that tool's own release pipeline through
  goreleaser. Nothing here is authored by hand.
- `scripts/`: `check-formula.sh` finds the changed formulae and runs the Homebrew checks,
  `check-formula_test.sh` is its self test and needs no Homebrew.
- Everything else is the repository's own scaffolding: licence, lint configuration, task runner
  and CI.

## Commands

```sh
task setup           # mise install
task check           # every check, one after another
task --list          # one target per check
```

- `task lint:formula` and `task test:formula` are CI only and not part of `check`: they need
  Homebrew, tap this checkout as `ostendorf-cloud/tap` while they run, and `test:formula` installs
  and executes every formula it checks. Run one deliberately on a machine where that is fine,
  for example `CHECK_BASE=<commit> task lint:formula`. Without `CHECK_BASE` every formula is
  checked. They abort when `ostendorf-cloud/tap` is already tapped.
- One task target per check and one CI job per target. `check` aggregates them and holds no
  command of its own. CI calls the small targets, never `check`.

## Constraints

- A formula is generated. Do not edit one by hand, and do not accept a pull request that does: the
  next release would overwrite it and the fix would be lost. A formula problem is fixed in the
  tool's own `.goreleaser.yaml`.
- A tool publishing here needs write access to this repository, which is why the token or app
  used for it is scoped to this repository alone rather than to the organisation.
- This repository must stay public. Homebrew cannot read a private tap without credentials, so a
  private tap breaks `brew install` for everyone.
- The repository name is fixed by Homebrew: a tap named `ostendorf-cloud/tap` resolves to
  `ostendorf-cloud/homebrew-tap`. Renaming it breaks every existing install.
- The split of checks: the releasing tool (gitcd) checks URLs, hashes and structure of the
  generated formula before it pushes. This repository runs `brew audit --strict`, `brew style`, an
  install from source and `brew test` on every formula a push to `main` or a pull request changes,
  on a macOS and a Linux runner (`.github/workflows/formula.yaml`, `scripts/check-formula.sh`).
  The tap never edits or fixes a formula.
- Formulae arrive by push to `main` from the release pipelines, with no pull request. A red
  formula check therefore means a formula is already published and broken. Do not edit it here.
  The next release overwrites it. Fix the cause in the releasing tool's `.goreleaser.yaml` or
  pipeline and cut a release. A formula that points at release assets can only install once
  those assets are public, so a failure right after a release can also mean the pipeline
  pushed before publishing.
- `brew install --build-from-source` and `brew test` execute the formula, which is Ruby, on the
  runner. This is acceptable only because formulae come from this organisation's own pipelines
  and pull requests from forks run with a read only token and no secrets. The workflow keeps
  `permissions: contents: read`, uses no secret and never uses `pull_request_target`.
- Homebrew refuses to load a formula from a tap that is not trusted, and `brew audit` and
  `brew style` load it. The check therefore runs `brew trust --formula ostendorf-cloud/tap/<name>`
  for each formula it checks and `brew untrust` at the end. This adds no exposure: the tapped
  checkout is this repository at the commit under test, the install job already runs the formula's
  Ruby, and pull requests from forks have a read only token and no secrets.
- A goreleaser generated formula may fail `brew audit --strict` for formula reasons on the first
  real push, for example a missing `test` block. That is expected. The fix belongs in the
  releasing tool, not here.
- A first time contributor's pull request from a fork needs a maintainer to approve its workflow
  run before the checks start.
- Self test fixtures are created by `scripts/check-formula_test.sh` in a temporary repository.
  Never put a placeholder formula under `Formula/`.

## Deviations

- No Go, no application code, so the language conventions do not apply.
- No release tooling of its own. This repository is published to, not released.
