# dotfiles

Configuration managed via [home-manager](https://github.com/nix-community/home-manager) with a bare git repo for dotfiles not owned by home-manager.

## Profiles

| Profile | Flake target | Use case |
|---|---|---|
| personal | `rossrkk@personal` | NixOS + KDE Plasma (Wayland) |
| work | `rosskelso@work` | WSL on Windows |

## Bootstrap: NixOS (personal)

Nix is already present. Clone the repo and check out files, then run home-manager.

```bash
git clone --bare git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dotfiles checkout
dotfiles config status.showUntrackedFiles no
```

> If checkout fails due to conflicts, remove the files it mentions and retry.

Bootstrap home-manager (first time only):

```bash
nix run home-manager -- switch --flake ~/.config/home-manager#rossrkk@personal
```

After that use the `hms` alias. To apply system config changes:

```bash
nrs
```

## Bootstrap: WSL (work)

### 1. Install Nix

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### 2. Clone and check out dotfiles

```bash
git clone --bare git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dotfiles checkout
dotfiles config status.showUntrackedFiles no
```

> `~/.config/nix/nix.conf` will be checked out here, enabling flakes for the next step.

### 3. Bootstrap home-manager

```bash
nix run home-manager -- switch --flake ~/.config/home-manager#rosskelso@work
```

After that use the `hms` alias.

### Fonts

Nerd fonts need to be installed on the Windows side for your terminal emulator. Install **0xProto Nerd Font Propo** from [nerdfonts.com](https://www.nerdfonts.com/font-downloads).

## Usage

```bash
dotfiles status
dotfiles add ~/.config/nvim/lua/plugins/foo.lua
dotfiles commit -m "add foo plugin"
dotfiles push
```
