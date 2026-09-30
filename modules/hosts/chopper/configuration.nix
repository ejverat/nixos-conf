{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.chopperConfiguration = {
    config,
    pkgs,
    lib,
    ...
  }: {
    imports = [
      self.nixosModules.chopperHardware
      # Cross-cutting host options (nixosConf.user.name) read by the features.
      self.nixosModules.nixosConf
      self.nixosModules.niri
      self.nixosModules.opencode
      self.nixosModules.zsh
      self.nixosModules.neovim
      self.nixosModules.docker
      self.nixosModules.claude-code
      self.nixosModules.antigravity
      self.nixosModules.ollama
      self.nixosModules.gimp
      self.nixosModules.libreoffice
      self.nixosModules.deepseek-harness
      self.nixosModules.pi
      self.nixosModules.gentle-pi
      self.nixosModules.engram
      # Native OrcaSlicer, on the same pinned 2.4.2 as gear5th so the shared
      # print presets' inherits chains keep resolving against matching system
      # preset names.
      self.nixosModules.orcaslicer
      # Native PrusaSlicer, from the same main nixpkgs pin as gear5th so the two
      # hosts stay on one version and the shared presets keep resolving.
      self.nixosModules.prusaslicer
      self.nixosModules.secrets
      # Mouse and keyboard sharing with gear5th (shared physical input over the
      # LAN). System layer: the package plus the UDP 4242 port lan-mouse listens
      # on; the user layer and the per-host client entry are below.
      self.nixosModules.lan-mouse

      # home-manager as a NixOS module: chopper consumes the same shared
      # flake.homeModules.* as gear5th, so user-level config has one source of
      # truth. System bits (sessions, /etc, setuid wrappers, sops) stay here.
      inputs.home-manager.nixosModules.home-manager
    ];

    # Single source for the desktop user: the feature modules derive the home
    # directory and file ownership from this, and the account below is keyed by
    # it. See modules/options.nix.
    nixosConf.user.name = "ejverat";

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # Move a real file aside instead of aborting activation when it sits on a
      # managed path (the standalone host learned this the hard way; see
      # scripts/bootstrap-gear5th.sh). As a NixOS module this option exists,
      # unlike in home-manager standalone.
      backupFileExtension = "bak";
      # The shared home modules resolve packages through the flake itself.
      extraSpecialArgs = {
        flakeSelf = self;
        flakeInputs = inputs;
      };
      users.${config.nixosConf.user.name} = {
        imports = [
          # Phase 2, slice 2 (user-level packages and the vendored dotfiles).
          self.homeModules.dotfiles
          self.homeModules.gh
          self.homeModules.hyprpicker
          self.homeModules.kanshi
          # Shared mouse/keyboard with gear5th. Same module gear5th imports, so
          # the pairing has one source of truth; the per-host side is the
          # nixosConf.lan-mouse.config value below.
          self.homeModules.lan-mouse
          self.homeModules.chromium
          self.homeModules.google-chrome
          self.homeModules.slack
          self.homeModules.teams
          self.homeModules.wezterm
          self.homeModules.tmux
          # Phase 2, slice 4: shared plugin/rc wiring; chopper installs its own
          # wrapper flavor (secrets-aware myZsh) below.
          self.homeModules.zsh
          # GTK theme, so OrcaSlicer and the other GTK apps resolve a real theme
          # instead of silently falling back to Adwaita light. NixOS already
          # puts the user profile's share dir in XDG_DATA_DIRS, so unlike
          # gear5th this needs no targets.genericLinux equivalent.
          # NOTE: the module writes ~/.config/gtk-3.0/settings.ini with
          # `force`, so a hand-written file at that path on chopper is replaced
          # by the managed Nordic theme.
          self.homeModules.gtk
          # Seeds the vendored OrcaSlicer print presets into the app's writable
          # data dir, only when missing, so chopper gets the same printers,
          # filaments and processes as gear5th. Capture or apply later edits with
          # scripts/slicer-presets.sh.
          self.homeModules.orcaslicer-presets
          # Same seed for PrusaSlicer. It has no GTK module of its own here
          # because chopper already imports homeModules.gtk above.
          self.homeModules.prusaslicer-presets
          # Deliberately NOT imported on chopper:
          #   niri      -> programs.niri (system) owns the session + DM wiring
          #   noctalia  -> ~/.config/noctalia/settings.json is runtime state the
          #                user tunes and syncs back with sync-noctalia
          #   pi        -> slice 5 discarded: the ~/.pi settings activation stays
          #                a system activation and the packages gain nothing
        ];

        nixosConf.zsh.wrapper = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;

        # Laptop + dock monitor profiles, consumed by flake.homeModules.kanshi
        # (modules/features/kanshi.nix) and written to ~/.config/kanshi/config.
        nixosConf.kanshi.config = ''
          profile home {
            output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
            output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,1080
          }

          profile docked {
            output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
          }

          profile laptop {
            output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,0
          }
        '';

        # The other side of the KVM pair. chopper sits to the left of gear5th, so
        # gear5th is the peer on the right. This text is seeded into
        # ~/.config/lan-mouse/config.toml only when that file does not exist;
        # afterwards lan-mouse owns the file and persists authorized peer
        # fingerprints there.
        nixosConf.lan-mouse.config = ''
          # Both backends are pinned rather than auto-detected: lan-mouse probes
          # the libei / InputCapture-portal capture backend first, and niri has no
          # EIS server and no InputCapture portal, so only layer-shell + wlroots
          # can succeed on this compositor.
          capture_backend = "layer-shell"
          emulation_backend = "wlroots"
          port = 4242

          [[clients]]
          position = "right"
          hostname = "gear5th.local"
          activate_on_startup = true
          # Fallback for when mDNS does not answer, which is the normal case
          # here: `gear5th.local` only advertises records this host cannot use
          # (an AAAA answer with no A, plus a stale 192.168.1.114 that now
          # belongs to a different device -- nothing listens on 4242 there).
          # 192.168.1.159 is the address the daemon actually handshakes with,
          # and it is a DHCP lease: reserving it on the router is what stops
          # this list from drifting. The peer's fingerprint still has to match
          # before anything is accepted.
          ips = ["192.168.1.159"]
        '';

        home.username = "ejverat";
        home.homeDirectory = "/home/ejverat";
        home.stateVersion = "25.11";
      };
    };

    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    # Use latest kernel.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    networking.hostName = "chopper"; # Define your hostname.

    # Configure network connections interactively with nmcli or nmtui.
    networking.networkmanager.enable = true;

    # Set your time zone.
    time.timeZone = "America/Merida";

    # Enable CUPS to print documents.
    services.printing.enable = true;

    # Enable sound.
    # services.pulseaudio.enable = true;
    # OR
    services.pipewire = {
      enable = true;
      pulse.enable = true;
    };

    # Enable touchpad support (enabled default in most desktopManager).
    services.libinput.enable = true;

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users.users.${config.nixosConf.user.name} = {
      isNormalUser = true;
      extraGroups = ["sudo" "wheel"]; # Enable ‘sudo’ for the user.
      packages = with pkgs; [
        tree
      ];
    };

    environment.systemPackages = with pkgs; [
      firefox
      git
      pciutils
      asusctl
      file-roller
      gcc
      ripgrep
      luarocks
      nomacs
      feh
    ];

    programs.xfconf.enable = true;
    programs.thunar.enable = true;
    programs.thunar.plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
    services.gvfs.enable = true; # Mount, trash, and other functionalities
    services.tumbler.enable = true; # Thumbnail support for images

    # DIRENV
    programs.direnv.enable = true;
    programs.direnv.nix-direnv.enable = true;

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    # Enable avahi to allow use hostname in local network
    services.avahi.enable = true;
    # Enable the mDNS NSS plugin so this host can *resolve* `.local` names
    # (e.g. klipper.local), not just announce its own hostname.
    services.avahi.nssmdns4 = true;
    networking.firewall.allowedUDPPorts = [5353];
    networking.firewall.allowedTCPPorts = [8080];

    # Display manager
    # Ensure greetd is not enabled anywhere by default (hosts can override if needed)
    services.greetd.enable = lib.mkDefault false;

    # Animations  "doom", "colormix", "matrix"
    services.displayManager.ly = {
      enable = true;
      settings = {
        animation = "doom";
        bigclock = true;
        # --- Color Settings (0xAARRGGBB) ---
        # Background color of dialog box (Black)
        bg = "0x00000000";
        # Foreground text color (Cyan: #00FFFF)
        fg = "0x0000FFFF";
        # Border color (Red: #FF0000)
        border_fg = "0x00FF0000";
        # Error message color (Red)
        error_fg = "0x00FF0000";
        # Clock color (Purple: #800080)
        clock_color = "#800080";
      };
    };

    # BLUETOOTH
    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          FastConnectable = true;
        };
        Policy = {
          AutoEnable = true;
        };
      };
    };

    services.upower.enable = true;
    services.asusd.enable = true;
    services.supergfxd.enable = true;

    nixpkgs.config.allowUnfree = true;
    # Enable OpenGL
    hardware.graphics = {
      enable = true;
    };

    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
      modesetting.enable = true;

      # HDMI-A-1 hangs off the dGPU (0000:01:00.0) while niri renders on i915, so
      # the external output is a cross-GPU destination whose plane needs a
      # hardware semaphore. If the dGPU loses its display state -- after a resume
      # (PM: suspend exit), or when the output is re-attached -- nvidia-drm
      # rejects niri's atomic commit:
      #   NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: Shader Program Header
      #   *ERROR* Failed to initialize semaphore for plane fence
      #   *ERROR* Failed to apply atomic modeset.  Error code: -11  (EAGAIN)
      # Xid 13 means the GPU ran a command stream whose shader memory is gone:
      # the client context survived the resume, the VRAM it points at did not.
      # niri never retries an EAGAIN commit, so the panel stays black for the
      # rest of the boot while niri still lists the output as configured.
      #
      # With open = true and driver >= 595 this installs the suspend path NVIDIA
      # documents for a hybrid laptop: NVreg_PreserveVideoMemoryAllocations=1 plus
      # NVreg_UseKernelSuspendNotifiers=1 (powerManagement.kernelSuspendNotifier
      # defaults to true for the open module from 595), so the kernel notifies the
      # driver instead of the nvidia-sleep.sh systemd units, which are not
      # installed in this combination. The driver's own defaults here are
      # PreserveVideoMemoryAllocations=2 and DynamicPowerManagement=3 with no
      # freeze/thaw mechanism registered at all.
      # See odd/tasks/chopper-hdmi-dgpu-power.md.
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = true;
      nvidiaSettings = true;
      #package = config.boot.kernelPackages.nvidiaPackages.stable;

      # Falsified hypothesis, kept on purpose for one more deploy so the
      # powerManagement change is the only variable in the test. nvidia-drm's
      # fbdev emulation was blamed for the rejected commit because the
      # `fb1: nvidia-drmdrmfb` registration was the one anomaly in the single
      # retained failing trace; the same failure later recurred with this
      # override active and no fbdev device present. It is harmless: fbcon is
      # bound to i915drmfb (fb0), not to this one, and nixpkgs otherwise sets
      # fbdev=1 unconditionally for modesetting.enable with driver >= 545, with
      # no option of its own. mkForce is required because a plain value conflicts
      # under the attrsOf (attrsOf raw) type. Revert once the output survives
      # suspend and hotplug with the new configuration.
      moduleParams.nvidia-drm.fbdev = lib.mkForce 0;
    };

    # USB serial adapters (CH340/CH341) - allow non-root access
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", MODE="0666"
    '';

    system.stateVersion = "25.11"; # Did you read the comment?

    # automatic updating
    system.autoUpgrade.enable = true;
    system.autoUpgrade.dates = "weekly";
    # autmatic cleanup
    nix.gc.automatic = true;
    nix.gc.dates = "daily";
    nix.gc.options = "--delete-older-than 7d";
    boot.loader.systemd-boot.configurationLimit = 15;
    nix.settings.auto-optimise-store = true;
  };
}
