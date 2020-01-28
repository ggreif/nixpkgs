{ stdenv, version, fetch, cmake, fetchpatch, enableShared ? true }:

stdenv.mkDerivation rec {
  pname = "libunwind";
  inherit version;

  src = fetch pname "0x7grl67cz15gbqzylsz5rnbmwxqr1wim1cjfy7km4hd0j0ihngb";

  nativeBuildInputs = [ cmake ];

  enableParallelBuilding = true;

  cmakeFlags = stdenv.lib.optional (!enableShared) "-DLIBUNWIND_ENABLE_SHARED=OFF";
}
