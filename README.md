# dotfiles

Configuration managed via
[home-manager](https://github.com/nix-community/home-manager). Clone this repo
to `~/.dotfiles` and run home-manager to symlink everything into place.

## Layout

Two kinds of thing live here, and they follow different rules:

- **App config** (`.config/nvim`, `.config/ghostty`, `.tmux.conf`,
  `.local/bin/…`) keeps the path it has in `$HOME`. home-manager symlinks these
  by explicit path so the shape isn't load-bearing for it — but it means the
  repo can still be checked out as a bare repo over `$HOME`, or stowed, on a
  machine where home-manager isn't an option.
- **The nix config itself** (`flake.nix`, `base.nix`, `hosts/`, `profiles/`)
  sits at the repo root. Nothing symlinks it into place, so there's no `$HOME`
  path for it to mirror — hence `--flake ~/.dotfiles#<target>`.

Anything true of *a machine* rather than *me* — Steam, Discord, printing, the
graphical stack — belongs in [chaos.nix](https://github.com/RossRKK/chaos.nix),
the NixOS system config, not here. Some boilerplate is deliberately duplicated
across the two: this repo has to stand alone on non-NixOS hosts (work's WSL,
aether's macOS), where chaos.nix isn't in the picture at all.

## Profiles

| Profile  | Flake target       | Use case                     |
| -------- | ------------------ | ----------------------------- |
| personal | `rossrkk@personal` | NixOS + KDE Plasma (Wayland) |
| work     | `rosskelso@work`   | WSL on Windows               |
| aether   | `rossrkk@aether`   | macOS (Apple Silicon)        |

## Bootstrap: NixOS (personal)

```bash
git clone git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
nix run home-manager -- switch --flake ~/.dotfiles#rossrkk@personal
```

## Bootstrap: WSL (work)

### 1. Install Nix

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### 2. Clone dotfiles and enable flakes

```bash
git clone git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
mkdir -p ~/.config/nix
ln -s ~/.dotfiles/.config/nix/nix.conf ~/.config/nix/nix.conf
```

### 3. Bootstrap home-manager

```bash
nix run home-manager -- switch --flake ~/.dotfiles#rosskelso@work
```

After that use the `hms` alias.

### Fonts

Nerd fonts need to be installed on the Windows side for your terminal emulator.
Install **0xProto Nerd Font Propo** from
[nerdfonts.com](https://www.nerdfonts.com/font-downloads).

## Bootstrap: macOS (aether)

### 1. Install Nix

Use the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
or the official one:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### 2. Clone dotfiles

```bash
git clone git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
```

### 3. Bootstrap home-manager

```bash
nix run home-manager -- switch --flake ~/.dotfiles#rossrkk@aether
```

After that use the `hms` alias.

The Nix-built fish binary reports an empty `$__fish_sysconfdir`, so it never
scans `/etc/fish/conf.d` — the usual place Nix's per-shell `PATH` setup (which
puts `~/.local/state/nix/profile/bin`, where `home-manager`/`hms` live, on
`PATH`) would be installed by the Nix installer. No machine-level fix needed:
`hosts/aether.nix` sources it directly via `programs.fish.shellInit`, so a
plain `home-manager switch` (step 3 above) is sufficient.

### Set fish as the login shell

`programs.fish.enable` installs and configures fish but doesn't change the
account's default shell — that's a one-time, machine-level step:

```bash
echo /Users/rossrkk/.nix-profile/bin/fish | sudo tee -a /etc/shells
chsh -s /Users/rossrkk/.nix-profile/bin/fish
```

### Pre-existing config

A fresh Mac usually already has a Homebrew-installed shell setup (`~/.gitconfig`,
`~/.zshrc`, etc.) from before it was managed by this repo. Where it conflicts —
e.g. `~/.gitconfig` shadows the home-manager-managed `~/.config/git/config` —
back the old file up (`mv ~/.gitconfig ~/.gitconfig.backup`) so home-manager's
version wins.

## Updating packages

Update all flake inputs to pull in newer package versions, then apply:

```bash
nix flake update --flake ~/.dotfiles
hms
```

To update a single input only (e.g. `nixpkgs`):

```bash
nix flake update nixpkgs --flake ~/.dotfiles
hms
```

Commit the updated `flake.lock` afterwards.

## Usage

Edit any config file directly in `~/.dotfiles` — changes are live immediately.
To commit:

```bash
cd ~/.dotfiles
git add .config/nvim/lua/plugins/foo.lua
git commit -m "add foo plugin"
git push
```
