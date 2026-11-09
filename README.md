# lid-inhibit

Keep a laptop awake with the lid closed, even with no external monitor.

The `lid-inhibit` user service holds a `handle-lid-switch` inhibitor lock, so
logind ignores the lid while it runs. It never starts on its own:

```sh
systemctl --user start lid-inhibit
systemctl --user stop lid-inhibit
```

A GNOME Shell extension adds a Quick Settings toggle for it, on GNOME Shell 48
and newer.

## NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    lid-inhibit = {
      url = "github:kimhappy/lid-inhibit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, lid-inhibit, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        lid-inhibit.nixosModules.default
        {
          services.lid-inhibit.enable = true;
        }
      ];
    };
  };
}
```

### Home Manager

Home Manager's own `enabled-extensions` shadows the system-wide default, so
import this module to merge the toggle into its list:

```nix
{
  imports = [ lid-inhibit.homeModules.default ];
}
```

## Debian / Ubuntu

`lid-inhibit` is the service; `lid-inhibit-gnome` adds the toggle and needs
GNOME Shell 48+.

```sh
nix build github:kimhappy/lid-inhibit#deb
sudo apt install ./result/lid-inhibit_1.0.0_all.deb        # Service only
sudo apt install ./result/lid-inhibit-gnome_1.0.0_all.deb  # GNOME Shell 48+
```
