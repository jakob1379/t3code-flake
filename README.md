# t3code-flake

Nix flake that builds [T3 Code](https://github.com/pingdotgg/t3code) from source for Linux, with the agent and source-control CLIs it drives wrapped onto its `PATH`.

<p align="center">
  <img src=".github/assets/build-flow.svg" width="100%" alt="Diagram of the build: nix run fetches pingdotgg/t3code, runs bun install, rebuilds node-pty with node-gyp and runs turbo build, then wraps the result into bin/t3 with codex, git, gh and glab on PATH by default, while claude-code, jj and azure-cli are opt-in overrides." />
</p>

T3 Code is the open-source control plane for coding agents: it runs agents such as Codex and Claude Code on your machine and gives them one interface. This flake packages a pinned upstream release so you can run it from Nix without installing Node or Bun yourself.

## Try it

```sh
nix run github:jakob1379/t3code-flake                  # CLI and bundled web UI (t3)
nix run github:jakob1379/t3code-flake#t3code-desktop   # adds the Electron desktop shell
```

Supported systems: `x86_64-linux` and `aarch64-linux`.

## Packages

The flake exposes a CLI package by default and a separate desktop package for GUI users:

| Package | Includes | Binary |
| --- | --- | --- |
| `t3code` (default) | CLI and bundled web UI | `t3` |
| `t3code-desktop` | CLI, bundled web UI, and desktop shell | `t3`, `t3code-desktop` |

Desktop support is selected by package, not by detecting the current GUI session. The desktop package also installs a `T3 Code` desktop entry and icon.

## Runtime tools

Each binary is wrapped so the tools below are on its `PATH`. Toggle them with package override arguments.

| Option | Default | Adds |
| --- | --- | --- |
| `enableCodex` | `true` | `codex` |
| `enableClaude` | `false` | `claude-code` |
| `enableGit` | `true` | `git` |
| `enableJujutsu` | `false` | `jujutsu` (`jj`) |
| `enableGitHub` | `true` | `gh` |
| `enableGitLab` | `true` | `glab` |
| `enableAzureDevOps` | `false` | `azure-cli` with the Azure DevOps extension |

Bitbucket support is configured at runtime with `T3CODE_BITBUCKET_EMAIL` and `T3CODE_BITBUCKET_API_TOKEN`; there is no package option for those credentials.

## Install with Home Manager

Add the flake as an input:

```nix
inputs.t3code.url = "github:jakob1379/t3code-flake";
```

CLI package with extra tools:

```nix
home.packages = [
  (inputs.t3code.packages.${pkgs.system}.t3code.override {
    enableClaude = true;
    enableJujutsu = true;
    enableAzureDevOps = true;
  })
];
```

Desktop package:

```nix
home.packages = [
  (inputs.t3code.packages.${pkgs.system}.t3code-desktop.override {
    enableJujutsu = true;
    enableGitLab = true;
  })
];
```

### Overlay

`overlays.default` adds `t3code` and `t3code-desktop` to your package set:

```nix
nixpkgs.overlays = [ inputs.t3code.overlays.default ];
home.packages = [ pkgs.t3code ];
```

## How the build works

1. `fetchFromGitHub` pulls the tagged release of `pingdotgg/t3code` set in `default.nix`.
2. `bun install --frozen-lockfile` runs in a fixed-output derivation, so dependencies are hashed and reproducible.
3. The native `node-pty` addon is rebuilt with `node-gyp`, since Bun skips lifecycle scripts.
4. `turbo run build --filter=t3` builds the server and web UI (plus `@t3tools/desktop` for the desktop package).
5. `makeBinaryWrapper` creates `bin/t3` around Node, and `bin/t3code-desktop` around Electron, with the enabled tools prefixed onto `PATH`.

The `nixpkgs` input is kept current by Dependabot.

## Credits

T3 Code is built by [pingdotgg](https://github.com/pingdotgg/t3code) and released under the MIT license. This repository only packages it for Nix.
