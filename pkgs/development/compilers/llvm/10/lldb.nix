{ stdenv
, bashInteractive
, wasmtime
, fetchFromGitHub
, fetchGit
, cmake
, zlib
, ncurses
, swig
, which
, libedit
, libxml2
, llvm
, clang-unwrapped
, python3
, version
, darwin
, lit
, ocamlPackages
, enableManpages ? false
}:

let ocaml = ocamlPackages.ocaml;

    vlq = stdenv.mkDerivation rec {
      name = "ocaml${ocaml.version}-vlq-${version}";

      src = fetchFromGitHub {
        owner = "flowtype";
        repo = "ocaml-vlq";
        rev = version;
        sha256 = "09jdgih2n2qwpxnlbcca4xa193rwbd1nw7prxaqlg134l4mbya83";
      };

      buildInputs = [ ocaml ocamlPackages.findlib ocamlPackages.dune ]; # 

      buildPhase = ''
        dune build
      '';

      inherit (ocamlPackages.dune) installPhase;

      meta = {
        homepage = https://github.com/flowtype/ocaml-vlq;
        platforms = ocaml.meta.platforms or [];
        description = "A simple library for encoding variable-length quantities";
        license = stdenv.lib.licenses.mit;
        maintainers = with stdenv.lib.maintainers; [ vbgl ];
      };
    };

  moc = stdenv.mkDerivation {
      pname = "motoko-compiler";
      version = "0.1";

      src = fetchGit {
        url    = "git@github.com:dfinity-lab/motoko.git";
        ref    = "gabor/dwarf";
        rev    = "4abc0ff69221659b8be7a3e36622e8edfa879113";
      };

      buildInputs = [
        vlq
        ocaml
        ocamlPackages.dune
        ocamlPackages.checkseum
        ocamlPackages.findlib
        ocamlPackages.menhir
        ocamlPackages.cow
        ocamlPackages.stdint
        ocamlPackages.wasm
        ocamlPackages.zarith
        ocamlPackages.yojson
        ocamlPackages.ppxlib
        ocamlPackages.ppx_inline_test
        ocamlPackages.uucp
      ];

      patches = [ ./mo-rts.wasm ];
      patchPhase = ''
        cp $patches ./mo-rts.wasm
        runHook postPatch
      '';
      postPatch = ''
        patchShebangs src
      '';

      buildPhase = ''
        make -C src moc
      '';

      installPhase = ''
        mkdir -p $out/bin $out/lib
        cp src/_build/default/exes/moc.exe $out/bin/moc
        cp ./mo-rts.wasm $out/lib
      '';
    };

    src-repo = {
      owner  = "ggreif";
      repo   = "llvm-project";
      rev    = "d17254d75ce9ea2932291ed2866a42ce9685eafe";
      sha256 = "1i46nrdwldyw1racfa7hraxmw5nbgcq9iryrzgfkgj48il85gc2j";
    };
