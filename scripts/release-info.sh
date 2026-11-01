#!/usr/bin/env bash
# Print the release this checkout would publish, as key=value lines:
#   upstream_tag=v18.14.2
#   fork_tag=v18.14.2-fork.2
# The fork tag is the pinned upstream tag plus scripts' `revision` file. Used by CI and by build.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tag="$(upstream_tag)"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "pinned upstream commit is not a stable release tag (got '$tag')"
revision="$(tr -d '[:space:]' < "$root/revision")"
[[ "$revision" =~ ^[1-9][0-9]*$ ]] || die "revision must be a positive integer"
printf 'upstream_tag=%s\nfork_tag=%s-fork.%s\n' "$tag" "$tag" "$revision"
