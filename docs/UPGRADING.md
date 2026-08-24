# Upgrading PassRelay

## Checking for updates

PassRelay includes an update-availability check, enabled by default since August 2026. If your version predates that, it is recommended to follow the "Reinstalling PassRelay" procedure below to get a completely fresh installation.

When PassRelay is invoked using its hotkey, it occasionally checks whether a newer `v1` revision is available and notifies the user if so. The check is simply done using Git locally to see if the GitHub repository has an update.

The check does **not** fetch, pull, or install anything. Upgrades are performed using one of the methods below.

## Normal upgrade

WezTerm can update installed plugins using its built-in plugin updater:

```lua
wezterm.plugin.update_all()
```

> **Note:** `wezterm.plugin.update_all()` updates **all installed WezTerm plugins**, not just PassRelay.

This can, for example, be run using WezTerm's Debug Overlay Lua REPL. After updating, reload the configuration or restart WezTerm. Some people also have it directly in their config file, which will update all plugins automatically when WezTerm is restarted.

## Reinstalling PassRelay

Another more direct way, is to simply delete PassRelay's local plugin checkout. When you start WezTerm next time, while you still have this configured:

```lua
wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm")
```

WezTerm will install it again.

By default, the PassRelay checkout is located at:

```text
~/.local/share/wezterm/plugins/httpssCssZssZsgithubsDscomsZsdfaerchsZspassrelaysDswezterm
```

Just close WezTerm, delete that entire directory, and start WezTerm again.

If your installation uses a different path, you can find the actual checkout directory from WezTerm's Debug Overlay Lua REPL with:

```lua
wezterm.plugin.list()
```

Find the PassRelay entry and use its `plugin_dir` value.

## Verifying the installed version

You can manually compare your installed PassRelay revision with the current `v1` branch.

From the PassRelay plugin directory:

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/v1
```

The first command prints the revision currently installed. The second prints the revision currently published on the `v1` branch.

If the hashes are identical, you are running the current version.

If they differ, your local checkout is not at the current `v1` revision.

