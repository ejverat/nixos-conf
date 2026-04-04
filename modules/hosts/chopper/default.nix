{ self, inputs, ... }: {

	flake.nixosConfigurations.chopper = inputs.nixpkgs.lib.nixosSystem {
		modules = [
			self.nixosModules.chopperConfiguration
		];
	};

}
