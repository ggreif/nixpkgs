{ lowPrio, newScope, pkgs, stdenv, cmake, libstdcxxHook
, libxml2, python, isl, fetchurl, fetchFromGitHub, overrideCC, wrapCCWith, wrapBintoolsWith
, buildLlvmTools # tools, but from the previous stage, for cross
, targetLlvmLibraries # libraries, but from the next stage, for cross
}:

let
  release_version = "10.0.0";
  branchpoint_version = "11-init";
  version = "10.0.0-branch"; # differentiating these is important for rc's

  fetch = name: sha256: fetchurl {
    url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-${release_version}/${name}-${release_version}.src.tar.xz";
    inherit sha256;
  };

  fetchBranchXX = name: sha256: fetchFromGitHub "llvm" "llvm-project" "llvmorg-${branchpoint_version}" sha256; # eta-reduce!

  fetchBranchSub = name: sha256:
    fetchurl {
      name = "X${name}-${branchpoint_version}.tar.gz";
      inherit sha256;
      url = "https://github.com/llvm/llvm-project/archive/llvmorg-${branchpoint_version}.tar.gz";
      downloadToTemp = true;
      postFetch = ''
        mv $downloadedFile $downloadedFile.tar.gz
        unpackFile $downloadedFile.tar.gz
        mv llvm-project-*/${name} ${name}-${version}
        rm -r llvm-project-*
        tar -czf $out ${name}-${version}
        rm -r ${name}-${version}
      '';
    };

  clang-tools-extra_src = fetchBranchSub "clang-tools-extra" "189l0b4lhfavjf1nb6w4dljz9l5dr8739xvlfwxshkq33jg1i03s";

  tools = stdenv.lib.makeExtensible (tools: let
    callPackage = newScope (tools // { inherit stdenv cmake libxml2 python isl release_version version fetch; });
    # callBranchPackage = newScope (tools // { inherit stdenv cmake libxml2 python isl release_version version; fetch = fetchBranch; });
    callBranchSubPackage = newScope (tools // { inherit stdenv cmake libxml2 python isl release_version version; fetch = fetchBranchSub; });
    mkExtraBuildCommands = cc: ''
      rsrc="$out/resource-root"
      mkdir "$rsrc"
      ln -s "${cc}/lib/clang/${release_version}/include" "$rsrc"
      ln -s "${targetLlvmLibraries.compiler-rt.out}/lib" "$rsrc/lib"
      echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
    '' + stdenv.lib.optionalString (stdenv.targetPlatform.isLinux && tools.clang-unwrapped ? gcc && !(stdenv.targetPlatform.useLLVM or false)) ''
      echo "--gcc-toolchain=${tools.clang-unwrapped.gcc}" >> $out/nix-support/cc-cflags
    '';
  in {

    llvm = callBranchSubPackage ./llvm.nix { };
    llvm-polly = callBranchSubPackage ./llvm.nix { enablePolly = true; };

    clang-unwrapped = callBranchSubPackage ./clang {
      inherit clang-tools-extra_src;
    };
    clang-polly-unwrapped = callBranchSubPackage ./clang {
      inherit clang-tools-extra_src;
      llvm = tools.llvm-polly;
      enablePolly = true;
    };

    llvm-manpages = lowPrio (tools.llvm.override {
      enableManpages = true;
      python = pkgs.python;  # don't use python-boot
    });

    clang-manpages = lowPrio (tools.clang-unwrapped.override {
      enableManpages = true;
      python = pkgs.python;  # don't use python-boot
    });

    libclang = tools.clang-unwrapped.lib;

    clang = if stdenv.cc.isGNU then tools.libstdcxxClang else tools.libcxxClang;

    libstdcxxClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      extraPackages = [
        libstdcxxHook
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = mkExtraBuildCommands cc;
    };

    libcxxClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = targetLlvmLibraries.libcxx;
      extraPackages = [
        targetLlvmLibraries.libcxx
        targetLlvmLibraries.libcxxabi
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = mkExtraBuildCommands cc;
    };

    lld = callBranchSubPackage ./lld.nix {};

    lldb = callBranchSubPackage ./lldb.nix {};

    # Below, is the LLVM bootstrapping logic. It handles building a
    # fully LLVM toolchain from scratch. No GCC toolchain should be
    # pulled in. As a consequence, it is very quick to build different
    # targets provided by LLVM and we can also build for what GCC
    # doesn’t support like LLVM. Probably we should move to some other
    # file.

    bintools = callPackage ./bintools.nix {};

    lldClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = targetLlvmLibraries.libcxx;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
      };
      extraPackages = [
        targetLlvmLibraries.libcxx
        targetLlvmLibraries.libcxxabi
        targetLlvmLibraries.compiler-rt
      ] ++ stdenv.lib.optionals (!stdenv.targetPlatform.isWasm) [
        targetLlvmLibraries.libunwind
      ];
      extraBuildCommands = ''
        echo "-target ${stdenv.targetPlatform.config}" >> $out/nix-support/cc-cflags
        echo "-rtlib=compiler-rt -Wno-unused-command-line-argument" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
      '' + stdenv.lib.optionalString (!stdenv.targetPlatform.isWasm) ''
        echo "--unwindlib=libunwind" >> $out/nix-support/cc-cflags
      '' + stdenv.lib.optionalString stdenv.targetPlatform.isWasm ''
        echo "-fno-exceptions" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoLibcxx = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
      };
      extraPackages = [
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = ''
        echo "-target ${stdenv.targetPlatform.config}" >> $out/nix-support/cc-cflags
        echo "-rtlib=compiler-rt" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
        echo "-nostdlib++" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoLibc = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
        libc = null;
      };
      extraPackages = [
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = ''
        echo "-target ${stdenv.targetPlatform.config}" >> $out/nix-support/cc-cflags
        echo "-rtlib=compiler-rt" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoCompilerRt = wrapCCWith {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
        libc = null;
      };
      extraPackages = [ ];
      extraBuildCommands = ''
        echo "-nostartfiles" >> $out/nix-support/cc-cflags
        echo "-target ${stdenv.targetPlatform.config}" >> $out/nix-support/cc-cflags
      '';
    };

  });

  libraries = stdenv.lib.makeExtensible (libraries: let
    # callPackage = newScope (libraries // buildLlvmTools // { inherit stdenv cmake libxml2 python isl release_version version fetch; });
    callBranchSubPackage = newScope (libraries // buildLlvmTools // { inherit stdenv cmake libxml2 python isl release_version version; fetch = fetchBranchSub; });
  in {

    compiler-rt = callBranchSubPackage ./compiler-rt.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoCompilerRt;
      }));

    stdenv = overrideCC stdenv buildLlvmTools.clang;

    libcxxStdenv = overrideCC stdenv buildLlvmTools.libcxxClang;

    libcxx = callBranchSubPackage ./libc++ ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
      }));

    libcxxabi = callBranchSubPackage ./libc++abi.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
        libunwind = libraries.libunwind;
      }));

    openmp = callBranchSubPackage ./openmp.nix {};

    libunwind = callBranchSubPackage ./libunwind.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
      }));

  });

in { inherit tools libraries; } // libraries // tools
