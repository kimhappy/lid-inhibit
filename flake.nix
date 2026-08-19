{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      extensionUuid = "lid-inhibit@kimhappy";

      homepage = "https://github.com/kimhappy/lid-inhibit";

      debVersion = "1.0.0";
      debMaintainer = "Hwanhee Kim <hwanhee.kim@laplacian.cc>";

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

          asDescriptionBody =
            text:
            map (line: if line == "" then " ." else " ${line}") (
              lib.splitString "\n" (lib.removeSuffix "\n" text)
            );

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
                lib.concatMapStrings (line: "${line}\n") (
                  [
                    "Package: ${pname}"
                    "Version: ${debVersion}"
                    "Architecture: all"
                    "Maintainer: ${debMaintainer}"
                    "Section: utils"
                    "Priority: optional"
                    "Homepage: ${homepage}"
                    "Depends: ${lib.concatStringsSep ", " depends}"
                    "Description: ${synopsis}"
                  ]
                  ++ asDescriptionBody body
                )
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
            body = ''
              Keep a laptop awake with the lid closed, on demand, even with no external
              monitor attached.

              Closing the lid suspends the machine because logind acts on the lid switch.
              This installs a lid-inhibit user service that does nothing but hold a
              handle-lid-switch inhibitor lock, so logind ignores the lid while it runs.
              The service is never started on its own - start and stop it to toggle:

                systemctl --user start lid-inhibit
                systemctl --user stop lid-inhibit

              For a GNOME Shell Quick Settings toggle, install lid-inhibit-gnome.
            '';
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
            body = ''
              Adds a Lid Close toggle to the GNOME Shell Quick Settings menu. It starts
              and stops the lid-inhibit service and follows its state.

              The extension is installed system-wide but still has to be enabled:

                gnome-extensions enable ${extensionUuid}

              This extension targets GNOME Shell 48 and newer. Older releases can use
              the lid-inhibit service on its own.
            '';
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

          extension = pkgs.runCommand "gnome-shell-extension-lid-inhibit"
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
