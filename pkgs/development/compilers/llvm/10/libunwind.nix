{ stdenv, version, fetch, cmake, fetchpatch, enableShared ? true }:

stdenv.mkDerivation rec {
  pname = "libunwind";
  inherit version;

  src = fetch pname "0pwpaznhhpd0bj61c8jh6saqn04nclkjw2mk2f90vvfmmg183qkj";

  nativeBuildInputs = [ cmake ];

  enableParallelBuilding = true;

  cmakeFlags = stdenv.lib.optional (!enableShared) "-DLIBUNWIND_ENABLE_SHARED=OFF";
}
