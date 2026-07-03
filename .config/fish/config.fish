alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

set --export EDITOR nvim

# Render Claude Code to the normal buffer, not the alternate screen, so its
# output stays in tmux scrollback for copy-mode selection.
set --export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN 1

if status is-interactive
    starship init fish | source
    zoxide init --cmd cd fish | source        
    fish_vi_key_bindings
# Commands to run in interactive sessions can go here
end
