#!/usr/bin/env bash
# Copyright 2026 Simon Ostendorf
# SPDX-License-Identifier: Apache-2.0
#
# Checks the formulae a push or pull request changed.
#
#   check-formula.sh changed <base> <head>   print the changed formula names
#   check-formula.sh lint    <base> <head>   brew audit --strict and brew style
#   check-formula.sh test    <base> <head>   brew install --build-from-source, brew test
#
# <base> is the commit before the change: the push's "before" on a push, the
# pull request's base sha on a pull request. Empty, all zeros or unknown to
# this clone (a force push dropped it) means every formula is checked. The
# comparison starts at the merge base of <base> and <head>, so a force push
# and a pull request check exactly the commits that are new on <head>.
#
# Only Formula/<name>.rb counts. Deleted files are never checked. A path in
# Formula/ ending in .rb that is nested or has an unexpected name is an
# error, never a silent skip. Any failing git call is an error too. No
# Formula/ directory, or no changed formula, is a clean skip with exit 0.
#
# "lint" and "test" tap this checkout as ostendorf-cloud/tap and untap it at
# the end. "test" EXECUTES the formula, which is Ruby, on this machine. Run it
# only on formulae that come from a trusted source.
set -euo pipefail

tap="ostendorf-cloud/tap"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-formula.XXXXXXXX")"
tapped=""
trusted="" # formula refs trusted by this run, space separated, names never contain a space

cleanup() {
  local ref
  # Trust is stored outside the tap, so untapping is not assumed to drop it.
  for ref in ${trusted}; do
    brew untrust --formula "${ref}" >/dev/null 2>&1 || true
  done
  if [[ -n "${tapped}" ]]; then
    brew untap --force "${tap}" >/dev/null 2>&1 || true
  fi
  rm -rf "${work}"
}
trap cleanup EXIT

die() {
  echo "check-formula: $*" >&2
  exit 2
}

# Writes the candidate paths under Formula/, NUL separated, to the file $3.
# Output is NUL separated so a path with a quote or a tab is never rewritten
# by git.
list_paths() {
  local base="$1" head="$2" out="$3" start
  git cat-file -e "${head}^{commit}" 2>/dev/null || die "head '${head}' is not a commit"
  if [[ -n "${base}" ]] && git cat-file -e "${base}^{commit}" 2>/dev/null &&
    start="$(git merge-base "${base}" "${head}" 2>/dev/null)"; then
    git diff -z --name-only --no-renames --diff-filter=d "${start}" "${head}" -- Formula >"${out}" ||
      die "git diff failed"
  else
    # First push, force push or unrelated history: check everything.
    git ls-tree -r -z --name-only "${head}" -- Formula >"${out}" || die "git ls-tree failed"
  fi
}

# Prints the formula names to check, one per line, sorted. A name outside
# Homebrew's own charset is an error, so nothing odd reaches a brew command.
changed_names() {
  local list="${work}/paths" path name names=""
  list_paths "$1" "$2" "${list}"
  while IFS= read -r -d '' path; do
    case "${path}" in
    Formula/*.rb) ;;
    *) continue ;;
    esac
    [[ "${path}" =~ ^Formula/[^/]+\.rb$ ]] || die "nested formula path '${path}' is not supported"
    [[ -f "${path}" ]] || die "${path} is not in the working tree: check out <head> first"
    name="$(basename "${path}" .rb)"
    [[ "${name}" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || die "unexpected formula name '${name}' in '${path}'"
    names+="${name}"$'\n'
  done <"${list}"
  printf '%s' "${names}" | sort
}

summary() {
  echo "$*"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$*" >>"${GITHUB_STEP_SUMMARY}"
  fi
}

# macOS runners have brew on PATH. Linux runners ship Homebrew under
# /home/linuxbrew/.linuxbrew without putting it on PATH.
find_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    return 0
  fi
  die "brew not found: this check needs Homebrew on the runner"
}

# Taps this checkout, a real clone of the checked out commit, so a pull
# request is checked at its merge commit. Refuses to touch a tap that was
# there before.
tap_checkout() {
  if brew tap | grep -Fxq "${tap}"; then
    die "${tap} is already tapped: untap it first, this check needs its own copy of the checkout"
  fi
  brew tap "${tap}" "$(pwd -P)"
  tapped=1
}

# Runs the check per formula, keeps going after a failure, and fails at
# the end with the list of broken formulae.
run_checks() {
  local mode="$1" base="$2" head="$3" list names=() name failed=() log="${work}/output"
  list="$(changed_names "${base}" "${head}")" || exit 2
  while IFS= read -r name; do
    [[ -n "${name}" ]] && names+=("${name}")
  done <<<"${list}"
  summary "### formula ${mode} on ${RUNNER_OS:-local} (${GITHUB_JOB:-local})"
  if [[ ${#names[@]} -eq 0 ]]; then
    summary "No formula changed, nothing to ${mode}."
    return 0
  fi
  find_brew
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  tap_checkout
  for name in "${names[@]}"; do
    echo "::group::${mode} ${name}"
    # brew audit and brew style refuse to load a formula from an untrusted
    # tap, and a tap is untrusted by default. The narrow form trusts this one
    # formula only. It is the checkout at the commit under test.
    if ! brew trust --formula "${tap}/${name}" 2>&1 | tee "${log}"; then
      echo "::endgroup::"
      summary "- ${name}: FAILED"
      echo "::error file=Formula/${name}.rb::could not trust ${tap}/${name}, so ${mode} did not run"
      failed+=("${name}")
      continue
    fi
    trusted+=" ${tap}/${name}"
    if "check_${mode}" "${tap}/${name}" 2>&1 | tee "${log}"; then
      echo "::endgroup::"
      summary "- ${name}: passed"
    else
      echo "::endgroup::"
      echo "Last output of ${name}:"
      tail -n 60 "${log}"
      summary "- ${name}: FAILED"
      echo "::error file=Formula/${name}.rb::${mode} failed for ${name}"
      failed+=("${name}")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    summary "Broken formula: ${failed[*]}. The next release overwrites it, so fix the releasing tool."
    return 1
  fi
}

check_lint() {
  local ref="$1" status=0
  brew audit --strict "${ref}" || status=1
  brew style "${ref}" || status=1
  return "${status}"
}

check_test() {
  local ref="$1"
  brew install --build-from-source "${ref}" && brew test "${ref}"
}

main() {
  local cmd="${1:-}" names
  [[ $# -eq 3 ]] || die "usage: check-formula.sh changed|lint|test <base> <head>"
  cd "$(git rev-parse --show-toplevel)"
  case "${cmd}" in
  changed)
    names="$(changed_names "$2" "$3")" || exit 2
    [[ -z "${names}" ]] || echo "${names}"
    ;;
  lint | test) run_checks "${cmd}" "$2" "$3" ;;
  *) die "unknown command '${cmd}'" ;;
  esac
}

main "$@"