in
stdenv.mkDerivation (rec {
  pname = "lldb";
  inherit version;

  src = fetchFromGitHub src-repo;

  sourceRoot = "source/${pname}";

  patches = [ ./lldb-procfs.patch ];

  postPatch = ''
    substituteInPlace tools/CMakeLists.txt \
      --replace "EXCLUDE_FROM_ALL" ""
  '';

  nativeBuildInputs = [ cmake python3 which swig lit ]
    ++ stdenv.lib.optionals enableManpages [ python3.pkgs.sphinx python3.pkgs.recommonmark ];

  buildInputs = [
    ncurses
    zlib
    libedit
    libxml2
    llvm
    bashInteractive
    moc
  ]
  ++ stdenv.lib.optionals stdenv.isDarwin [
    darwin.libobjc
    darwin.apple_sdk.libs.xpc
    darwin.apple_sdk.frameworks.Foundation
    darwin.bootstrap_cmds
    darwin.apple_sdk.frameworks.Carbon
    darwin.apple_sdk.frameworks.Cocoa
  ];

  hardeningDisable = [ "format" ];

  cmakeFlags = [
    "-DLLVM_ENABLE_RTTI=OFF"
    "-DClang_DIR=${clang-unwrapped}/lib/cmake"
    "-DLLVM_EXTERNAL_LIT=${lit}/bin/lit"
    "-DPYTHON_HOME=${python3}"
    "-DLLDB_RELOCATABLE_PYTHON=0"
  ] ++ stdenv.lib.optionals stdenv.isDarwin [
    "-DLLDB_USE_SYSTEM_DEBUGSERVER=ON"
  ] ++ stdenv.lib.optionals (!stdenv.isDarwin) [
    "-DLLDB_CODESIGN_IDENTITY=" # codesigning makes nondeterministic
  ] ++ stdenv.lib.optionals enableManpages [
    "-DLLVM_ENABLE_SPHINX=ON"
    "-DSPHINX_OUTPUT_MAN=ON"
    "-DSPHINX_OUTPUT_HTML=OFF"
  ];

  postConfigure = ''
    substituteInPlace ../build/source/CMakeFiles/lldbBase.dir/build.make \
      --replace lldb/build/source/VCSVersion.inc lldb/build/source/VCSVersion.incX \
      --replace source/VCSVersion.inc: source/VCSVersion.incX:
    cat >> ../build/source/CMakeFiles/lldbBase.dir/build.make << EOF
    source/VCSVersion.inc: source/VCSVersion.incX
    	echo '#define LLDB_REVISION "${src-repo.rev}"' >> \$@
    	echo '#define LLDB_REPOSITORY "git@github.com:${src-repo.owner}/${src-repo.repo}"' >> \$@
    EOF
  '';

  enableParallelBuilding = true;

  postInstall = ''
    # Editor support
    # vscode:
    install -D ../tools/lldb-vscode/package.json $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/package.json
    mkdir -p $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/bin
    ln -s $out/bin/lldb-vscode $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/bin

    # IDE settings
    cat > $out/share/vscode/settings.json << EOF
    {
      "lldb.library": "$out/lib/liblldb${stdenv.targetPlatform.extensions.sharedLibrary}",
      "debug.allowBreakpointsEverywhere": true,
      "lldb.launch.sourceLanguages": [
        "cpp",
        "rust",
        "motoko"
      ],
      "lldb.launch.sourceMap": {
        "." : "\''${workspaceFolder}"
      },
      "lldb.launch.initCommands": [
        "settings set plugin.jit-loader.gdb.enable on",
      ],
      "update.mode": "none",
      "update.showReleaseNotes": false,
      "extensions.autoCheckUpdates": false,
      "extensions.autoUpdate": false,
      "workbench.settings.enableNaturalLanguageSearch": false,
      "workbench.enableExperiments": false,
      "terminal.integrated.shell.linux": "${bashInteractive}/bin/bash",
      "terminal.integrated.shell.osx": "${bashInteractive}/bin/bash",
      "files.autoSave": "afterDelay"
    }
    EOF

    # Build task
    cat > $out/share/vscode/tasks.json << EOF
    {
      "version": "2.0.0",
      "tasks": [
        {
          "label": "Build Motoko",
          "type": "shell",
          "command": "${moc}/bin/moc",
          "args": ["-wasi-system-api", "-g", "\''${relativeFile}",
                   "-o", "\''${relativeFileDirname}/\''${fileBasename}.wasm"],
          "options": {"env": {"MOC_RTS": "${moc}/lib/mo-rts.wasm"}},
          "group": "build"
        }
      ]
    }
    EOF

    # Debug launcher
    cat > $out/share/vscode/launch.json << EOF
    {
      "version": "0.2.0",
      "configurations": [
        {
          "type": "lldb",
          "request": "launch",
          "name": "Debug",
          "program": "${wasmtime}/bin/wasmtime",
          "args": ["-g", "\''${relativeFileDirname}/\''${fileBasename}.wasm"],
          "cwd": "\''${workspaceFolder}"
        }
      ]
    }
    EOF

    # Setup script for `codium` workspace
    cat > $out/share/vscode/setup-workspace.sh << EOF
    VSCODIUM_SUPPORT=$out/share/vscode

    cp \''${VSCODIUM_SUPPORT}/settings.json \$HOME/Library/Application\ Support/VSCodium/User/
    cp \''${VSCODIUM_SUPPORT}/settings.json \$HOME/.config/VSCodium/User/
    cp \''${VSCODIUM_SUPPORT}/launch.json ./.vscode/
    cp \''${VSCODIUM_SUPPORT}/tasks.json ./.vscode/
    EOF
  '';

  meta = with stdenv.lib; {
    description = "A next-generation high-performance debugger";
    homepage = "https://lldb.llvm.org";
    license = licenses.ncsa;
    platforms = platforms.all;
  };
} // stdenv.lib.optionalAttrs enableManpages {
  pname = "lldb-manpages";

  buildPhase = ''
    make docs-lldb-man
  '';

  propagatedBuildInputs = [];

  installPhase = ''
    # manually install lldb man page
    mkdir -p $out/share/man/man1
    install docs/man/lldb.1 -t $out/share/man/man1/
  '';

  postPatch = null;
  postInstall = null;

  outputs = [ "out" ];

  doCheck = false;

  meta.description = "man pages for LLDB ${version}";
})
