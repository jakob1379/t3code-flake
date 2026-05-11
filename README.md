# t3code-flake

Nix flake for packaging T3 Code.

## Package options

The package exposes optional runtime tooling through `default.nix` arguments.

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

Example overlay override:

```nix
final: prev: {
  t3code = prev.t3code.override {
    enableClaude = true;
    enableJujutsu = true;
    enableAzureDevOps = true;
  };
}
```
