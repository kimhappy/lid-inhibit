{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      extensionUuid = "lid-inhibit@kimhappy";

      homepage = "https://github.com/kimhappy/lid-inhibit";

      debVersion = "1.0.0";
      debMaintainer = "kimhappy <babtul21@gmail.com>";

      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          mkDeb =
            {
              pname,
              depends,
              synopsis,
              body,
              payload,
            }:
            let
              control = pkgs.writeText "${pname}-control" (
                lib.concatMapStrings (line: "${line}\n") [
                  "Package: ${pname}"
                  "Version: ${debVersion}"
                  "Architecture: all"
                  "Maintainer: ${debMaintainer}"
                  "Section: utils"
                  "Priority: optional"
                  "Homepage: ${homepage}"
                  "Depends: ${lib.concatStringsSep ", " depends}"
                  "Description: ${synopsis}"
                  " ${body}"
                ]
              );
            in
            pkgs.runCommand "${pname}-deb-${debVersion}"
              {
                nativeBuildInputs = [ pkgs.dpkg ];
              }
              ''
                stage=$PWD/stage
                install -dm755 $stage

                ${payload}

                chmod -R u+w $stage
                find $stage -type d -exec chmod 755 {} +
                find $stage -type f -exec chmod 644 {} +

                installedSize=$(du -ks $stage | cut -f1)

                install -dm755 $stage/DEBIAN
                {
                  cat ${control}
                  echo "Installed-Size: $installedSize"
                } > $stage/DEBIAN/control

                mkdir -p $out
                dpkg-deb --build --root-owner-group $stage $out/${pname}_${debVersion}_all.deb
              '';

          debService = mkDeb {
            pname = "lid-inhibit";
            depends = [ "systemd" ];
            synopsis = "on-demand handle-lid-switch inhibitor";
            body = "Installs lid-inhibit user service and GNOME Shell Quick Settings toggle.";
            payload = ''
              install -Dm644 ${./lid-inhibit.service} $stage/usr/lib/systemd/user/lid-inhibit.service
              install -Dm644 ${./LICENSE}             $stage/usr/share/doc/lid-inhibit/copyright
              install -Dm644 ${./README.md}           $stage/usr/share/doc/lid-inhibit/README.md
            '';
          };

          debGnome = mkDeb {
            pname = "lid-inhibit-gnome";
            depends = [
              "lid-inhibit (= ${debVersion})"
              "gnome-shell (>= 48)"
            ];
            synopsis = "GNOME Shell Quick Settings toggle for lid-inhibit";
            body = "Adds a Lid Close toggle to the GNOME Shell Quick Settings menu.";
            payload = ''
              install -dm755 $stage/usr/share/gnome-shell/extensions/${extensionUuid}
              cp -rT ${./extension} $stage/usr/share/gnome-shell/extensions/${extensionUuid}

              install -Dm644 ${./LICENSE} $stage/usr/share/doc/lid-inhibit-gnome/copyright
            '';
          };

          deb = pkgs.symlinkJoin {
            name = "lid-inhibit-debs-${debVersion}";
            paths = [
              debService
              debGnome
            ];
          };
        in
        {
          inherit deb debService debGnome;
          default = deb;
        }
      );

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.lid-inhibit;

          gnomeEnabled = config.services.desktopManager.gnome.enable;

          extension =
            pkgs.runCommand "gnome-shell-extension-lid-inhibit"
              {
                meta = {
                  description = "GNOME Shell Quick Settings toggle for suspend on lid close";
                  inherit homepage;
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
          options.services.lid-inhibit.enable = lib.mkEnableOption "an on-demand `handle-lid-switch` inhibitor with a GNOME Shell Quick Settings toggle";

          config = lib.mkIf cfg.enable {
            environment.systemPackages = lib.optional gnomeEnabled extension;

            programs.dconf = lib.mkIf gnomeEnabled {
              enable = true;
              profiles.user.databases = [
                { settings."org/gnome/shell".enabled-extensions = [ extensionUuid ]; }
              ];
            };

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

      homeModules.default = {
        dconf.settings."org/gnome/shell".enabled-extensions = [ extensionUuid ];
      };
    };
}
