# dotfiles

Configuration managed via [home-manager](https://github.com/nix-community/home-manager). Clone this repo to `~/.dotfiles` and run home-manager to symlink everything into place.

## Profiles

| Profile | Flake target | Use case |
|---|---|---|
| personal | `rossrkk@personal` | NixOS + KDE Plasma (Wayland) |
| work | `rosskelso@work` | WSL on Windows |

## Bootstrap: NixOS (personal)

```bash
git clone git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
nix run home-manager -- switch --flake ~/.dotfiles/.config/home-manager#rossrkk@personal
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

### 2. Clone dotfiles and enable flakes

```bash
git clone git@github.com:RossRKK/.dotfiles.git ~/.dotfiles
mkdir -p ~/.config/nix
ln -s ~/.dotfiles/.config/nix/nix.conf ~/.config/nix/nix.conf
```

### 3. Bootstrap home-manager

```bash
nix run home-manager -- switch --flake ~/.dotfiles/.config/home-manager#rosskelso@work
```

After that use the `hms` alias.

### Fonts

Nerd fonts need to be installed on the Windows side for your terminal emulator. Install **0xProto Nerd Font Propo** from [nerdfonts.com](https://www.nerdfonts.com/font-downloads).

## Updating packages

Update all flake inputs to pull in newer package versions, then apply:

```bash
nix flake update ~/.dotfiles/.config/home-manager
hms
```

To update a single input only (e.g. `nixpkgs`):

```bash
nix flake update nixpkgs --flake ~/.dotfiles/.config/home-manager
hms
```

Commit the updated `flake.lock` afterwards.

## Usage

Edit any config file directly in `~/.dotfiles` — changes are live immediately. To commit:

```bash
cd ~/.dotfiles
git add .config/nvim/lua/plugins/foo.lua
git commit -m "add foo plugin"
git push
```
