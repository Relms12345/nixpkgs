{
  lib,
  a2a-sdk,
  aiohttp,
  anthropic,
  apscheduler,
  azure-identity,
  azure-keyvault-secrets,
  azure-storage-blob,
  azure-storage-file-datalake,
  backoff,
  boto3,
  buildPythonPackage,
  cacert,
  click,
  cryptography,
  expression,
  fastapi,
  fastapi-sso,
  fastuuid,
  fetchFromGitHub,
  fetchurl,
  google-cloud-iam,
  google-cloud-kms,
  google-genai,
  grpcio,
  gunicorn,
  gzip,
  httpx,
  importlib-metadata,
  inquirerpy,
  jinja2,
  jsonschema,
  langfuse,
  maturin,
  mcp,
  nodejs,
  openai,
  openssl,
  opentelemetry-api,
  opentelemetry-exporter-otlp,
  opentelemetry-sdk,
  orjson,
  polars,
  prisma,
  prometheus-client,
  pydantic,
  pydantic-settings,
  pyjwt,
  pynacl,
  pypdf,
  python,
  python-dotenv,
  python-multipart,
  pyyaml,
  resend,
  restrictedpython,
  rich,
  rq,
  rustPlatform,
  sentry-sdk,
  soundfile,
  stdenvNoCC,
  tiktoken,
  tokenizers,
  uv-build,
  uvicorn,
  uvloop,
  websockets,
  nixosTests,
  nix-update-script,
}:

let
  version = "1.98.0";
  proxyExtrasVersion = "0.4.86";
  cargoRoot = "litellm-rust";

  prismaVersion = "5.17.0";
  prismaEngineCommit = "393aa359c9ad4a4bb28630fb5613f9c281cde053";

  src = fetchFromGitHub {
    owner = "BerriAI";
    repo = "litellm";
    tag = "v${version}";
    hash = "sha256-eMquDSSlBo//huXXiys/F36O18VDjv7U1OUe7DrKhus=";
  };

  prismaQueryEngine = fetchurl {
    url = "https://binaries.prisma.sh/all_commits/${prismaEngineCommit}/debian-openssl-3.0.x/query-engine.gz";
    hash = "sha256-m8hX3r4NV2DFce5icQdiI9lL6YHCmiJAHeaB8/cOBn0=";
  };

  prismaSchemaEngine = fetchurl {
    url = "https://binaries.prisma.sh/all_commits/${prismaEngineCommit}/debian-openssl-3.0.x/schema-engine.gz";
    hash = "sha256-mK1DP9ZNouoettVlVTqaQzns8w8cIRsotpaQ9ZEmmkE=";
  };

  prismaCliCache = stdenvNoCC.mkDerivation {
    pname = "prisma-cli-cache";
    version = prismaVersion;

    nativeBuildInputs = [
      nodejs
      cacert
    ];

    dontUnpack = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-A+S/7h8OcIrfoBW2Ysaf9yG8MU6zOvrp4gHMFg/UB/8=";

    buildPhase = ''
      export HOME="$TMPDIR"
      export npm_config_cache="$TMPDIR/npm-cache"
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

      mkdir build
      cd build

      cat > package.json <<'EOF'
      {
        "name": "prisma-binaries",
        "version": "1.0.0",
        "private": true,
        "dependencies": {
          "prisma": "${prismaVersion}"
        }
      }
      EOF

      ${nodejs}/bin/npm install \
        --ignore-scripts \
        --no-audit \
        --no-fund \
        --omit=dev
    '';

    installPhase = ''
      mkdir -p "$out"

      cp -r \
        package.json \
        package-lock.json \
        node_modules \
        "$out/"
    '';
  };

  litellm-proxy-extras = buildPythonPackage {
    pname = "litellm-proxy-extras";
    version = proxyExtrasVersion;
    pyproject = true;

    inherit src;

    sourceRoot = "${src.name}/litellm-proxy-extras";

    postPatch = ''
      rm -rf dist

      substituteInPlace pyproject.toml \
        --replace-fail \
          "uv_build==0.11.8" \
          "uv_build==${uv-build.version}"
    '';

    build-system = [
      uv-build
    ];

    doCheck = false;

    pythonImportsCheck = [
      "litellm_proxy_extras"
    ];
  };

