{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  alsa-lib,
  libopus,
  libpulseaudio,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  platform =
    sources.platforms.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  # Prebuilt addons omp extracts and dlopen's at runtime resolve these by
  # soname. The agent injects OMP_NATIVE_LIBRARY_PATH into its inference worker
  # subprocesses' LD_LIBRARY_PATH instead of exporting it process-wide.
  runtimeLibraries = [
    stdenv.cc.cc.lib
    alsa-lib
    libopus
    libpulseaudio
  ];

  # The aarch64 release binary is linked with 64 KiB segment alignment (every
  # PT_LOAD carries p_align 0x10000); the x86_64 one uses 4 KiB. patchelf
  # assumes 4 KiB unless told otherwise.
  elfPageSize = if stdenv.hostPlatform.isAarch64 then "65536" else "4096";
in
stdenv.mkDerivation {
  pname = "omp";
  version = sources.version;

  src = fetchurl {
    url = platform.url;
    hash = platform.hash;
  };

  nativeBuildInputs = [
    installShellFiles
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ makeBinaryWrapper ];

  dontUnpack = true;

  # The release artifact is a Bun single-file executable: the JS bundle and a
  # compressed native addon live inside the ELF/Mach-O image. Stripping rewrites
  # the file and breaks both, and on macOS it also voids the signature.
  dontStrip = true;

  # All ELF rewriting happens in postFixup with an explicit page size; the
  # default --shrink-rpath pass has no such flag.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -m755 -D $src $out/bin/omp
    runHook postInstall
  '';

  # Only the interpreter may be rewritten. Growing the dynamic section of this
  # Bun single-file executable — `--add-needed`, `--set-rpath`, and therefore
  # autoPatchelfHook — shifts the appended payload and makes the aarch64 binary
  # SIGSEGV before main (verified against the release artifact in an arm64
  # container: interpreter-only survives, `--add-needed libstdc++.so.6` and
  # `--set-rpath` both crash). That rules out the DT_NEEDED libstdc++ preload
  # upstream's own Nix build applies, so addons are served through
  # OMP_NATIVE_LIBRARY_PATH alone, which the agent injects into its inference
  # worker subprocesses' LD_LIBRARY_PATH. The binary itself needs nothing beyond
  # glibc: DT_NEEDED is libc, ld-linux, libpthread, libdl and libm, all resolved
  # from the interpreter's built-in search path.
  postFixup =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      patchelf \
        --page-size ${elfPageSize} \
        --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" \
        "$out/bin/omp"
      wrapProgram "$out/bin/omp" \
        --set-default OMP_NATIVE_LIBRARY_PATH "${lib.makeLibraryPath runtimeLibraries}"
    ''
    # Written to files rather than piped through process substitution: a
    # non-zero exit inside <(...) would silently install empty completions.
    + ''
      export HOME="$TMPDIR"
      for shell in bash zsh fish; do
        $out/bin/omp completions "$shell" > "$TMPDIR/omp.$shell"
      done
      installShellCompletion --cmd omp \
        --bash "$TMPDIR/omp.bash" \
        --zsh "$TMPDIR/omp.zsh" \
        --fish "$TMPDIR/omp.fish"
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME="$TMPDIR" $out/bin/omp --version | grep -q "${sources.version}"
    HOME="$TMPDIR" $out/bin/omp --smoke-test | grep -q "smoke-test: ok"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal-based coding agent with multi-model support";
    homepage = "https://omp.sh";
    changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${sources.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "omp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
