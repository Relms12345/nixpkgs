{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;

  cfg = config.services.litellm;
  settingsFormat = pkgs.formats.yaml { };

  tiktokenEncodings = {
    cl100k_base = {
      url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken";
      hash = "sha256-Ijkht27pm96ZW3/3OFE+7xAPtR0YyTWXoRO8/+hlsqc=";
    };
  };

  tiktokenCacheEntries = lib.mapAttrsToList (
    _: encoding:
    let
      cacheKey = builtins.hashString "sha1" encoding.url;
      sourceFile = pkgs.fetchurl {
        inherit (encoding) url hash;
      };
    in
    {
      inherit cacheKey sourceFile;
    }
  ) tiktokenEncodings;

  seedTiktokenCacheScript = pkgs.writeShellScript "litellm-seed-tiktoken-cache" ''
    set -eu

    mkdir -p "$CUSTOM_TIKTOKEN_CACHE_DIR"

    ${lib.concatMapStringsSep "\n" (entry: ''
      ln -sf ${entry.sourceFile} "$CUSTOM_TIKTOKEN_CACHE_DIR/${entry.cacheKey}"
    '') tiktokenCacheEntries}
  '';
in
{
  options = {
    services.litellm = {
      enable = lib.mkEnableOption "LiteLLM server";
      package = lib.mkPackageOption pkgs "litellm" { };

      stateDir = lib.mkOption {
        type = types.path;
        default = "/var/lib/litellm";
        example = "/home/foo";
        description = "State directory of LiteLLM.";
      };

      host = lib.mkOption {
        type = types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = ''
          The host address which the LiteLLM server HTTP interface listens to.
        '';
      };

      port = lib.mkOption {
        type = types.port;
        default = 8080;
        example = 11111;
        description = ''
          Which port the LiteLLM server listens to.
        '';
      };

      settings = lib.mkOption {
        type = types.submodule {
          freeformType = settingsFormat.type;
          options = {
            model_list = lib.mkOption {
              type = settingsFormat.type;
              description = ''
                List of supported models on the server, with model-specific configs.
              '';
              default = [ ];
            };
            router_settings = lib.mkOption {
              type = settingsFormat.type;
              description = ''
                LiteLLM Router settings
              '';
              default = { };
            };

            litellm_settings = lib.mkOption {
              type = settingsFormat.type;
              description = ''
                LiteLLM Module settings
              '';
              default = { };
            };

            general_settings = lib.mkOption {
              type = settingsFormat.type;
              description = ''
                LiteLLM Server settings
              '';
              default = { };
            };

            environment_variables = lib.mkOption {
              type = settingsFormat.type;
              description = ''
                Environment variables to pass to the Lite
              '';
              default = { };
            };
          };
        };
        default = { };
        description = ''
          Configuration for LiteLLM.
          See <https://docs.litellm.ai/docs/proxy/configs> for more.
        '';
      };

      environment = lib.mkOption {
        type = types.attrsOf types.str;
        default = {
          SCARF_NO_ANALYTICS = "True";
          DO_NOT_TRACK = "True";
          ANONYMIZED_TELEMETRY = "False";
        };
        example = ''
          {
            NO_DOCS="True";
          }
        '';
        description = ''
          Extra environment variables for LiteLLM.
        '';
      };

      environmentFile = lib.mkOption {
        description = ''
          Environment file to be passed to the systemd service.
          Useful for passing secrets to the service to prevent them from being
          world-readable in the Nix store.
        '';
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/var/lib/secrets/liteLLMSecrets";
      };

      openFirewall = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to open the firewall for LiteLLM.
          This adds `services.litellm.port` to `networking.firewall.allowedTCPPorts`.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}/ui' 0700 - - - -"
      "d '${cfg.stateDir}/tiktoken-cache' 0700 - - - -"
    ];

    systemd.services.litellm = {
      description = "LLM Gateway to provide model access, fallbacks and spend tracking across 100+ LLMs.";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [
        pkgs.nodejs
        pkgs.openssl
      ];

      environment = {
        LITELLM_NON_ROOT = "true";
        LITELLM_UI_PATH = "${cfg.stateDir}/ui";
        CUSTOM_TIKTOKEN_CACHE_DIR = "${cfg.stateDir}/tiktoken-cache";

        HOME = cfg.stateDir;
        XDG_CACHE_HOME = "${cfg.stateDir}/.cache";

        PRISMA_BINARY_CACHE_DIR =
          "${cfg.package}/share/litellm/prisma-cli";

        PRISMA_QUERY_ENGINE_BINARY =
          "${cfg.package}/lib/litellm-prisma/query-engine";

        PRISMA_SCHEMA_ENGINE_BINARY =
          "${cfg.package}/lib/litellm-prisma/schema-engine";

        PRISMA_VERSION = "5.17.0";
        PRISMA_EXPECTED_ENGINE_VERSION =
          "393aa359c9ad4a4bb28630fb5613f9c281cde053";

        PRISMA_USE_GLOBAL_NODE = "true";
        PRISMA_USE_NODEJS_BIN = "false";
      } // cfg.environment;

      serviceConfig =
        let
          configFile = settingsFormat.generate "config.yaml" cfg.settings;
        in
        {
          ExecStartPre = [
            # Seed tokenizer cache with fixed-output files so startup does not
            # depend on outbound network access.
            seedTiktokenCacheScript

            # LiteLLM may rewrite/copy UI assets with read-only permissions
            # during previous runs; normalize writability on each start.
            "${pkgs.runtimeShell} -euc 'chmod -R u+rwX ${cfg.stateDir}/ui'"
          ];
          ExecStart = "${lib.getExe cfg.package} --host \"${cfg.host}\" --port ${toString cfg.port} --config ${configFile}";
          EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
          WorkingDirectory = cfg.stateDir;
          StateDirectory = [
            "litellm"
            "litellm/ui"
            "litellm/tiktoken-cache"
          ];
          RuntimeDirectory = "litellm";
          RuntimeDirectoryMode = "0755";
          PrivateTmp = true;
          DynamicUser = true;
          DevicePolicy = "closed";
          LockPersonality = true;
          PrivateUsers = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          ProtectClock = true;
          ProtectProc = "invisible";
        };
    };

    networking.firewall = lib.mkIf cfg.openFirewall { allowedTCPPorts = [ cfg.port ]; };
  };

  meta.maintainers = [ ];
}
