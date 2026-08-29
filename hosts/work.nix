{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
  ];

  programs.git.settings.user.email = "ross.kelso@oxionics.com";
  programs.jujutsu.settings.user.email = "ross.kelso@oxionics.com";

  # WSL has no systemd user session ssh-agent, so start one per shell if needed.
  programs.fish.interactiveShellInit = ''
    if test -z "$SSH_AUTH_SOCK"
        eval (ssh-agent -c) > /dev/null
    end
  '';

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.dotfiles#rosskelso@work";
  };

  home.packages = with pkgs; [
    ansible
    poethepoet

    # Infra tooling ("cluster access" set)
    (google-cloud-sdk.withExtraComponents [
      google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    kubectl
    k9s
    atmos
    yq-go
    jq

    # Infra tooling ("infra engineering" set)
    opentofu
    sops
    kubernetes-helm
    kustomize
    kubeconform
    k3d
    go-task
    step-cli
  ];

  home.username = "rosskelso";
  home.homeDirectory = "/home/rosskelso";
  home.stateVersion = "26.05";
}
