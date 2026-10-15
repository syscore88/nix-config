{ pkgs, ... }:

{
  programs.zsh = {
    enable = pkgs.lib.mkForce true;
    enableCompletion = pkgs.lib.mkForce true;
    autosuggestions.enable = pkgs.lib.mkForce true;
    syntaxHighlighting.enable = pkgs.lib.mkForce true;
    enableLsColors = pkgs.lib.mkForce true;
    histSize = 30000;
    ohMyZsh = {
      enable = pkgs.lib.mkForce true;
      plugins = [ "git" "sudo" ];
    };
    promptInit = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
    '';
  };

  fonts.packages = with pkgs; [
    nerd-fonts.meslo-lg
  ];

  users.users."__INSTALL_USER__".shell = pkgs.lib.mkForce pkgs.zsh;
}