in
buildPythonPackage rec {
  pname = "litellm";
  inherit version src;
  pyproject = true;

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
    prisma
    gzip
    nodejs
    openssl
  ];

  inherit cargoRoot;

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit
      pname
      version
      src
      cargoRoot
      ;

    hash = "sha256-iwgIclG8BGeHDNtm686w2Rxe+9ddvBrz1sMfOBeuKK0=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        "maturin==1.9.4" \
        "maturin==${maturin.version}"

    cp \
      litellm-proxy-extras/litellm_proxy_extras/schema.prisma \
      litellm-proxy-schema.prisma

    substituteInPlace litellm-proxy-schema.prisma \
      --replace-fail \
        'provider = "prisma-client-py"' \
        'provider = "prisma-client-py"
         output = "./generated-prisma"'

    substituteInPlace litellm-proxy-schema.prisma \
      --replace-fail \
        'binaryTargets = ["native", "debian-openssl-1.1.x", "debian-openssl-3.0.x", "linux-musl", "linux-musl-openssl-3.0.x"]' \
        'binaryTargets = ["native"]'
  '';

  dependencies = [
    aiohttp
    boto3
    click
    fastuuid
    httpx
    importlib-metadata
    jinja2
    jsonschema
    openai
    pydantic
    pydantic-settings
    python-dotenv
    tiktoken
    tokenizers
  ];

  optional-dependencies = {
    proxy = [
      apscheduler
      azure-identity
      azure-storage-blob
      backoff
      cryptography
      expression
      fastapi
      fastapi-sso
      gunicorn
      inquirerpy
      # FIXME package litellm-enterprise
      litellm-proxy-extras
      mcp
      orjson
      polars
      pyjwt
      pynacl
      python-multipart
      pyyaml
      restrictedpython
      rich
      rq
      soundfile
      uvloop
      uvicorn
      websockets
    ];

    extra_proxy = [
      a2a-sdk
      azure-identity
      azure-keyvault-secrets
      google-cloud-iam
      google-cloud-kms
      prisma
      # FIXME package redisvl
      resend
    ];

    proxy-runtime = [
      anthropic
      # FIXME package azure-ai-contentsafety
      azure-storage-file-datalake
      # FIXME package ddtrace
      # FIXME package detect-secrets
      # FIXME package google-cloud-aiplatform
      google-genai
      grpcio
      langfuse
      # FIXME package mangum
      opentelemetry-api
      opentelemetry-exporter-otlp
      opentelemetry-sdk
      # FIXME package llm-sandbox
      prometheus-client
      pypdf
      sentry-sdk
    ];
  };

  preInstall = ''
    mkdir -p prisma-engines

    gzip -dc ${prismaQueryEngine} > prisma-engines/query-engine
    gzip -dc ${prismaSchemaEngine} > prisma-engines/schema-engine

    chmod +x \
      prisma-engines/query-engine \
      prisma-engines/schema-engine

    export PRISMA_QUERY_ENGINE_BINARY="$PWD/prisma-engines/query-engine"
    export PRISMA_SCHEMA_ENGINE_BINARY="$PWD/prisma-engines/schema-engine"

    export PRISMA_EXPECTED_ENGINE_VERSION="${prismaEngineCommit}"
    export PRISMA_VERSION="${prismaVersion}"

    export PRISMA_CLIENT_ENGINE_TYPE="binary"
    export PRISMA_CLI_QUERY_ENGINE_TYPE="binary"

    export PRISMA_BINARY_CACHE_DIR="${prismaCliCache}"

    export PRISMA_USE_GLOBAL_NODE="true"
    export PRISMA_USE_NODEJS_BIN="false"

    export HOME="$TMPDIR"
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ openssl ]}"
    export PATH="${nodejs}/bin:$PATH"

    # prisma-client-py copies its own package into the generated client.
    # Files originating from the Nix store are read-only, so its copy_tree()
    # produces a read-only generated tree. Patch the generator to make that
    # tree writable immediately after copying.
    mkdir -p prisma-python
    cp -r ${prisma}/${python.sitePackages}/prisma prisma-python/
    chmod -R u+w prisma-python

    python - <<'PY'
    from pathlib import Path

    path = Path("prisma-python/prisma/generator/generator.py")
    text = path.read_text()

    old = """        if not is_same_path(BASE_PACKAGE_DIR, rootdir):
                copy_tree(BASE_PACKAGE_DIR, rootdir)
    """

    new = """        if not is_same_path(BASE_PACKAGE_DIR, rootdir):
                copy_tree(BASE_PACKAGE_DIR, rootdir)

                # Nix: files copied from the store retain read-only permissions.
                rootdir.chmod(rootdir.stat().st_mode | 0o700)
                for path in rootdir.rglob("*"):
                    path.chmod(path.stat().st_mode | 0o700)
    """

    if old not in text:
        raise RuntimeError("Could not patch prisma generator copy_tree block")

    path.write_text(text.replace(old, new))
    PY

    rm -rf generated-prisma

    export PYTHONPATH="$PWD/prisma-python''${PYTHONPATH:+:$PYTHONPATH}"

    python -m prisma generate \
      --schema="$PWD/litellm-proxy-schema.prisma"
  '';

  postInstall = ''
    rm -rf "$out/${python.sitePackages}/prisma"

    cp -r \
      generated-prisma \
      "$out/${python.sitePackages}/prisma"

    # Install the exact Prisma engines used to generate this client.
    mkdir -p "$out/lib/litellm-prisma"

    cp \
      prisma-engines/query-engine \
      "$out/lib/litellm-prisma/query-engine"

    cp \
      prisma-engines/schema-engine \
      "$out/lib/litellm-prisma/schema-engine"

    chmod +x \
      "$out/lib/litellm-prisma/query-engine" \
      "$out/lib/litellm-prisma/schema-engine"

    # Install the pre-populated prisma@5.17.0 CLI cache so runtime migrations
    # never try to npm-install anything.
    mkdir -p "$out/share/litellm/prisma-cli"
    cp -r ${prismaCliCache}/. "$out/share/litellm/prisma-cli/"
  '';

  pythonImportsCheck = [
    "litellm"
    "prisma"
    "litellm_proxy_extras"
  ];

  pythonRelaxDeps = [
    "aiohttp"
    "boto3"
    "click"
    "importlib-metadata"
    "jsonschema"
    "openai"
    "pydantic"
    "python-dotenv"
  ];

  doCheck = false;

  passthru = {
    tests = {
      inherit (nixosTests) litellm;
    };

    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "v([0-9]+\\.[0-9]+\\.[0-9]+)"
      ];
    };
  };

  meta = {
    description = "Use any LLM as a drop in replacement for gpt-3.5-turbo. Use Azure, OpenAI, Cohere, Anthropic, Ollama, VLLM, Sagemaker, HuggingFace, Replicate (100+ LLMs)";
    mainProgram = "litellm";
    homepage = "https://github.com/BerriAI/litellm";
    changelog = "https://github.com/BerriAI/litellm/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ happysalada ];
  };
}
