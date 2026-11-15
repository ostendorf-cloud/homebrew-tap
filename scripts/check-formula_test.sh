#!/usr/bin/env bash
# Copyright 2026 Simon Ostendorf
# SPDX-License-Identifier: Apache-2.0
# Self test for check-formula.sh. Each case builds a throwaway git repository
# with placeholder formulae and a fake brew that only logs its calls, so this
# runs without Homebrew and never touches the real Formula/ directory.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-formula.sh"
real_git="$(command -v git)"
# An explicit template, because macOS mktemp ignores TMPDIR without one.
work="$(mktemp -d "${TMPDIR:-/tmp}/check-formula-test.XXXXXXXX")"
trap 'rm -rf "${work}"' EXIT

# Commit identity for the throwaway repositories only.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

fake_bin="${work}/bin"
git_shim="${work}/git-shim"
mkdir -p "${fake_bin}" "${git_shim}"
# FAKE_BREW_FAIL names a subcommand that fails for the formula "aaa-bad".
# FAKE_BREW_TAPS is what "brew tap" lists.
cat <<'FAKE' >"${fake_bin}/brew"
#!/usr/bin/env bash
if [ "$1" = "tap" ] && [ $# -eq 1 ]; then
  printf '%s' "${FAKE_BREW_TAPS:-}"
  exit 0
fi
echo "brew $*" >>"${FAKE_BREW_LOG}"
case "$*" in
*/aaa-bad) [ "$1" = "${FAKE_BREW_FAIL:-}" ] && exit 1 ;;
esac
exit 0
FAKE
# A git that fails for the subcommand named in FAKE_GIT_FAIL.
cat <<FAKE >"${git_shim}/git"
#!/usr/bin/env bash
if [ "\$1" = "\${FAKE_GIT_FAIL:-}" ]; then
  echo "fake git: \$1 failed" >&2
  exit 1
fi
exec "${real_git}" "\$@"
FAKE
chmod +x "${fake_bin}/brew" "${git_shim}/git"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

repo=""
commit() { # commit <message>
  git add -A && git commit -q --allow-empty -m "$1" && git rev-parse HEAD
}
new_repo() {
  repo="${work}/repo-$1"
  mkdir -p "${repo}"
  cd "${repo}"
  git init -q -b main
}
formula() { # formula <name>
  mkdir -p Formula
  printf 'class X < Formula\n  # %s\nend\n' "$RANDOM" >"Formula/$1.rb"
}

# expect <case> <expected output> <command...>
expect() {
  local name="$1" want="$2" got
  shift 2
  got="$("$@" 2>&1)" || {
    fail "${name}: exit $? with: ${got}"
    return
  }
  [[ "${got}" == "${want}" ]] || fail "${name}: want '${want}', got '${got}'"
}

# expect_exit <case> <exit code> <command...>: the command fails with that code.
expect_exit() {
  local name="$1" want="$2" code=0
  shift 2
  "$@" >/dev/null 2>&1 || code=$?
  [[ "${code}" -eq "${want}" ]] || fail "${name}: want exit ${want}, got ${code}"
}

# No Formula/ directory yet: clean skip.
new_repo nodir
echo hi >README.md
head="$(commit one)"
expect "no Formula dir" "" "${script}" changed "" "${head}"

# First push that creates Formula/: base is all zeros, everything is checked.
formula alpha
formula beta
head="$(commit two)"
expect "all zero base" $'alpha\nbeta' "${script}" changed 0000000000000000000000000000000000000000 "${head}"
expect "empty base" $'alpha\nbeta' "${script}" changed "" "${head}"

# Only a non formula file changes.
base="${head}"
echo more >>README.md
head="$(commit three)"
expect "no formula change" "" "${script}" changed "${base}" "${head}"

# One formula modified, one added, one deleted, one non rb file added.
base="${head}"
formula alpha
formula gamma
git rm -q Formula/beta.rb
echo x >Formula/notes.txt
head="$(commit four)"
expect "modified, added, deleted" $'alpha\ngamma' "${script}" changed "${base}" "${head}"

# Rename counts as the new name only.
base="${head}"
git mv Formula/gamma.rb Formula/delta.rb
head="$(commit five)"
expect "rename" "delta" "${script}" changed "${base}" "${head}"

# Force push: the old tip is not an ancestor of the new head.
old_tip="${head}"
git reset -q --hard "${base}"
formula epsilon
head="$(commit six)"
expect "force push" "epsilon" "${script}" changed "${old_tip}" "${head}"

# A base this clone does not know (dropped by a force push): check everything.
expect "unknown base" $'alpha\nepsilon\ngamma' "${script}" changed 1111111111111111111111111111111111111111 "${head}"

# A head that is not a commit is an error, never a skip.
expect_exit "bad head" 2 "${script}" changed "${base}" 2222222222222222222222222222222222222222
expect_exit "bad head, lint" 2 "${script}" lint "${base}" not-a-commit

# A failing git call is an error, never "no formula changed".
expect_exit "git diff fails" 2 env PATH="${git_shim}:${PATH}" FAKE_GIT_FAIL=diff "${script}" changed "${base}" "${head}"
expect_exit "git ls-tree fails" 2 env PATH="${git_shim}:${PATH}" FAKE_GIT_FAIL=ls-tree "${script}" changed "" "${head}"

