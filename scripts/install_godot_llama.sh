#!/usr/bin/env bash
# Install godot_llama GDExtension (in-process llama.cpp) into the Godot project.
# On macOS also fetches llama.cpp runtime dylibs (the plugin zip ships the
# framework but not libllama/libggml, which must sit beside it in bin/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/shaders-godot/godot-project"
ADDON="$PROJECT/addons/godot_llama"
BIN="$ADDON/bin"
WRAPPER="$PROJECT/scripts/godot_llama_wrapper.gd"
VERSION="${GODOT_LLAMA_VERSION:-1.0.0}"
LLAMA_CPP_TAG="${LLAMA_CPP_TAG:-b9821}"
ZIP="godot-llama-plugin-all-platforms-${VERSION}.zip"
URL="https://github.com/mgrigajtis/godot_llama/releases/download/${VERSION}/${ZIP}"

LLAMA_DYLIBS=(
	libllama.0.dylib
	libggml.0.dylib
	libggml-base.0.dylib
	libggml-cpu.0.dylib
	libggml-blas.0.dylib
	libggml-metal.0.dylib
	libggml-rpc.0.dylib
	libmtmd.0.dylib
)

already_ok() {
	[[ -f "$ADDON/godot_llama.gdextension" ]] || return 1
	[[ "${GODOT_LLAMA_FORCE:-0}" == "1" ]] && return 1
	if [[ "$(uname -s)" == "Darwin" ]]; then
		[[ -f "$BIN/libllama.0.dylib" && -f "$BIN/libggml-blas.0.dylib" ]]
	else
		return 0
	fi
}

fix_macos_dylib_rpaths() {
	local f dep
	for f in "$BIN"/lib*.0.dylib; do
		[[ -f "$f" ]] || continue
		install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true
		for dep in "${LLAMA_DYLIBS[@]}"; do
			install_name_tool -change "@rpath/$dep" "@loader_path/$dep" "$f" 2>/dev/null || true
		done
	done
	for f in "$BIN"/libgodot_llama.macos.template_*.framework/libgodot_llama.macos.template_*; do
		[[ -f "$f" ]] || continue
		install_name_tool -add_rpath @loader_path/.. "$f" 2>/dev/null || true
		for dep in "${LLAMA_DYLIBS[@]}"; do
			install_name_tool -change "@rpath/$dep" "@loader_path/../$dep" "$f" 2>/dev/null || true
		done
	done
}

if already_ok; then
	echo "godot_llama already installed at $ADDON (set GODOT_LLAMA_FORCE=1 to reinstall)"
	exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading godot_llama ${VERSION}..."
curl -fsSL -o "$tmpdir/$ZIP" "$URL"
mkdir -p "$PROJECT/addons"
unzip -q -o "$tmpdir/$ZIP" -d "$PROJECT"

rm -rf "$ADDON/demo"
cp -f "$WRAPPER" "$ADDON/godot_llama.gd"

if [[ "$(uname -s)" == "Darwin" ]]; then
	arch="arm64"
	if [[ "$(uname -m)" == "x86_64" ]]; then
		arch="x64"
	fi
	llama_tar="llama-${LLAMA_CPP_TAG}-bin-macos-${arch}.tar.gz"
	llama_url="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_CPP_TAG}/${llama_tar}"
	echo "Fetching llama.cpp macOS dylibs (${LLAMA_CPP_TAG}, ${arch})..."
	curl -fsSL -o "$tmpdir/$llama_tar" "$llama_url"
	tar -xzf "$tmpdir/$llama_tar" -C "$tmpdir"
	llama_dir="$(find "$tmpdir" -maxdepth 1 -type d -name 'llama-*' | head -1)"
	if [[ -z "$llama_dir" ]]; then
		echo "ERROR: could not find llama extract dir in $llama_tar" >&2
		exit 1
	fi
	mkdir -p "$BIN"
	cp -f "$llama_dir"/lib*.0.dylib "$BIN/"
	fix_macos_dylib_rpaths
	echo "Installed llama.cpp dylibs into $BIN"
fi

echo "Installed godot_llama to $ADDON"
echo "Guardian voice uses the bundled or downloaded GGUF model (see scripts/fetch_guardian_model.sh)."
