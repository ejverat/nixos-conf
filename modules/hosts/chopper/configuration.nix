{ self, inputs, ... }: {

	flake.nixosModules.chopperConfiguration = { config, pkgs, lib, ... }: {
		imports = [
			self.nixosModules.chopperHardware
			self.nixosModules.niri
		];

		nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
		users.users.ejverat = {
			isNormalUser = true;
			extraGroups = [ "sudo" "wheel" ]; # Enable ‘sudo’ for the user.
			packages = with pkgs; [
			tree
			];
		};

		environment.systemPackages = with pkgs; [
			firefox
			neovim
			git
			pciutils
			asusctl
			pciutils
			asusctl
			file-roller
		];
		
		programs.xfconf.enable = true;
		programs.thunar.enable = true;
		programs.thunar.plugins = with pkgs.xfce; [
		  thunar-archive-plugin
		  thunar-volman
		];
		services.gvfs.enable = true; # Mount, trash, and other functionalities
		services.tumbler.enable = true; # Thumbnail support for images

		
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
		networking.firewall.allowedUDPPorts = [ 5353 ];

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
		
		system.stateVersion = "25.11"; # Did you read the comment?
	};

}
