{
  description = "Sanctum Platform - reproducible toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Terraform is BSL-licensed (unfree) since 1.6. Scope the allowance to
        # Terraform only rather than a blanket allowUnfree. Swap in `opentofu`
        # below if you want a fully FOSS toolchain.
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
          # ecdsa is a transitive build-time dep of the Python security tooling
          # (checkov/semgrep), flagged insecure upstream. Dev-shell only, never
          # shipped to a runtime image.
          config.permittedInsecurePackages = [ "python3.14-ecdsa-0.19.2" ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "sanctum";

          packages = with pkgs; [
            # IaC (trivy covers IaC misconfig scanning via `trivy config`;
            # checkov runs in CI/pre-commit where it installs from pip)
            terraform
            terragrunt
            tflint
            terraform-docs
            awscli2

            # Containers / Kubernetes
            docker-client
            hadolint
            kubectl
            kubernetes-helm
            kustomize
            trivy
            kind      # local Kubernetes for the kind-kafka chamber
            kcat      # Kafka producer/consumer CLI
            go-task   # task runner (Taskfile)

            # Supply-chain security
            cosign
            syft
            grype
            gitleaks
            semgrep

            # Observability
            prometheus.cli          # provides promtool
            prometheus-alertmanager # provides amtool
            grafana-loki            # provides logcli

            # Linters / general
            shellcheck
            yamllint
            jq
            yq-go
            pre-commit

            # App runtimes (sample services)
            python312
            nodejs_22
          ];

          shellHook = ''
            echo "sanctum shell"
            echo "terraform $(terraform version -json | jq -r .terraform_version) | $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)"
          '';
        };
      });
}
