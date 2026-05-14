# t3code-flake

Nix flake for packaging T3 Code.

## Package options

The flake exposes a CLI package by default and a separate desktop package for GUI users:

| Package | Includes |
| --- | --- |
| `t3code` | CLI and bundled web UI |
| `t3code-desktop` | CLI, bundled web UI, and desktop shell |

Optional runtime tooling is exposed through package override arguments.

| Option | Default | Adds |
| --- | --- | --- |
| `enableCodex` | `true` | `codex` |
| `enableClaude` | `false` | `claude-code` |
| `enableGit` | `true` | `git` |
| `enableJujutsu` | `false` | `jujutsu` (`jj`) |
| `enableGitHub` | `true` | `gh` |
| `enableGitLab` | `true` | `glab` |
| `enableAzureDevOps` | `false` | `azure-cli` with the Azure DevOps extension |

Bitbucket support is configured at runtime with `T3CODE_BITBUCKET_EMAIL` and `T3CODE_BITBUCKET_API_TOKEN`; there is no package option for those credentials. Desktop support is selected by package, not by detecting the current GUI session.

Home Manager example:

```nix
home.packages = [
  (inputs.t3code.packages.${pkgs.system}.t3code.override {
    enableClaude = true;
    enableJujutsu = true;
    enableAzureDevOps = true;
  })
];
```

Desktop package example:

```nix
home.packages = [
  (inputs.t3code.packages.${pkgs.system}.t3code-desktop.override {
    enableJujutsu = true;
    enableGitLab = true;
  })
];
```
