#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd -- "${script_dir}/.." && pwd)"

export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:${HOME}/.nix-profile/bin:${PATH:-}"

cd "$workspace_dir"
exec nix develop "$workspace_dir" --command haskell-language-server-wrapper "$@"
