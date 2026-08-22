{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
  autoPatchelfHook,
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
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontUnpack = true;

  # The release artifact is a Bun single-file executable: the JS bundle and a
  # compressed native addon live inside the ELF/Mach-O image. Stripping rewrites
  # the file and breaks the loader, and on macOS it also voids the signature.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -m755 -D $src $out/bin/omp
    runHook postInstall
  '';

  # autoPatchelfHook runs inside fixupPhase, before this hook, so the
  # interpreter and RPATH are already rewritten and the binary is executable
  # here. Forcing libstdc++ to load at process start (DT_NEEDED) is what
  # upstream's own Nix build does: addons the main process dlopen's then resolve
  # libstdc++.so.6 / libgcc_s.so.1 from the already-loaded set regardless of the
  # addon's own DT_RUNPATH. patchelf must run before wrapProgram, which replaces
  # $out/bin/omp with a wrapper and moves the real binary to .omp-wrapped.
  postFixup =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      patchelf --add-needed libstdc++.so.6 "$out/bin/omp"
      wrapProgram "$out/bin/omp" \
        --set-default OMP_NATIVE_LIBRARY_PATH "${lib.makeLibraryPath runtimeLibraries}"
    ''
    + ''
      export HOME="$TMPDIR"
      installShellCompletion --cmd omp \
        --bash <($out/bin/omp completions bash) \
        --zsh <($out/bin/omp completions zsh) \
        --fish <($out/bin/omp completions fish)
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME="$TMPDIR" $out/bin/omp --version | grep -q "${sources.version}"
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
