# dotfiles

## Setup on a new machine

### 1. Clone the repo

```bash
git clone --bare https://github.com/rosskelso/dotfiles.git ~/.dotfiles
```

### 2. Add the alias

**fish** (`~/.config/fish/config.fish`):
```fish
abbr --add dotfiles 'git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

**bash** (`~/.bashrc`):
```bash
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

**zsh** (`~/.zshrc`):
```zsh
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

### 3. Checkout the files

```bash
dotfiles checkout
dotfiles config status.showUntrackedFiles no
```

> If checkout fails due to conflicts, back up or remove the existing files it mentions, then run it again.

## Usage

```bash
dotfiles status
dotfiles add ~/.config/nvim/lua/plugins/foo.lua
dotfiles commit -m "add foo plugin"
dotfiles push
```
