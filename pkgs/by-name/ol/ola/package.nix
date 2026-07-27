{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  bison,
  flex,
  pkg-config,
  libftdi1,
  libuuid,
  cppunit,
  protobuf_21,
  zlib,
  avahi,
  libmicrohttpd,
  perl,
  python3,
}:

stdenv.mkDerivation {
  pname = "ola";
  version = "0.10.9-unstable-2026-06-18";

  src = fetchFromGitHub {
    owner = "OpenLightingProject";
    repo = "ola";
    rev = "99b26c65d45e807032c1337ca7ebf1ac51ff3995";
    hash = "sha256-ajHsSsEsYDmdMCh/K5wD0WSSOpSTcwyH8J6/zRi5OPs=";
  };
  nativeBuildInputs = [
    autoreconfHook
    bison
    flex
    pkg-config
    perl
  ];
  buildInputs = [
    # required for ola-ftdidmx plugin (support for 'dumb' FTDI devices)
    libftdi1
    libuuid
    cppunit
    protobuf_21
    zlib
    avahi
    libmicrohttpd
    python3
  ];
  propagatedBuildInputs = [
    (python3.pkgs.protobuf.override { protobuf = protobuf_21; })
    python3.pkgs.numpy
  ];

  configureFlags = [ "--enable-python-libs" ];

  enableParallelBuilding = true;

  meta = {
    broken = stdenv.hostPlatform.isDarwin;
    description = "Framework for controlling entertainment lighting equipment";
    homepage = "https://www.openlighting.org/ola/";
    maintainers = [ ];
    license = with lib.licenses; [
      lgpl21
      gpl2Plus
    ];
    platforms = lib.platforms.all;
  };
}
