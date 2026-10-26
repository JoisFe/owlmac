#!/usr/bin/env bash
# OwlMac installer
#
#   curl -fsSL https://raw.githubusercontent.com/semiaurum/owlmac/main/install.sh | bash
#
# Run from inside a clone (./install.sh) to build from source instead of downloading.
# Set OWLMAC_REPO=owner/repo to install from a fork.
set -euo pipefail

REPO="${OWLMAC_REPO:-semiaurum/owlmac}"

say() { printf '\033[1;33m🦉 %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "OwlMac은 macOS 전용이에요."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 13 )) || die "macOS 13 (Ventura) 이상이 필요해요. 지금은 $(sw_vers -productVersion)."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

build_from() {
  command -v swiftc >/dev/null || die "소스 빌드에는 Command Line Tools가 필요해요: xcode-select --install"
  say "소스에서 빌드하는 중…"
  "$1/scripts/build.sh" >/dev/null
  app="$1/build/OwlMac.app"
}

here="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
if [[ -n "$here" && -x "$here/scripts/build.sh" ]]; then
  build_from "$here"
else
  say "최신 버전 내려받는 중… ($REPO)"
  if curl -fsSL "https://github.com/$REPO/releases/latest/download/OwlMac.zip" -o "$work/OwlMac.zip"; then
    ditto -x -k "$work/OwlMac.zip" "$work"
    app="$work/OwlMac.app"
  else
    say "릴리스를 찾지 못해서 소스를 받아 빌드할게요."
    git clone --quiet --depth 1 "https://github.com/$REPO.git" "$work/src"
    build_from "$work/src"
  fi
fi

[[ -d "$app" ]] || die "OwlMac.app을 만들지 못했어요."

dest="/Applications"
[[ -w "$dest" ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

if pgrep -x OwlMac >/dev/null; then
  say "실행 중인 OwlMac을 종료할게요."
  pkill -x OwlMac || true
  sleep 1
fi

rm -rf "$dest/OwlMac.app"
ditto "$app" "$dest/OwlMac.app"
xattr -dr com.apple.quarantine "$dest/OwlMac.app" 2>/dev/null || true

open "$dest/OwlMac.app"
say "설치 완료: $dest/OwlMac.app"
cat <<'EOF'

   메뉴바에 부엉이가 나타났어요.
   · 클릭        깨우기 / 재우기
   · 우클릭      메뉴 (시간 정해 깨우기, 자동 감지, 로그인 시 실행 …)

   부엉이 눈이 동그랗게 떠 있으면 맥이 잠들지 않아요.
EOF
