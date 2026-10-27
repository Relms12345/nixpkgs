{
  lib,
  a2a-sdk,
  aiohttp,
  anthropic,
  anyio,
  apscheduler,
  azure-ai-contentsafety,
  azure-identity,
  azure-keyvault-secrets,
  azure-storage-blob,
  azure-storage-file-datalake,
  backoff,
  boto3,
  buildPythonPackage,
  certifi,
  click,
  cryptography,
  detect-secrets,
  expression,
  fastapi,
  fastapi-sso,
  fastuuid,
  fetchFromGitHub,
  filelock,
  google-cloud-iam,
  google-cloud-kms,
  google-cloud-speech,
  google-genai,
  granian,
  grpcio,
  gunicorn,
  hiredis,
  httpx2,
  huggingface-hub,
  importlib-metadata,
  inquirerpy,
  jinja2,
  jsonschema,
  langfuse,
  llm-sandbox,
  mcp,
  nodejs,
  openai,
  opentelemetry-api,
  opentelemetry-exporter-otlp,
  opentelemetry-instrumentation-fastapi,
  opentelemetry-sdk,
  orjson,
  packaging,
  polars,
  prisma,
  prisma_6,
  prisma-engines_6,
  prometheus-client,
  psycopg,
  pydantic,
  pydantic-settings,
  pyjwt,
  pynacl,
  pypdf,
  python,
  python-dotenv,
  python-multipart,
  pyyaml,
  redisvl,
  resend,
  restrictedpython,
  rich,
  rq,
  rustPlatform,
  sentry-sdk,
  soundfile,
  starlette,
  tiktoken,
  tokenizers,
  tomlkit,
  typing-extensions,
  uv-build,
  uvicorn,
  uvloop,
  websockets,
  nixosTests,
  nix-update-script,
}: let
  prismaEngines = prisma-engines_6;
  prismaCli = prisma_6;

  src = fetchFromGitHub {
    owner = "BerriAI";
    repo = "litellm";
    rev = "100529391a249e2f6c24bdc2c198afb0d57e59cf";
    hash = "sha256-v2RNIsGlFCLCrpT2Q8Q7VAX4ZoJR8xwprqvcqjqJfuE=";
  };

  prismaPatched = prisma.overridePythonAttrs {
    src = fetchFromGitHub {
      owner = "kkkykin";
      repo = "prisma-client-py";
      rev = "e3d23804414e974558f0035e7faace61bea56cf2";
      hash = "sha256-9/uexdgYsv2S1IRh2SzeV3AO1SEBGPTbKspsEJHPEmw=";
    };
  };

  litellm-proxy-extras = buildPythonPackage rec {
    pname = "litellm-proxy-extras";
    version = "0.4.111";
    pyproject = true;

    inherit src;
    sourceRoot = "${src.name}/litellm-proxy-extras";

    postPatch = ''
      rm -rf dist

      substituteInPlace pyproject.toml \
        --replace-fail "uv_build==0.11.8" "uv_build"

      substituteInPlace litellm_proxy_extras/utils.py \
        --replace-fail '            return custom_migrations_dir' '
                  [os.chmod(_p, 0o755 if os.path.isdir(_p) else 0o644) for _r, _d, _fs in os.walk(custom_migrations_dir) for _p in [_r, *(os.path.join(_r, _f) for _f in _fs)]]
                  return custom_migrations_dir'
    '';

    build-system = [uv-build];
    dependencies = [psycopg];
    pythonImportsCheck = ["litellm_proxy_extras"];

    pythonRemoveDeps = [
      "psycopg-binary"
    ];

    meta = {
      description = "Bundled prisma migrations and helpers for the LiteLLM proxy";
      homepage = "https://github.com/BerriAI/litellm";
      license = lib.licenses.mit;
    };
  };

  litellm-enterprise = buildPythonPackage rec {
    pname = "litellm-enterprise";
    version = "0.1.79";
    pyproject = true;

    inherit src;
    sourceRoot = "${src.name}/enterprise";

    postPatch = ''
      rm -rf dist

      substituteInPlace pyproject.toml \
        --replace-fail "uv_build==0.11.8" "uv_build"
    '';

    build-system = [uv-build];
    pythonImportsCheck = ["litellm_enterprise"];

    meta = {
      description = "Bundled prisma migrations and helpers for the LiteLLM proxy";
      homepage = "https://github.com/BerriAI/litellm";
      license = lib.licenses.mit;
    };
  };
