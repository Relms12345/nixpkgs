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
  click,
  cryptography,
  detect-secrets,
  expression,
  fastapi,
  fastapi-sso,
  fastuuid,
  fetchFromGitHub,
  fetchPypi,
  filelock,
  google-cloud-iam,
  google-cloud-kms,
  google-cloud-speech,
  google-genai,
  granian,
  grpcio,
  gunicorn,
  hatchling,
  hiredis,
  httpx2,
  huggingface-hub,
  importlib-metadata,
  inquirerpy,
  jinja2,
  jsonschema,
  langfuse,
  maturin,
  mcp,
  nodejs,
  openai,
  opentelemetry-api,
  opentelemetry-exporter-otlp,
  opentelemetry-instrumentation-fastapi,
  opentelemetry-sdk,
  orjson,
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
    owner = "Relms12345";
    repo = "litellm";
    rev = "41b863869ecc8fe0bef7374113f30b542d99d5f7";
    hash = "sha256-o+TyPnRq9XKToOHnvrR78WDE4708LIewHZracRrKOmg=";
  };

  llm-sandbox = buildPythonPackage {
    pname = "llm-sandbox";
    version = "0.3.45";
    pyproject = true;

    src = fetchPypi {
      pname = "llm_sandbox";
      version = "0.3.45";
      hash = "sha256-Atn0oZNuudt7P4dJtdI7wRhDR4am9fVIvnu9A3H2dPI=";
    };

    build-system = [hatchling];
    dependencies = [pydantic];

    pythonImportsCheck = ["llm_sandbox"];

    doCheck = false;
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
    version = "0.4.103";
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
    pythonImportsCheck = ["litellm_proxy_extras"];

    meta = {
      description = "Bundled prisma migrations and helpers for the LiteLLM proxy";
      homepage = "https://github.com/BerriAI/litellm";
      license = lib.licenses.mit;
    };
  };

  litellm-enterprise = buildPythonPackage rec {
    pname = "litellm-enterprise";
    version = "0.1.72";
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
in buildPythonPackage rec {
  pname = "litellm";
  version = "1.105.0";
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
    inherit
      pname
      version
      src
      cargoRoot
      ;
    hash = "sha256-8JbjXY2ubiMcrr0j6r8RAfEQh43mN676XPL6M+elf0o=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "maturin==1.15.0" "maturin==${maturin.version}"

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
    boto3
    click
    fastuuid
    filelock
    httpx2
    huggingface-hub
    importlib-metadata
    jinja2
    jsonschema
    openai
    pydantic
    pydantic-settings
    python-dotenv
    pyyaml
    tiktoken
    tokenizers
  ]
  ++ httpx2.optional-dependencies.http2;

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
      granian
      gunicorn
      httpx2
      hiredis
      inquirerpy
      litellm-enterprise
      litellm-proxy-extras
      mcp
      orjson
      polars
      pyjwt
      pynacl
      # FIXME pyroscope-io
      python-multipart
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
      google-cloud-kms
      google-cloud-iam
      prismaPatched
      psycopg
      redisvl
      resend
    ];

    proxy-runtime = [
      anthropic
      # FIXME package azure-ai-contentsafety
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
    ] ++ anthropic.optional-dependencies.vertex;
  };

  pythonImportsCheck = [ "litellm" ];

  pythonRelaxDeps = [
    "boto3"
    "importlib-metadata"
    "pydantic-settings"
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
    description = "Use any LLM as a drop in replacement for gpt-3.5-turbo. Use Azure, OpenAI, Cohere, Anthropic, Ollama, VLLM, Sagemaker, HuggingFace, Replicate (100+ LLMs)";
    mainProgram = "litellm";
    homepage = "https://github.com/BerriAI/litellm";
    changelog = "https://github.com/BerriAI/litellm/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ happysalada ];
  };
}
