# lid-inhibit

Keep a laptop awake with the lid closed, on demand, even with no external
monitor attached.

Closing the lid suspends the machine because logind acts on the lid switch.
This installs a `lid-inhibit` user service that does nothing but hold a
`handle-lid-switch` inhibitor lock, so logind ignores the lid while it runs.
The service is never started on its own — start and stop it to toggle:

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

## Debian / Ubuntu

Two packages are built. `lid-inhibit` is the service and works anywhere;
`lid-inhibit-gnome` adds the Quick Settings toggle and needs GNOME Shell 48+.

```sh
nix build github:kimhappy/lid-inhibit#deb
sudo apt install ./result/lid-inhibit_1.0.0_all.deb        # Service only
sudo apt install ./result/lid-inhibit-gnome_1.0.0_all.deb  # GNOME Shell 48+
```
