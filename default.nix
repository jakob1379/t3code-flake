{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  electron,
  makeBinaryWrapper,
  nodejs,
  node-gyp,
  pkg-config,
  python3,
  writableTmpDirAsHomeHook,
}:

let
  version = "0.0.17";

  workspaceDirs = [
    "apps/desktop"
    "apps/marketing"
    "apps/server"
    "apps/web"
    "packages/client-runtime"
    "packages/contracts"
    "packages/shared"
    "scripts"
  ];

  workspacePaths = [ "./" ] ++ map (path: "./${path}") workspaceDirs;

  workspaceFilters = lib.concatMapStringsSep " " (
    path: "--filter ${lib.escapeShellArg path}"
  ) workspacePaths;

  workspaceDirsShell = lib.concatMapStringsSep " " lib.escapeShellArg workspaceDirs;

  workspaceNodeModules = map (path: "${path}/node_modules") workspaceDirs;

  workspaceNodeModulesShell = lib.concatMapStringsSep " " lib.escapeShellArg workspaceNodeModules;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  inherit version;

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EbkDGpQSVHopyPWnVvndp9vDoLqXGYd1hF9iy7zYKiQ=";
  };

  bunDeps = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-bun-deps";
    inherit (finalAttrs) version src;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;

    outputHash = "sha256-ipZSGVzbYPWgg3NQB886Dg4YgAd3OE1RoHepckVUm3o=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";

    buildPhase = ''
      runHook preBuild

      bun install \
        --cpu="*" \
        --frozen-lockfile \
        --linker hoisted \
        ${workspaceFilters} \
        --ignore-scripts \
        --no-progress \
        --os="*"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      find . -type d -name node_modules -exec cp -R --parents {} "$out" \;

      runHook postInstall
    '';
  };

  nativeBuildInputs = [
    bun
    makeBinaryWrapper
    nodejs
    node-gyp
    pkg-config
    python3
    writableTmpDirAsHomeHook
  ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  configurePhase = ''
    runHook preConfigure

    cp -R "${finalAttrs.bunDeps}/." .

    chmod -R u+w ./node_modules
    for modules in ${workspaceNodeModulesShell}
    do
      if [ -d "$modules" ]; then
        chmod -R u+w "$modules"
      fi
    done

    patchShebangs node_modules
    for modules in ${workspaceNodeModulesShell}
    do
      if [ -d "$modules" ]; then
        patchShebangs "$modules"
      fi
    done

    mkdir -p "$HOME/.node-gyp/${nodejs.version}"
    echo 11 > "$HOME/.node-gyp/${nodejs.version}/installVersion"
    ln -sf "${nodejs}/include" "$HOME/.node-gyp/${nodejs.version}"

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/node_modules/.bin:$PATH"

    # Bun leaves dependency lifecycle scripts disabled in the fixed-output
    # install. Build only the native node-pty addon needed on Linux instead
    # of invoking the package's full npm rebuild/prepare pipeline.
    (
      cd node_modules/.bun/node-pty@1.1.0/node_modules/node-pty
      export npm_config_nodedir="${nodejs}"
      export npm_config_python="${python3}/bin/python3"
      node scripts/prebuild.js || node-gyp rebuild
      node scripts/post-install.js
    )

    node ./node_modules/turbo/bin/turbo run build --filter=@t3tools/desktop --filter=t3

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/t3code"

    cp package.json "$out/share/t3code/"
    cp bun.lock "$out/share/t3code/"

    cp -R node_modules "$out/share/t3code/"
    for workspace in ${workspaceDirsShell}
    do
      cp -R --parents "$workspace" "$out/share/t3code/"
    done

    makeBinaryWrapper ${nodejs}/bin/node "$out/bin/t3" \
      --add-flags "$out/share/t3code/apps/server/dist/index.mjs" \
      --set NODE_ENV production

    makeBinaryWrapper ${electron}/bin/electron "$out/bin/t3code-desktop" \
      --add-flags "$out/share/t3code/apps/desktop/dist-electron/main.js" \
      --set NODE_ENV production

    runHook postInstall
  '';

  meta = {
    description = "T3 Code CLI, bundled web UI, and desktop shell";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "t3";
    platforms = lib.platforms.linux;
  };
})
