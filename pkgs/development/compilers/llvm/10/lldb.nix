{ stdenv
, fetch
, cmake
, zlib
, ncurses
, swig
, which
, libedit
, libxml2
, llvm
, clang-unwrapped
, python
, version
, darwin
, lit
, enableManpages ? true
}:

stdenv.mkDerivation rec {
  pname = "lldb";
  inherit version;

  src = fetch pname "0w9d29vsprj69gfxxn6llkvhlxp25vlbbpv64r32kir2s6h8nyyd";

  patches = [ ./lldb-procfs.patch ];

  nativeBuildInputs = [ cmake python which swig lit ]
    ++ stdenv.lib.optionals enableManpages [ python.pkgs.sphinx python.pkgs.recommonmark ];

  buildInputs = [
    ncurses
    zlib
    libedit
    libxml2
    llvm
  ]
  ++ stdenv.lib.optionals stdenv.isDarwin [
    darwin.libobjc
    darwin.apple_sdk.libs.xpc
    darwin.apple_sdk.frameworks.Foundation
    darwin.bootstrap_cmds
    darwin.apple_sdk.frameworks.Carbon
    darwin.apple_sdk.frameworks.Cocoa
  ];

  CXXFLAGS = "-fno-rtti";
  hardeningDisable = [ "format" ];

  cmakeFlags = [
    "-DLLDB_CODESIGN_IDENTITY=" # codesigning makes nondeterministic
    "-DClang_DIR=${clang-unwrapped}/lib/cmake"
    "-DLLVM_EXTERNAL_LIT=${lit}/bin/lit"
  ] ++ stdenv.lib.optionals stdenv.isDarwin [
    "-DLLDB_USE_SYSTEM_DEBUGSERVER=ON"
  ] ++ stdenv.lib.optionals enableManpages [
    "-DLLVM_ENABLE_SPHINX=ON"
    "-DSPHINX_OUTPUT_MAN=ON"
    "-DSPHINX_OUTPUT_HTML=OFF"
  ]
;

  enableParallelBuilding = true;

  postInstall = ''
    # man page
    mkdir -p $out/share/man/man1
    make docs-lldb-man
    install docs/man/lldb.1 -t $out/share/man/man1/

    # Editor support
    # vscode:
    install -D ../tools/lldb-vscode/package.json $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/package.json
    mkdir -p $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/bin
    ln -s $out/bin/lldb-vscode $out/share/vscode/extensions/llvm-org.lldb-vscode-0.1.0/bin
  '';

  meta = with stdenv.lib; {
    description = "A next-generation high-performance debugger";
    homepage = http://lldb.llvm.org;
    license = licenses.ncsa;
    platforms = platforms.all;
  };
}
