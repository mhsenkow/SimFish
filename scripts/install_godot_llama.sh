#!/usr/bin/env bash
# Install godot_llama GDExtension (in-process llama.cpp) into the Godot project.
# On macOS the release zip ships the framework only — llama.cpp dylibs must be
# built from godot_llama's pinned submodule (prebuilt llama.cpp releases mismatch
# the plugin ABI and hard-crash at llama_context init).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/shaders-godot/godot-project"
ADDON="$PROJECT/addons/godot_llama"
BIN="$ADDON/bin"
WRAPPER="$PROJECT/scripts/godot_llama_wrapper.gd"
VERSION="${GODOT_LLAMA_VERSION:-1.0.0}"
ZIP="godot-llama-plugin-all-platforms-${VERSION}.zip"
URL="https://github.com/mgrigajtis/godot_llama/releases/download/${VERSION}/${ZIP}"
STAMP="$BIN/.llama_dylibs_commit"

LLAMA_DYLIBS=(
	libllama.0.dylib
	libggml.0.dylib
	libggml-base.0.dylib
	libggml-cpu.0.dylib
	libggml-blas.0.dylib
	libggml-metal.0.dylib
	libmtmd.0.dylib
)

expected_llama_commit() {
	case "$VERSION" in
		1.0.0) echo "2b089c77580d347767f440205103e4da8ec33d89" ;;
		*)
			echo "ERROR: unknown GODOT_LLAMA_VERSION=${VERSION} — add its submodule commit to install_godot_llama.sh" >&2
			exit 1
			;;
	esac
}

already_ok() {
	[[ -f "$ADDON/godot_llama.gdextension" ]] || return 1
	[[ "${GODOT_LLAMA_FORCE:-0}" == "1" ]] && return 1
	if [[ "$(uname -s)" == "Darwin" ]]; then
		[[ -f "$BIN/libllama.0.dylib" && -f "$STAMP" ]] || return 1
		[[ "$(cat "$STAMP")" == "$(expected_llama_commit)" ]]
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

build_macos_llama_dylibs() {
	local want
	want="$(expected_llama_commit)"
	if ! command -v cmake >/dev/null 2>&1; then
		echo "ERROR: cmake required on macOS (brew install cmake)" >&2
		exit 1
	fi
	echo "Building llama.cpp dylibs matched to godot_llama ${VERSION} (${want:0:7})..."
	git clone --depth 1 --branch "${VERSION}" --recurse-submodules \
		"https://github.com/mgrigajtis/godot_llama.git" "$tmpdir/godot_llama"
	local got
	got="$(git -C "$tmpdir/godot_llama/third_party/llama.cpp" rev-parse HEAD)"
	if [[ "$got" != "$want" ]]; then
		echo "WARNING: submodule commit ${got:0:7} != expected ${want:0:7}; update LLAMA_SUBMODULE_COMMIT" >&2
	fi
	cmake -S "$tmpdir/godot_llama/third_party/llama.cpp" \
		-B "$tmpdir/godot_llama/third_party/llama.cpp/build_shared" \
		-DGGML_SHARED=ON -DBUILD_SHARED_LIBS=ON -DGGML_METAL=ON -DGGML_BLAS=ON
	cmake --build "$tmpdir/godot_llama/third_party/llama.cpp/build_shared" \
		--config Release -j"$(sysctl -n hw.ncpu)"
	mkdir -p "$BIN"
	rm -f "$BIN"/libllama*.dylib "$BIN"/libggml*.dylib "$BIN"/libmtmd*.dylib
	local src="$tmpdir/godot_llama/third_party/llama.cpp/build_shared/bin"
	for f in "${LLAMA_DYLIBS[@]}"; do
		cp -f "$src/$f" "$BIN/$f"
	done
	echo "$got" > "$STAMP"
	fix_macos_dylib_rpaths
	echo "Installed matching llama.cpp dylibs into $BIN"
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
	build_macos_llama_dylibs
fi

echo "Installed godot_llama to $ADDON"
echo "Guardian voice uses the bundled or downloaded GGUF model (see scripts/fetch_guardian_model.sh)."
echo "Verify macOS inference: ./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_llama_macos.gd"
