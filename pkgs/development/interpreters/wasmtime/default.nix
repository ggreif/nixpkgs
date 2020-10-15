{ rustPlatform, fetchFromGitHub, lib, python, cmake, llvmPackages, clang, stdenv, darwin }:

rustPlatform.buildRustPackage rec {
  pname = "wasmtime";
  version = "0.20.0";

  src = fetchFromGitHub {
    owner = "bytecodealliance";
    repo = "${pname}";
    rev = "dev";
    sha256 = "031k1j0wvh6szdap208n8ypclfylhxnkl38zld1mavrl6znd42y4";
    fetchSubmodules = true;
  };

  cargoSha256 = "03f3rjilhg8ky0hns2hy4lzaxhgyr4yxm8id4lycm3qvzpk1mnbn";

  nativeBuildInputs = [ python cmake clang ];
  buildInputs = [ llvmPackages.libclang ] ++
   lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
  LIBCLANG_PATH = "${llvmPackages.libclang}/lib";

  doCheck = true;

  meta = with lib; {
    description = "Standalone JIT-style runtime for WebAssembly, using Cranelift";
    homepage = "https://github.com/bytecodealliance/wasmtime";
    license = licenses.asl20;
    maintainers = [ maintainers.matthewbauer ];
    platforms = platforms.unix;
  };
}
