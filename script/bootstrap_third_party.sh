#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/ThirdParty"
ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-15.6}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"

OPUS_VERSION="1.3.1"
LIBRESSL_VERSION="3.1.5"
PJSIP_VERSION="2.10"

if [[ "$ARCH" != "arm64" ]]; then
  echo "Telephone's current linker configuration expects arm64 PJSIP libraries; got $ARCH." >&2
  exit 1
fi

OPUS_PREFIX="$THIRD_PARTY_DIR/Opus"
LIBRESSL_PREFIX="$THIRD_PARTY_DIR/LibreSSL"
PJSIP_PREFIX="$THIRD_PARTY_DIR/PJSIP"

if [[ -f "$OPUS_PREFIX/lib/libopus.a" &&
      -f "$LIBRESSL_PREFIX/lib/libssl.a" &&
      -f "$LIBRESSL_PREFIX/lib/libcrypto.a" &&
      -f "$PJSIP_PREFIX/lib/libpjsua-arm-apple-darwin.a" ]]; then
  echo "Third-party libraries are already built."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

COMMON_CFLAGS="-arch arm64 -Os -mmacosx-version-min=$MIN_MACOS"

build_opus() {
  if [[ -f "$OPUS_PREFIX/lib/libopus.a" ]]; then
    return
  fi

  echo "Building Opus $OPUS_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "opus-$OPUS_VERSION.tar.gz"     "https://archive.mozilla.org/pub/opus/opus-$OPUS_VERSION.tar.gz"
  tar xzf "opus-$OPUS_VERSION.tar.gz"
  cd "opus-$OPUS_VERSION"
  ./configure     --prefix="$OPUS_PREFIX"     --disable-shared     CFLAGS="$COMMON_CFLAGS"
  make -j"$JOBS"
  make install
}

build_libressl() {
  if [[ -f "$LIBRESSL_PREFIX/lib/libssl.a" && -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ]]; then
    return
  fi

  echo "Building LibreSSL $LIBRESSL_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "libressl-$LIBRESSL_VERSION.tar.gz"     "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-$LIBRESSL_VERSION.tar.gz"
  tar xzf "libressl-$LIBRESSL_VERSION.tar.gz"
  cd "libressl-$LIBRESSL_VERSION"
  ./configure     --prefix="$LIBRESSL_PREFIX"     --disable-shared     CFLAGS="$COMMON_CFLAGS"
  make -j"$JOBS"
  make install
}

build_pjsip() {
  if [[ -f "$PJSIP_PREFIX/lib/libpjsua-arm-apple-darwin.a" ]]; then
    return
  fi

  echo "Building PJSIP $PJSIP_VERSION"
  cd "$TMP_DIR"
  curl -fsSL --retry 3 -o "pjproject-$PJSIP_VERSION.tar.gz"     "https://codeload.github.com/pjsip/pjproject/tar.gz/$PJSIP_VERSION"
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
EOF

  for patch_file in "$PJSIP_PREFIX"/patches/*.patch; do
    patch -p0 -i "$patch_file"
  done

  ./configure     --prefix="$PJSIP_PREFIX"     --with-opus="$OPUS_PREFIX"     --with-ssl="$LIBRESSL_PREFIX"     --disable-video     --disable-libyuv     --disable-libwebrtc     --host=arm-apple-darwin     CFLAGS="$COMMON_CFLAGS -DNDEBUG"     CXXFLAGS="$COMMON_CFLAGS -DNDEBUG"

  make -j"$JOBS" lib
  make install
}

mkdir -p "$THIRD_PARTY_DIR"
build_opus
build_libressl
build_pjsip

echo "Third-party libraries are ready."
