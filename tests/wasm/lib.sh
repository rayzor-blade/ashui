# Build steps shared by smoke.sh and run.sh. Source it from tests/, with `out`
# set to the work directory (relative to tests/).
#
# ASHUI_WASM_SMALL=1 builds for size, as a site would ship: blinc_abi with fat
# LTO and opt-level z, the programs with LLVM's Oz, and every module's name
# section dropped. It takes a few minutes longer and prints each module's size.

here=$(pwd)
ash=${ASH:-$(command -v "$here/../../ash/target/release/ash" || command -v ash || true)}
[ -x "$ash" ] || { echo "wasm: no ash; set ASH" >&2; exit 1; }
haxe_ui="haxe --class-path ../haxe --class-path ../../hlwindow/haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated --macro ashui.ui.Markup.enable()"

# blinc_abi as a wasm side module, in $out.
build_abi() {
  if [ -n "${ASHUI_WASM_SMALL:-}" ]; then
    export CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_OPT_LEVEL=z CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 ASH_LLVM_PASSES='default<Oz>'
  fi
  mkdir -p "$out"
  sh ../scripts/build_wasm.sh "$out"
}

# Drops each module's name section in $1 and says what is left, when building small.
shrink() {
  [ -n "${ASHUI_WASM_SMALL:-}" ] || return 0
  for module in "$1"/*.wasm; do
    python3 ../scripts/strip_wasm_names.py "$module" "$module.tmp" > /dev/null && mv "$module.tmp" "$module"
    echo "wasm: $(basename "$module") $(wc -c < "$module" | tr -d ' ') bytes, $(brotli -q 9 -c "$module" 2> /dev/null | wc -c | tr -d ' ') brotli"
  done
}

# The state of the repositories the web builds come from: their revisions and what is changed in them. A change is a reason to build again.
web_stamp() {
  for repo in hlwindow hlwgpu xgpu xwindow x-idl; do
    [ -d "$vib/$repo/.git" ] || continue
    echo "$repo $(git -C "$vib/$repo" rev-parse HEAD) $(git -C "$vib/$repo" diff HEAD | shasum | cut -c1-12)"
  done
}

# patches <git url> <checkout>: cargo --config arguments that take every crate of the checkout, its root and crates/*, in place of the
# revision of the repository at <git url>.
patches() {
  for manifest in "$2/Cargo.toml" "$2"/crates/*/Cargo.toml; do
    [ -f "$manifest" ] || continue
    name=$(sed -n 's/^name = "\(.*\)"/\1/p' "$manifest" | head -1)
    [ -n "$name" ] || continue
    echo "--config 'patch.\"$1\".$name.path=\"$(dirname "$manifest")\"'"
  done
}

# web_library <repo> <output directory>: builds <repo>'s web files. hlwindow and hlwgpu pin the revisions of xwindow, xgpu and x-idl they
# build with; where checkouts of those are beside ashui the build uses them instead, from a copy of the library so that its own tree
# is left as it is, and a fix made there is in the page before the pins move.
web_library() {
  if [ -d "$vib/xgpu" ] && [ -d "$vib/x-idl" ] && [ -d "$vib/xwindow" ]; then
    # Outside ashui's tree, which is a Cargo workspace of its own.
    work="$(mktemp -d)/$1"
    mkdir -p "$work" "$here/$out/.shim"
    rsync -a --exclude target --exclude .git "$vib/$1/" "$work/"
    ln -s "$vib/$1/target" "$work/target"
    {
      echo '#!/bin/sh'
      echo 'tc=""'
      echo 'case "$1" in +*) tc="$1"; shift ;; esac'
      echo 'exec "$HOME/.cargo/bin/cargo" $tc \\'
      for dependency in "x-idl https://github.com/rayzor-blade/x-idl.git" "xgpu https://github.com/rayzor-blade/xgpu.git" "xwindow https://github.com/rayzor-blade/xwindow.git"; do
        patches "${dependency#* }" "$vib/${dependency% *}" | sed 's/$/ \\/'
      done
      echo '  "$@"'
    } > "$here/$out/.shim/cargo"
    chmod +x "$here/$out/.shim/cargo"
    built=0
    (cd "$work" && PATH="$here/$out/.shim:$PATH" sh scripts/build_wasm.sh "$2") || built=1
    rm -rf "$(dirname "$work")"
    return $built
  else
    (cd "$vib/$1" && sh scripts/build_wasm.sh "$2")
  fi
}

