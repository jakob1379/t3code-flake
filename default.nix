{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  copyDesktopItems,
  electron,
  makeBinaryWrapper,
  makeDesktopItem,
  git,
  jujutsu,
  gh,
  glab,
  azure-cli,
  azure-cli-extensions,
  nodejs,
  node-gyp,
  pkg-config,
  python3,
  writableTmpDirAsHomeHook,
  codex,
  claude-code,
  enableCodex ? true,
  enableClaude ? false,
  enableGit ? true,
  enableJujutsu ? false,
  enableGitHub ? true,
  enableGitLab ? true,
  enableAzureDevOps ? false,
}:

let
  version = "0.0.22";

  desktopItem = makeDesktopItem {
    name = "t3code";
    desktopName = "T3 Code";
    exec = "t3code-desktop";
    icon = "t3code";
    terminal = false;
    categories = [
      "Development"
      "Utility"
    ];
  };

  workspaceDirs = [
    "apps/desktop"
    "apps/marketing"
    "apps/server"
    "apps/web"
    "packages/client-runtime"
    "packages/contracts"
    "packages/effect-acp"
    "packages/effect-codex-app-server"
    "packages/shared"
    "packages/ssh"
    "packages/tailscale"
    "scripts"
  ];

  workspacePaths = [ "./" ] ++ map (path: "./${path}") workspaceDirs;

  workspaceFilters = lib.concatMapStringsSep " " (
    path: "--filter ${lib.escapeShellArg path}"
  ) workspacePaths;

  workspaceDirsShell = lib.concatMapStringsSep " " lib.escapeShellArg workspaceDirs;

  workspaceNodeModules = map (path: "${path}/node_modules") workspaceDirs;

  workspaceNodeModulesShell = lib.concatMapStringsSep " " lib.escapeShellArg workspaceNodeModules;

  azureDevOpsPackage = azure-cli.withExtensions [ azure-cli-extensions.azure-devops ];

  agentPackages =
    lib.optionals enableCodex [ codex ]
    ++ lib.optionals enableClaude [ claude-code ];

  sourceControlPackages =
    lib.optionals enableGit [ git ]
    ++ lib.optionals enableJujutsu [ jujutsu ]
    ++ lib.optionals enableGitHub [ gh ]
    ++ lib.optionals enableGitLab [ glab ]
    ++ lib.optionals enableAzureDevOps [ azureDevOpsPackage ];

  runtimePackages = agentPackages ++ sourceControlPackages;

  runtimePathWrapperArgs = lib.optionalString (runtimePackages != [ ]) ''
    \
      --prefix PATH : ${lib.makeBinPath runtimePackages}
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  inherit version;

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZSUmu3FT+wpCLwpUv3yrFWC4EzcVvev9cZQ/FyeLjqI=";
  };

  postPatch = ''
    python3 - <<'PY'
    import json
    from pathlib import Path

    for relative_path in [
        "apps/server/package.json",
        "apps/desktop/package.json",
        "apps/web/package.json",
        "packages/contracts/package.json",
    ]:
        package_json = Path(relative_path)
        data = json.loads(package_json.read_text())
        data["version"] = "${finalAttrs.version}"
        package_json.write_text(json.dumps(data, indent=2) + "\n")
    PY
  '';

  bunDeps = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-bun-deps";
    inherit (finalAttrs) version src;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;

    outputHash = "sha256-q5OJ9f31/KsNwPXxw2lDlOET3rp/3OKGDzyTP2nlq38=";
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
    copyDesktopItems
    makeBinaryWrapper
    nodejs
    node-gyp
    pkg-config
    python3
    writableTmpDirAsHomeHook
  ];

  desktopItems = [ desktopItem ];

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

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/node_modules/.bin:$PATH"

    # Bun leaves dependency lifecycle scripts disabled in the fixed-output
    # install, so build the native node-pty addon explicitly.
    nodePtyDir="$(node -p "require('path').dirname(require.resolve('node-pty/package.json'))")"
    (
      cd "$nodePtyDir"
      export npm_config_nodedir="${nodejs}"
      export npm_config_python="${python3}/bin/python3"
      node-gyp rebuild
    )

    node ./node_modules/turbo/bin/turbo run build --filter=@t3tools/desktop --filter=t3

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/share/icons/hicolor/512x512/apps" \
      "$out/share/pixmaps" \
      "$out/share/t3code"

    cp package.json "$out/share/t3code/"
    cp bun.lock "$out/share/t3code/"

    cp -R node_modules "$out/share/t3code/"
    for workspace in ${workspaceDirsShell}
    do
      cp -R --parents "$workspace" "$out/share/t3code/"
    done

    makeBinaryWrapper ${nodejs}/bin/node "$out/bin/t3" \
      --add-flags "$out/share/t3code/apps/server/dist/bin.mjs" \
      --set NODE_ENV production ${runtimePathWrapperArgs}

    makeBinaryWrapper ${electron}/bin/electron "$out/bin/t3code-desktop" \
      --add-flags "$out/share/t3code/apps/desktop" \
      --set NODE_ENV production ${runtimePathWrapperArgs}

    cp apps/desktop/resources/icon.png "$out/share/icons/hicolor/512x512/apps/t3code.png"
    cp apps/desktop/resources/icon.png "$out/share/pixmaps/t3code.png"

    runHook postInstall
  '';

  meta = {
    description = "T3 Code CLI, bundled web UI, and desktop shell";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ "jakob1379" ];
    mainProgram = "t3";
    platforms = lib.platforms.linux;
  };
})
