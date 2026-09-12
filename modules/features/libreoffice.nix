{ ... }: {
  flake.nixosModules.libreoffice = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # `libreoffice-qt` is the same LibreOffice build with the Qt6 VCL plugin
      # enabled, which integrates with the Wayland session instead of dragging
      # in the GTK stack. It reads .pptx (OOXML) and the legacy binary .ppt
      # (OLE2) through Impress.
      libreoffice-qt

      # Spellcheck dictionaries. The LibreOffice wrapper iterates NIX_PROFILES
      # and appends every <profile>/share/hunspell to DICPATH, so installing
      # them here is enough -- no manual DICPATH wiring required.
      hunspellDicts.es_MX
      hunspellDicts.en_US
    ];

    # Fonts for documents authored elsewhere. Office and LibreOffice disagree
    # on font metrics, and one missing font reflows the whole deck, so keep
    # both the metric-compatible substitutes and the original families.
    fonts.packages = with pkgs; [
      carlito # metric-compatible with Calibri
      caladea # metric-compatible with Cambria
      liberation_ttf # metric-compatible with Arial / Times New Roman / Courier New
      corefonts # Arial, Times New Roman, Courier New, ... (unfree)
      noto-fonts
      noto-fonts-cjk-sans
    ];
  };
}