# The web builds of hlwindow and hlwgpu, from their repositories beside ashui, in $out/hlwindow-web and $out/hlwgpu-web: what their
# release ZIPs carry under web/, and what a build defined wasm stages from them.
web_libraries() {
  vib=$(cd ../.. && pwd)
  if [ ! -f "$vib/hlwindow/scripts/build_wasm.sh" ] || [ ! -f "$vib/hlwgpu/scripts/build_wasm.sh" ]; then
    echo "wasm: a window needs hlwindow and hlwgpu checked out beside ashui"
    return 1
  fi
  stamp=$(web_stamp)
  [ ! -d "$out/hlwindow-web" ] || [ "$(cat "$out/web-libraries.stamp" 2> /dev/null)" != "$stamp" ] || return 0
  rm -rf "$out/hlwindow-web" "$out/hlwgpu-web"
  web_library hlwindow "$here/$out/hlwindow-web" || return 1
  # A new directory each time: hlwgpu's build script writes gpu-agent.mjs only when cargo runs it, and cargo runs it only when this path changes.
  gpu=$(mktemp -d)
  web_library hlwgpu "$gpu" || { rm -rf "$gpu"; return 1; }
  mkdir -p "$out/hlwgpu-web" && cp "$gpu"/* "$out/hlwgpu-web/"
  rm -rf "$gpu"
  [ -f "$out/hlwgpu-web/gpu-agent.mjs" ] || { echo "wasm: hlwgpu's build wrote no gpu-agent.mjs"; return 1; }
  echo "$stamp" > "$out/web-libraries.stamp"
}

# hlavi's web build, in $out/hlavi-web: what its release ZIP carries under web/, and what a build defined wasm stages from it. hlavi
# builds from xavi and x-idl beside it, with no pins to patch.
web_media() {
  vib=$(cd ../.. && pwd)
  [ -f "$vib/hlavi/scripts/build_wasm.sh" ] || { echo "wasm: media needs hlavi checked out beside ashui"; return 1; }
  stamp="$(git -C "$vib/hlavi" rev-parse HEAD) $(git -C "$vib/hlavi" diff HEAD | shasum | cut -c1-12) $(git -C "$vib/xavi" rev-parse HEAD) $(git -C "$vib/xavi" diff HEAD | shasum | cut -c1-12)"
  [ ! -d "$out/hlavi-web" ] || [ "$(cat "$out/hlavi-web.stamp" 2> /dev/null)" != "$stamp" ] || return 0
  rm -rf "$out/hlavi-web"
  (cd "$vib/hlavi" && sh scripts/build_wasm.sh "$here/$out/hlavi-web") || return 1
  echo "$stamp" > "$out/hlavi-web.stamp"
}

# build_window <name> <main class> <class path> [haxe flags]: an ashui window built for a page as an app would be, in $out/<name>:
# the libraries' web builds and ashui's page are staged by their macros, and ash builds the module and its host.
build_window() {
  name=$1; main=$2; path=$3
  shift 3
  web_libraries || return 1
  dir="$out/$name"
  mkdir -p "$dir"
  # NativeInstall copies blinc_abi.wasm from a release package; a checkout has the build.
  cp "$out/blinc_abi.wasm" "$dir/"
  $haxe_ui -D wasm -D ashui_no_hdll -D ashui_window -D "hlwgpu_web=$here/$out/hlwgpu-web" -D "hlwindow_web=$here/$out/hlwindow-web" \
    --macro "ashui.core.render.UiFramework.register()" --macro "ashui.macro.DefaultFonts.stage()" --macro "ashui.macro.WebPage.stage()" \
    --macro "hlwgpu.macro.NativeInstall.stage()" --macro "hlwindow.macro.NativeInstall.stage()" \
    --class-path ../components/haxe --class-path ../icons/haxe --class-path ../canvaskit/haxe --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
    --class-path "$path" "$@" -main "$main" -hl "$dir/$name.hl"
  ASH_WASM_FIBERS=1 "$ash" --build "$dir/$name.wasm" --target wasm32-wasip1-threads "$dir/$name.hl" > "$dir/build.log" 2>&1 || { cat "$dir/build.log"; return 1; }
  shrink "$dir"
}

# WindowPage: a small window that draws and quits.
build_window_page() {
  build_window window-page WindowPage wasm
}

# Banner: the README's dashboard (a glTF car, glass panels, gauges, a street map), its files embedded.
build_banner() {
  scenes=$(cd ../tools/snapshot && pwd)/scenes
  build_window banner Banner "$scenes" -D "ashui_css=$scenes/Banner.css" \
    --macro 'ashui.core.Assets.embed("../tools/snapshot/assets/3d/Mazda6", "../assets/3d/Mazda6")' \
    --macro 'ashui.core.Assets.embed("../tools/snapshot/assets/map", "../assets/map")'
}
