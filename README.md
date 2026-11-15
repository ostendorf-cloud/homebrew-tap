# homebrew-tap

Homebrew formulae for ostendorf-cloud tools.

## Use

```sh
brew tap ostendorf-cloud/tap
brew install gitcd
```

The tap name is `ostendorf-cloud/tap` rather than the repository name: Homebrew maps a tap to a
repository called `homebrew-<name>`, so this repository has to be called `homebrew-tap`.

A formula can also be installed without tapping first:

```sh
brew install ostendorf-cloud/tap/gitcd
```

## What is here

`Formula/` holds one formula per tool. Nothing in it is written by hand: each tool's own release
pipeline publishes its formula here through goreleaser when it cuts a release, so a formula's
content belongs to the repository that produced it.

A pull request changing a formula by hand is therefore the wrong fix. The change belongs in the
tool's `.goreleaser.yaml`, and the next release brings it here.

## Tools

| Formula | Tool |
| --- | --- |
| `gitcd` | [gitcd](https://github.com/ostendorf-cloud/gitcd), clones repositories into a predictable layout and applies a git identity profile per remote |

## Development

```sh
task setup
task --list
task check
```

The checks here cover the repository's own files rather than the formulae: a formula is generated,
and the tool that generates it tests it before publishing.

## License

Apache-2.0. See `LICENSE`.
