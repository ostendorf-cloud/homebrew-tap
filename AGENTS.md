# homebrew-tap

Homebrew formulae for ostendorf-cloud tools. The baseline rules apply and are not repeated here.

## Layout

- `Formula/`: one formula per tool, each written by that tool's own release pipeline through
  goreleaser. Nothing here is authored by hand.
- Everything else is the repository's own scaffolding: licence, lint configuration, task runner
  and CI.

## Commands

```sh
task setup           # mise install
task check           # every check, one after another
task --list          # one target per check
```

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
- The checks here cover this repository's own files. A formula's own correctness is the releasing
  tool's responsibility, tested before it publishes.

## Deviations

- No Go, no application code, so the language conventions do not apply.
- No release tooling of its own. This repository is published to, not released.