# A name or path that is not Formula/<name>.rb fails closed, in the diff and in the full listing.
bad_path() { # bad_path <case> <path>
  new_repo "bad-$1"
  echo hi >README.md
  local first
  first="$(commit one)"
  mkdir -p "$(dirname "$2")"
  echo 'class X < Formula; end' >"$2"
  local second
  second="$(commit two)"
  expect_exit "$1 in diff" 2 "${script}" changed "${first}" "${second}"
  expect_exit "$1 in listing" 2 "${script}" changed "" "${second}"
}
bad_path space 'Formula/Bad Name.rb'
bad_path quote 'Formula/we"ird.rb'
bad_path tab $'Formula/ta\tb.rb'
bad_path unicode 'Formula/ünï.rb'
bad_path nested 'Formula/f/x.rb'

# lint and test run the right brew commands per changed formula.
new_repo run
echo hi >README.md
base="$(commit one)"
formula zzz-ok
formula aaa-bad
head="$(commit two)"
real_repo="$(pwd -P)"
export PATH="${fake_bin}:${PATH}"
export FAKE_BREW_LOG="${work}/brew.log"
t=ostendorf-cloud/tap

: >"${FAKE_BREW_LOG}"
"${script}" lint "${base}" "${head}" >/dev/null
want="brew tap ${t} ${real_repo}
brew trust --formula ${t}/aaa-bad
brew audit --strict ${t}/aaa-bad
brew style ${t}/aaa-bad
brew trust --formula ${t}/zzz-ok
brew audit --strict ${t}/zzz-ok
brew style ${t}/zzz-ok
brew untrust --formula ${t}/aaa-bad
brew untrust --formula ${t}/zzz-ok
brew untap --force ${t}"
[[ "$(cat "${FAKE_BREW_LOG}")" == "${want}" ]] || fail "lint calls: $(cat "${FAKE_BREW_LOG}")"

: >"${FAKE_BREW_LOG}"
"${script}" test "${base}" "${head}" >/dev/null
want="brew tap ${t} ${real_repo}
brew trust --formula ${t}/aaa-bad
brew install --build-from-source ${t}/aaa-bad
brew test ${t}/aaa-bad
brew trust --formula ${t}/zzz-ok
brew install --build-from-source ${t}/zzz-ok
brew test ${t}/zzz-ok
brew untrust --formula ${t}/aaa-bad
brew untrust --formula ${t}/zzz-ok
brew untap --force ${t}"
[[ "$(cat "${FAKE_BREW_LOG}")" == "${want}" ]] || fail "test calls: $(cat "${FAKE_BREW_LOG}")"

# A broken formula that sorts first fails the run and the others are still checked.
: >"${FAKE_BREW_LOG}"
out="${work}/out.txt"
sum="${work}/summary.md"
: >"${sum}"
code=0
FAKE_BREW_FAIL=install GITHUB_STEP_SUMMARY="${sum}" "${script}" test "${base}" "${head}" >"${out}" 2>&1 || code=$?
[[ "${code}" -eq 1 ]] || fail "broken install: want exit 1, got ${code}"
grep -q "brew test ${t}/zzz-ok" "${FAKE_BREW_LOG}" || fail "formula after the broken one was skipped"
grep -q "brew test ${t}/aaa-bad" "${FAKE_BREW_LOG}" && fail "brew test ran after a failed install"
grep -q '^::error file=Formula/aaa-bad.rb::' "${out}" || fail "no annotation with the formula path: $(cat "${out}")"
grep -q 'zzz-ok: passed' "${sum}" || fail "summary lacks the passed formula"
grep -q 'aaa-bad: FAILED' "${sum}" || fail "summary lacks the failed formula"
grep -q '^### formula test on' "${sum}" || fail "summary lacks a heading"
[[ "$(tail -n1 "${FAKE_BREW_LOG}")" == "brew untap --force ${t}" ]] || fail "no untap after a failure"

# A formula that cannot be trusted fails the run with a clear annotation and
# is not audited. The other formula is still checked.
: >"${FAKE_BREW_LOG}"
code=0
FAKE_BREW_FAIL=trust "${script}" lint "${base}" "${head}" >"${out}" 2>&1 || code=$?
[[ "${code}" -eq 1 ]] || fail "failed trust: want exit 1, got ${code}"
grep -q '^::error file=Formula/aaa-bad.rb::could not trust' "${out}" || fail "no trust annotation: $(cat "${out}")"
grep -q "brew audit --strict ${t}/aaa-bad" "${FAKE_BREW_LOG}" && fail "audit ran for an untrusted formula"
grep -q "brew audit --strict ${t}/zzz-ok" "${FAKE_BREW_LOG}" || fail "formula after the untrusted one was skipped"

code=0
FAKE_BREW_FAIL=audit "${script}" lint "${base}" "${head}" >/dev/null 2>&1 || code=$?
[[ "${code}" -eq 1 ]] || fail "broken audit: want exit 1, got ${code}"

# A tap of the same name that was there before is never touched.
: >"${FAKE_BREW_LOG}"
expect_exit "existing tap" 2 env FAKE_BREW_TAPS="${t}"$'\n' "${script}" lint "${base}" "${head}"
[[ ! -s "${FAKE_BREW_LOG}" ]] || fail "brew called although the tap existed: $(cat "${FAKE_BREW_LOG}")"

# Nothing changed: brew is never called.
: >"${FAKE_BREW_LOG}"
"${script}" lint "${head}" "${head}" >/dev/null
[[ ! -s "${FAKE_BREW_LOG}" ]] || fail "brew called without a formula change"

if [[ "${failures}" -gt 0 ]]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "check-formula tests passed"
