# lid-inhibit

Keep a laptop awake with the lid closed, on demand, even with no external
monitor attached.

Closing the lid suspends the machine because logind acts on the lid switch.
This installs a `lid-inhibit` user service that does nothing but hold a
`handle-lid-switch` inhibitor lock, so logind ignores the lid while it runs.
The service is never started on its own — start and stop it to toggle:

```sh
systemctl --user start lid-inhibit
systemctl --user stop  lid-inhibit
```

On GNOME, a Quick Settings toggle for the service is installed as well. Add
`lid-inhibit@kimhappy` to `enabled-extensions` to turn it on.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lid-inhibit.url = "github:kimhappy/lid-inhibit";
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
