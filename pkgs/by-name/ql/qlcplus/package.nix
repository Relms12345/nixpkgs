{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  udevCheckHook,
  udev,
  alsa-lib,
  fftw,
  ola,
  libftdi1,
  libusb1,
  libusb-compat-0_1,
  libsndfile,
  qt6,
  pipewire,
}:

stdenv.mkDerivation rec {
  pname = "qlcplus";
  version = "5.2.2";

  src = fetchFromGitHub {
    owner = "mcallegari";
    repo = "qlcplus";
    rev = "QLC+_${version}";
    hash = "sha256-e8KyuCnzTUz/f6cfT7LyUQ9snaFBnE5WTc4FP7jhdRY=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    udevCheckHook

    qt6.qttools
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    udev
    alsa-lib
    fftw
    ola
    libftdi1
    libusb1
    libusb-compat-0_1
    libsndfile
    pipewire
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtserialport
    qt6.qtsvg
    qt6.qtwebsockets
    qt6.qt3d
  ];

  postPatch = ''
    patchShebangs .

    substituteInPlace variables.cmake \
      --replace-fail \
        'set(INSTALLROOT "/usr")' \
        "set(INSTALLROOT \"$out\")" \
      --replace-fail \
        'set(UDEVRULESDIR "/etc/udev/rules.d")' \
        "set(UDEVRULESDIR \"$out/lib/udev/rules.d\")"
  '';

  cmakeFlags = [
    "-Dqmlui=ON"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
  ];

  qtWrapperArgs = [
    "--unset QT_STYLE_OVERRIDE"
    "--set QT_QUICK_CONTROLS_STYLE Fusion"
    "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pipewire ]}"
  ];

  doInstallCheck = true;

  meta = {
    description = "Free software to control DMX and analog lighting systems";
    homepage = "https://www.qlcplus.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "qlcplus-qml";
  };
}
