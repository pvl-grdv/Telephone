#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/ThirdParty"
ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-15.6}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"

OPUS_VERSION="1.5.2"
LIBRESSL_VERSION="4.3.2"
PJSIP_VERSION="2.17"

if [[ "$ARCH" != "arm64" ]]; then
  echo "Telephone's current linker configuration expects arm64 PJSIP libraries; got $ARCH." >&2
  exit 1
fi

OPUS_PREFIX="$THIRD_PARTY_DIR/Opus"
LIBRESSL_PREFIX="$THIRD_PARTY_DIR/LibreSSL"
PJSIP_PREFIX="$THIRD_PARTY_DIR/PJSIP"

version_matches() {
  local prefix="$1"
  local expected="$2"
  [[ -f "$prefix/.telephone-version" ]] &&
    [[ "$(<"$prefix/.telephone-version")" == "$expected" ]]
}

reset_prefix() {
  local prefix="$1"
  local expected="$2"
  local preserve_patches="${3:-false}"

  if version_matches "$prefix" "$expected"; then
    return
  fi

  echo "Refreshing $prefix for version $expected"
  if [[ "$preserve_patches" == "true" ]]; then
    mkdir -p "$prefix"
    find "$prefix" -mindepth 1 -maxdepth 1 ! -name patches -exec rm -rf {} +
  else
    rm -rf "$prefix"
    mkdir -p "$prefix"
  fi
}

mark_version() {
  local prefix="$1"
  local version="$2"
  printf '%s\n' "$version" > "$prefix/.telephone-version"
}

all_dependencies_ready() {
  version_matches "$OPUS_PREFIX" "$OPUS_VERSION" &&
    version_matches "$LIBRESSL_PREFIX" "$LIBRESSL_VERSION" &&
    version_matches "$PJSIP_PREFIX" "$PJSIP_VERSION" &&
    [[ -f "$OPUS_PREFIX/lib/libopus.a" ]] &&
    [[ -f "$LIBRESSL_PREFIX/lib/libssl.a" ]] &&
    [[ -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ]] &&
    [[ -f "$PJSIP_PREFIX/lib/libpjsua-arm-apple-darwin.a" ]]
}

if all_dependencies_ready; then
  echo "Third-party libraries are already built at the expected versions."
  exit 0
fi

mkdir -p "$THIRD_PARTY_DIR"
reset_prefix "$OPUS_PREFIX" "$OPUS_VERSION"
reset_prefix "$LIBRESSL_PREFIX" "$LIBRESSL_VERSION"
reset_prefix "$PJSIP_PREFIX" "$PJSIP_VERSION" true

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

COMMON_CFLAGS="-arch arm64 -Os -mmacosx-version-min=$MIN_MACOS"

build_opus() {
  if version_matches "$OPUS_PREFIX" "$OPUS_VERSION" &&
     [[ -f "$OPUS_PREFIX/lib/libopus.a" ]]; then
    return
  fi

  echo "Building Opus $OPUS_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "opus-$OPUS_VERSION.tar.gz" \
    "https://archive.mozilla.org/pub/opus/opus-$OPUS_VERSION.tar.gz"
  tar xzf "opus-$OPUS_VERSION.tar.gz"
  cd "opus-$OPUS_VERSION"
  ./configure \
    --prefix="$OPUS_PREFIX" \
    --disable-shared \
    CFLAGS="$COMMON_CFLAGS"
  make -j"$JOBS"
  make install
  mark_version "$OPUS_PREFIX" "$OPUS_VERSION"
}

build_libressl() {
  if version_matches "$LIBRESSL_PREFIX" "$LIBRESSL_VERSION" &&
     [[ -f "$LIBRESSL_PREFIX/lib/libssl.a" ]] &&
     [[ -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ]]; then
    return
  fi

  echo "Building LibreSSL $LIBRESSL_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "libressl-$LIBRESSL_VERSION.tar.gz" \
    "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-$LIBRESSL_VERSION.tar.gz"
  tar xzf "libressl-$LIBRESSL_VERSION.tar.gz"
  cd "libressl-$LIBRESSL_VERSION"
  ./configure \
    --prefix="$LIBRESSL_PREFIX" \
    --disable-shared \
    CFLAGS="$COMMON_CFLAGS"
  make -j"$JOBS"
  make install
  mark_version "$LIBRESSL_PREFIX" "$LIBRESSL_VERSION"
}

build_pjsip() {
  if version_matches "$PJSIP_PREFIX" "$PJSIP_VERSION" &&
     [[ -f "$PJSIP_PREFIX/lib/libpjsua-arm-apple-darwin.a" ]]; then
    return
  fi

  echo "Building PJSIP $PJSIP_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "pjproject-$PJSIP_VERSION.tar.gz" \
    "https://codeload.github.com/pjsip/pjproject/tar.gz/$PJSIP_VERSION"
  tar xzf "pjproject-$PJSIP_VERSION.tar.gz"
  cd "pjproject-$PJSIP_VERSION"

  cat > pjlib/include/pj/config_site.h <<'EOF'
#define PJSIP_DONT_SWITCH_TO_TCP 1
#define PJSUA_MAX_ACC 32
#define PJMEDIA_RTP_PT_TELEPHONE_EVENTS 101
#define PJ_DNS_MAX_IP_IN_A_REC 32
#define PJ_DNS_SRV_MAX_ADDR 32
#define PJSIP_MAX_RESOLVED_ADDRESSES 32
#define PJ_HAS_IPV6 1

/* Modern PJSIP already contains the dispatch-semaphore implementation.
 * Select it on Darwin instead of carrying Telephone's old source patch.
 */
#define PJ_SEMAPHORE_USE_DISPATCH_SEM 1
EOF

  for patch_file in "$PJSIP_PREFIX"/patches/*.patch; do
    echo "Applying $(basename "$patch_file")"
    patch -p0 -i "$patch_file"
  done

  ./configure \
    --prefix="$PJSIP_PREFIX" \
    --with-opus="$OPUS_PREFIX" \
    --with-ssl="$LIBRESSL_PREFIX" \
    --disable-video \
    --disable-libyuv \
    --disable-libwebrtc \
    --host=arm-apple-darwin \
    CFLAGS="$COMMON_CFLAGS -DNDEBUG" \
    CXXFLAGS="$COMMON_CFLAGS -DNDEBUG"

  make -j"$JOBS" lib
  make install
  mark_version "$PJSIP_PREFIX" "$PJSIP_VERSION"
}

build_opus
build_libressl
build_pjsip

echo "Third-party libraries are ready:"
echo "  Opus $OPUS_VERSION"
echo "  LibreSSL $LIBRESSL_VERSION"
echo "  PJSIP $PJSIP_VERSION"
