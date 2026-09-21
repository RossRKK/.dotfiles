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
aether's macOS, the Deck's SteamOS), where chaos.nix isn't in the picture at all.

## Profiles

| Profile  | Flake target       | Use case                     |
| -------- | ------------------ | ----------------------------- |
| personal | `rossrkk@personal` | NixOS + KDE Plasma (Wayland) |
| work     | `rosskelso@work`   | WSL on Windows               |
| aether   | `rossrkk@aether`   | macOS (Apple Silicon)        |
| deck     | `deck@achilles`    | Steam Deck (SteamOS 3.x)     |

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

## Bootstrap: Steam Deck (achilles)

The Deck's user is `deck`, not `rossrkk` — home-manager checks `$USER` against
`home.username` and aborts on a mismatch (`USER is "deck", expected "rossrkk"`),
so it gets its own target, `deck@achilles`, rather than reusing `rossrkk@personal`.

### 1. Set a password for `deck`

SteamOS ships the `deck` account with no password, and the Nix installer needs
`sudo`:

```bash
passwd
```

### 2. Install Nix with the Steam Deck planner

SteamOS's root filesystem is read-only and replaced wholesale by every system
update, so a plain `/nix` would be wiped each time. The
[Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
has a `steam-deck` planner that keeps the store on the (persistent) home
partition and bind-mounts it to `/nix` via a systemd unit, so it survives
updates:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install steam-deck
```

It toggles `steamos-readonly` itself as part of the mount unit — no need to
disable it by hand. Open a new shell afterwards so `/etc/profile.d/nix.sh` is
picked up.

### 3. Clone dotfiles and enable flakes

```bash
git clone https://github.com/RossRKK/.dotfiles.git ~/.dotfiles
mkdir -p ~/.config/nix
ln -s ~/.dotfiles/.config/nix/nix.conf ~/.config/nix/nix.conf
```

The installer already enables flakes system-wide; the symlink is what fixes
`experimental Nix feature 'flakes' is disabled` if Nix got on here some other
way. Until it's in place, pass the features on the command line — both in one
flag, and *before* the subcommand, since `nix run home-manager` needs flakes to
resolve the flakeref in the first place:

```bash
nix --extra-experimental-features 'nix-command flakes' run home-manager -- switch --flake ~/.dotfiles#deck@achilles
```

### 4. Bootstrap home-manager

```bash
nix run home-manager -- switch --flake ~/.dotfiles#deck@achilles
```

`base.nix` pulls a whole toolchain (LSPs, LLVM, rustup, tree-sitter), so the
first switch fetches a few GB into the store — worth checking free space on the
64 GB model first.

SteamOS's stock `~/.bashrc` blocks activation (home-manager won't clobber an
existing file). Move it aside and re-run:

```bash
mv ~/.bashrc ~/.bashrc.backup
```

After that use the `hms` alias.

### 5. SSH key

`base.nix` signs both git and jj commits with `~/.ssh/id_ed25519.pub`, so
commits fail until a key exists. Generate one and add it to GitHub (as both an
authentication *and* a signing key), then switch the remote over to SSH:

```bash
ssh-keygen -t ed25519 -C ross@rosskelso.com
git -C ~/.dotfiles remote set-url origin git@github.com:RossRKK/.dotfiles.git
```

### Shell and terminal

`chsh` is pointless here: `/etc/passwd` and `/etc/shells` live on the rootfs
that updates replace. `hosts/deck.nix` instead has bash `exec` into fish for
interactive top-level shells, and sources Nix's profile script directly so a
post-update shell still finds `~/.nix-profile/bin` even when
`/etc/profile.d/nix.sh` is gone.

Set Konsole's font to **0xProto Nerd Font Propo** (installed by
`hosts/deck.nix`, which turns on `fonts.fontconfig` so SteamOS's fontconfig
sees the nix profile's fonts) or the prompt's glyphs render as boxes.

### What this host deliberately doesn't manage

Desktop mode's Plasma session belongs to SteamOS — the taskbar, the Return to
Gaming Mode launcher, the gamescope-driven layout — and system updates restore
their own version of it. So `hosts/deck.nix` skips `profiles/desktop.nix` and
plasma-manager entirely; it's the CLI environment only.

### After a SteamOS update

The store lives on `/home` and survives, but anything the installer put under
`/etc` may not. If `nix` is on `PATH` (fish is covered by `programs.fish.shellInit`,
see above) but `/nix` is empty, the bind mount didn't come back — re-run the
installer command from step 2, which is idempotent.

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
