abbr --add dotfiles 'git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

if status is-interactive
    starship init fish | source
    zoxide init --cmd cd fish | source        
    fish_vi_key_bindings
# Commands to run in interactive sessions can go here
end
