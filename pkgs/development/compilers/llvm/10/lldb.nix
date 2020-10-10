{ stdenv
, wasmtime
, fetchFromGitHub
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
, enableManpages ? false
}:

let src-repo = {
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

  nativeBuildInputs = [ cmake python3 which swig lit ]
    ++ stdenv.lib.optionals enableManpages [ python3.pkgs.sphinx python3.pkgs.recommonmark ];

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

  hardeningDisable = [ "format" ];

  cmakeFlags = [
    "-DLLVM_ENABLE_RTTI=OFF"
    "-DClang_DIR=${clang-unwrapped}/lib/cmake"
    "-DLLVM_EXTERNAL_LIT=${lit}/bin/lit"
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
    # make wasmtime easily accessible
    ln -s ${wasmtime}/bin/wasmtime $out/bin/lldb-wasmtime
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
