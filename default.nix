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
  version = "0.0.15";

  workspacePaths = [
    "./"
    "./apps/desktop"
    "./apps/server"
    "./apps/web"
    "./packages/contracts"
    "./packages/shared"
    "./scripts"
  ];

  workspaceFilters = lib.concatMapStringsSep " " (
    path: "--filter ${lib.escapeShellArg path}"
  ) workspacePaths;

  canonicalizeNodeModules = builtins.toFile "canonicalize-node-modules.ts" ''
    import { lstat, mkdir, readdir, rm, symlink } from "node:fs/promises";
    import { join, relative } from "node:path";

    type Entry = {
      dir: string;
      version: string;
    };

    const root = process.cwd();
    const bunRoot = join(root, "node_modules/.bun");
    const linkRoot = join(bunRoot, "node_modules");
    const directories = (await readdir(bunRoot)).sort();

    const versions = new Map<string, Entry[]>();

    for (const entry of directories) {
      const full = join(bunRoot, entry);
      if (!(await isDirectory(full))) continue;

      const parsed = parseEntry(entry);
      if (!parsed) continue;

      const list = versions.get(parsed.name) ?? [];
      list.push({ dir: full, version: parsed.version });
      versions.set(parsed.name, list);
    }

    const selections = new Map<string, Entry>();

    for (const [slug, list] of versions) {
      list.sort((a, b) => {
        const aValid = Bun.semver.satisfies(a.version, "x.x.x");
        const bValid = Bun.semver.satisfies(b.version, "x.x.x");
        if (aValid && bValid) return -Bun.semver.order(a.version, b.version);
        if (aValid) return -1;
        if (bValid) return 1;
        return b.version.localeCompare(a.version);
      });

      const first = list[0];
      if (first) selections.set(slug, first);
    }

    await rm(linkRoot, { recursive: true, force: true });
    await mkdir(linkRoot, { recursive: true });

    for (const [slug, entry] of Array.from(selections.entries()).sort((a, b) =>
      a[0].localeCompare(b[0]),
    )) {
      const parts = slug.split("/");
      const leaf = parts.pop();
      if (!leaf) continue;

      const parent = join(linkRoot, ...parts);
      const target = join(entry.dir, "node_modules", slug);
      if (!(await isDirectory(target))) continue;

      await mkdir(parent, { recursive: true });
      const linkPath = join(parent, leaf);
      const relativeTarget = relative(parent, target) || ".";

      await rm(linkPath, { recursive: true, force: true });
      await symlink(relativeTarget, linkPath);
    }

    async function isDirectory(path: string) {
      try {
        return (await lstat(path)).isDirectory();
      } catch {
        return false;
      }
    }

    function parseEntry(label: string) {
      const marker = label.startsWith("@") ? label.indexOf("@", 1) : label.indexOf("@");
      if (marker <= 0) return null;

      const name = label.slice(0, marker).replace(/\+/g, "/");
      const version = label.slice(marker + 1);
      if (!name || !version) return null;

      return { name, version };
    }
  '';

  normalizeBunBinaries = builtins.toFile "normalize-bun-binaries.ts" ''
    import { lstat, mkdir, readdir, rm, symlink } from "node:fs/promises";
    import { join, relative } from "node:path";

    type PackageManifest = {
      name?: string;
      bin?: string | Record<string, string>;
    };

    const root = process.cwd();
    const bunRoot = join(root, "node_modules/.bun");
    const bunEntries = (await readdir(bunRoot)).sort();

    for (const entry of bunEntries) {
      const modulesRoot = join(bunRoot, entry, "node_modules");
      if (!(await exists(modulesRoot))) continue;

      const binRoot = join(modulesRoot, ".bin");
      await rm(binRoot, { recursive: true, force: true });
      await mkdir(binRoot, { recursive: true });

      const packageDirs = await collectPackages(modulesRoot);
      for (const packageDir of packageDirs) {
        const manifest = await readManifest(packageDir);
        if (!manifest?.bin) continue;

        const seen = new Set<string>();
        if (typeof manifest.bin === "string") {
          const fallback = manifest.name ?? packageDir.split("/").pop();
          if (fallback) {
            await linkBinary(binRoot, fallback, packageDir, manifest.bin, seen);
          }
          continue;
        }

        for (const [name, target] of Object.entries(manifest.bin).sort((a, b) =>
          a[0].localeCompare(b[0]),
        )) {
          await linkBinary(binRoot, name, packageDir, target, seen);
        }
      }
    }

    async function collectPackages(modulesRoot: string) {
      const found: string[] = [];

      for (const name of (await readdir(modulesRoot)).sort()) {
        if (name === ".bin" || name === ".bun") continue;

        const full = join(modulesRoot, name);
        if (!(await isDirectory(full))) continue;

        if (!name.startsWith("@")) {
          found.push(full);
          continue;
        }

        for (const child of (await readdir(full)).sort()) {
          const scopedDir = join(full, child);
          if (await isDirectory(scopedDir)) found.push(scopedDir);
        }
      }

      return found.sort();
    }

    async function readManifest(dir: string) {
      const file = Bun.file(join(dir, "package.json"));
      if (!(await file.exists())) return null;
      return (await file.json()) as PackageManifest;
    }

    async function linkBinary(
      binRoot: string,
      name: string,
      packageDir: string,
      target: string,
      seen: Set<string>,
    ) {
      if (!name || !target) return;

      const normalizedName = name.includes("/") ? name.slice(name.lastIndexOf("/") + 1) : name;
      if (seen.has(normalizedName)) return;

      const resolved = join(packageDir, target);
      if (!(await Bun.file(resolved).exists())) return;

      seen.add(normalizedName);
      const destination = join(binRoot, normalizedName);
      const relativeTarget = relative(binRoot, resolved) || ".";

      await rm(destination, { force: true });
      await symlink(relativeTarget, destination);
    }

    async function exists(path: string) {
      try {
        await lstat(path);
        return true;
      } catch {
        return false;
      }
    }

    async function isDirectory(path: string) {
      try {
        return (await lstat(path)).isDirectory();
      } catch {
        return false;
      }
    }
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  inherit version;

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HOPiA8X/FzswKGmOuYKog3YIn5iq5rJ/7kDoGhN11x0=";
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

    outputHash = "sha256-MsnBKob7ASPvrz1fiVVz2s0VxvQOZDcFI9PebJuraOE=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";

    postPatch = ''
      mkdir -p nix
      cp ${canonicalizeNodeModules} nix/canonicalize-node-modules.ts
      cp ${normalizeBunBinaries} nix/normalize-bun-binaries.ts
    '';

    buildPhase = ''
      runHook preBuild

      bun install \
        --cpu="*" \
        --frozen-lockfile \
        ${workspaceFilters} \
        --ignore-scripts \
        --no-progress \
        --os="*"

      bun --bun ./nix/canonicalize-node-modules.ts
      bun --bun ./nix/normalize-bun-binaries.ts

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
    for workspace in \
      apps/desktop \
      apps/server \
      apps/web \
      packages/contracts \
      packages/shared \
      scripts
    do
      chmod -R u+w "$workspace/node_modules"
    done

    patchShebangs \
      node_modules \
      apps/desktop/node_modules \
      apps/server/node_modules \
      apps/web/node_modules \
      packages/contracts/node_modules \
      packages/shared/node_modules \
      scripts/node_modules

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

    mkdir -p "$out/bin" "$out/share/t3code/apps" "$out/share/t3code/packages"

    cp package.json "$out/share/t3code/"
    cp bun.lock "$out/share/t3code/"

    cp -R apps/desktop "$out/share/t3code/apps/"
    cp -R apps/server "$out/share/t3code/apps/"
    cp -R apps/web "$out/share/t3code/apps/"
    cp -R packages/contracts "$out/share/t3code/packages/"
    cp -R packages/shared "$out/share/t3code/packages/"
    cp -R scripts "$out/share/t3code/"
    cp -R node_modules "$out/share/t3code/"

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
