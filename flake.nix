{
  outputs =
    { ... }:
    {
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.lid-inhibit;

          extensionUuid = "lid-inhibit@kimhappy";

          extension = pkgs.runCommand "gnome-shell-extension-lid-inhibit"
            {
              meta = {
                description = "GNOME Shell Quick Settings toggle for suspend on lid close";
                homepage = "https://github.com/kimhappy/lid-inhibit";
                license = lib.licenses.mit;
                platforms = lib.platforms.linux;
              };
            }
            ''
              mkdir -p $out/share/gnome-shell/extensions
              cp -r ${./extension} $out/share/gnome-shell/extensions/${extensionUuid}
            '';
        in
        {
          options.services.lid-inhibit.enable = lib.mkEnableOption ''
            lid-inhibit, an on-demand `handle-lid-switch` inhibitor.

            The `lid-inhibit` user service is installed but never started on its own.
            While it runs, logind ignores the lid switch, so closing the lid does not
            suspend even without an external monitor attached.

            On GNOME, a Quick Settings toggle for the service is installed as well. It
            still has to be listed under `enabled-extensions` in the user's
            `org/gnome/shell` dconf, as `${extensionUuid}`
          '';

          config = lib.mkIf cfg.enable {
            environment.systemPackages =
              lib.optional config.services.desktopManager.gnome.enable extension;

            systemd.user.services.lid-inhibit = {
              description = "Prevent suspend on lid close";
              serviceConfig = {
                Type = "exec";
                ExecStart = ''
                  ${config.systemd.package}/bin/systemd-inhibit \
                    --what=handle-lid-switch \
                    --who="Lid Inhibit" \
                    --why="Suspend on lid close disabled" \
                    --mode=block \
                    ${pkgs.coreutils}/bin/sleep infinity
                '';
              };
            };
          };
        };
    };
}
