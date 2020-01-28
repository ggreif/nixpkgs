{ stdenv
, fetch
, cmake
, llvm
, perl
, version
}:

stdenv.mkDerivation rec {
  pname = "openmp";
  inherit version;

  src = fetch pname "0kbgl9yxncfndsvk10915gmbmkr4k8j479srd9aszxvya8ml57sw";

  nativeBuildInputs = [ cmake perl ];
  buildInputs = [ llvm ];

  enableParallelBuilding = true;

  meta = {
    description = "Components required to build an executable OpenMP program";
    homepage    = http://openmp.llvm.org/;
    license     = stdenv.lib.licenses.mit;
    platforms   = stdenv.lib.platforms.all;
  };
}
