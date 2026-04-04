{ self, inputs, ... }: {

	flake.nixosModules.chopperHardware = { config, lib, pkgs, modulesPath, ... }: {

		imports =
		[ (modulesPath + "/installer/scan/not-detected.nix")
		];

		boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
		boot.initrd.kernelModules = [ ];
		boot.kernelModules = [ "kvm-intel" ];
		boot.extraModulePackages = [ ];

		fileSystems."/" =
			{ device = "/dev/disk/by-uuid/dc80e510-c0ce-4a4f-a618-e964d975f39d";
			fsType = "ext4";
			};

		fileSystems."/boot" =
			{ device = "/dev/disk/by-uuid/398D-4321";
			fsType = "vfat";
			options = [ "fmask=0077" "dmask=0077" ];
			};

		swapDevices =
			[ { device = "/dev/disk/by-uuid/1e54fd04-5770-4b8a-a42b-dfffde7e78ca"; }
			];

		nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
		hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

	};
}