in buildPythonPackage (finalAttrs: {
  pname = "litellm";
  version = "1.108.0";
  pyproject = true;

  inherit src;

  nativeBuildInputs = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
    nodejs
    prismaCli
    prismaEngines
    prismaPatched
  ];

  cargoRoot = "litellm-rust";

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs)
      pname
      version
      src
      cargoRoot
      ;
    hash = "sha256-5Tq0/3aKg99JYAWD7bVD2K8CkiPT4yv4t+VSOVIqS98=";
  };

  patches = [
    ./model-cost-map-retry-wait-for-import.patch
  ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "maturin==1.15.0" "maturin>=1.0,<2.0"

    substituteInPlace litellm/proxy/schema.prisma \
      --replace-fail '  provider = "prisma-client-py"' \
      $'  provider = "prisma-client-py"\n  output = "../../prisma"'
  '';

  postInstall = ''
    (
      set -eo pipefail
      export HOME="$TMPDIR"
      export PATH="${prismaPatched}/bin:$PATH"
      export PRISMA_EXPECTED_ENGINE_VERSION="$(grep -o '[0-9a-f]\{40\}' "${prismaCli}/lib/prisma/packages/fetch-engine/package.json" | head -1)"
      export PRISMA_QUERY_ENGINE_BINARY="${prismaEngines}/bin/query-engine"
      export PRISMA_QUERY_ENGINE_LIBRARY="${prismaEngines}/lib/libquery_engine.node"
      export PRISMA_SCHEMA_ENGINE_BINARY="${prismaEngines}/bin/schema-engine"
      export PRISMA_FMT_BINARY="${prismaEngines}/bin/prisma-fmt"

      sp="$out/${python.sitePackages}"
      schema="$sp/litellm/proxy/schema.prisma"

      mkdir -p "$sp/prisma"
      chmod -R u+w "$sp" || true
      ${prismaCli}/bin/prisma generate --schema "$schema"
    )
  '';

  dependencies = [
    aiohttp
    anyio
    boto3
    certifi
    click
    filelock
    fastuuid
    httpx2
    huggingface-hub
    importlib-metadata
    jinja2
    jsonschema
    openai
    packaging
    pydantic
    pydantic-settings
    python-dotenv
    pyyaml
    tiktoken
    tokenizers
    typing-extensions
  ]
  ++ httpx2.optional-dependencies.http2;

  optional-dependencies = {
    proxy = [
      apscheduler
      azure-identity
      azure-storage-blob
      backoff
      boto3
      cryptography
      expression
      fastapi
      fastapi-sso
      granian
      gunicorn
      hiredis
      httpx2
      inquirerpy
      litellm-enterprise
      litellm-proxy-extras
      mcp
      orjson
      polars
      pydantic
      pyjwt
      pynacl
      # FIXME pyroscope-io
      python-multipart
      pyyaml
      restrictedpython
      rich
      rq
      soundfile
      starlette
      tomlkit
      uvicorn
      uvloop
      websockets
    ];

    extra_proxy = [
      a2a-sdk
      azure-keyvault-secrets
      azure-identity
      google-cloud-iam
      google-cloud-kms
      prismaPatched
      psycopg
      redisvl
      resend
    ];

    proxy-runtime = [
      anthropic
      azure-ai-contentsafety
      azure-storage-file-datalake
      # FIXME package ddtrace
      detect-secrets
      # FIXME package google-cloud-aiplatform
      google-cloud-speech
      google-genai
      grpcio
      langfuse
      llm-sandbox
      # FIXME package mangum
      opentelemetry-api
      opentelemetry-exporter-otlp
      opentelemetry-instrumentation-fastapi
      opentelemetry-sdk
      prometheus-client
      pypdf
      sentry-sdk
    ]
    ++ anthropic.optional-dependencies.vertex
    # litellm's skills executor uses the default docker backend
    ++ llm-sandbox.optional-dependencies.docker;
  };

  pythonImportsCheck = [ "litellm" ];

  pythonRelaxDeps = [
    "boto3"
    "certifi"
    "importlib-metadata"
  ];

  # access network
  doCheck = false;

  passthru = {
    tests = { inherit (nixosTests) litellm; };
    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "v([0-9]+\\.[0-9]+\\.[0-9]+)$"
      ];
    };
  };

  meta = {
    description = "Call LLM APIs in OpenAI (or native) format with cost tracking, guardrails, load balancing, and logging";
    mainProgram = "litellm";
    homepage = "https://github.com/BerriAI/litellm";
    changelog = "https://github.com/BerriAI/litellm/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      happysalada
      anish
    ];
  };
})
