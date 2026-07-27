{
  description = "Rust and Kirigami development environment for SMS2";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          pkg-config
          rustc
          cargo
          clippy
          rustfmt
          clang
        ];

        buildInputs = with pkgs.kdePackages; [
          extra-cmake-modules
          qtbase
          qtdeclarative
          qttools
          kirigami
          kirigami-addons
          qqc2-desktop-style
        ];

        CXX = "clang++";
        REAL_QMAKE = "${pkgs.kdePackages.qtbase}/bin/qmake6";
        RUSTFLAGS = "-L native=${pkgs.kdePackages.qtdeclarative}/lib -L native=${pkgs.kdePackages.qtbase}/lib";
        shellHook = ''
          export QMAKE="$PWD/qmake-wrapper"
          export CARGO_TARGET_DIR="$PWD/target"
          printf '%s\n' "$REAL_QMAKE" > /tmp/sms2-real-qmake
          export QT_TOOLS_DIR="/tmp/sms2-qt-tools"
          export QT_LIBS_DIR="/tmp/sms2-qt-libs"
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with pkgs.kdePackages; [ qtbase qtdeclarative ])}:''${LD_LIBRARY_PATH:-}"
          export QT_PLUGIN_PATH="${pkgs.kdePackages.qtbase}/lib/qt-6/plugins:${pkgs.kdePackages.qtdeclarative}/lib/qt-6/plugins:''${QT_PLUGIN_PATH:-}"
          export QML2_IMPORT_PATH="${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml:${pkgs.kdePackages.kirigami}/lib/qt-6/qml:${pkgs.kdePackages.kirigami-addons}/lib/qt-6/qml:${pkgs.kdePackages.qqc2-desktop-style}/lib/qt-6/qml:''${QML2_IMPORT_PATH:-}"
          mkdir -p "$QT_TOOLS_DIR"
          mkdir -p "$QT_LIBS_DIR"
          ln -sf ${pkgs.kdePackages.qtbase}/libexec/* "$QT_TOOLS_DIR/"
          ln -sf ${pkgs.kdePackages.qtdeclarative}/libexec/* "$QT_TOOLS_DIR/"
          ln -sf ${pkgs.kdePackages.qtbase}/lib/libQt6* "$QT_LIBS_DIR/"
          ln -sf ${pkgs.kdePackages.qtdeclarative}/lib/libQt6* "$QT_LIBS_DIR/"
        '';
      };
    };
}
