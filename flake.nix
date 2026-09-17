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
            builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" "vagrant" ];
          # ecdsa is a transitive build-time dep of the Python security tooling
          # (checkov/semgrep), flagged insecure upstream. Dev-shell only, never
          # shipped to a runtime image.
          config.permittedInsecurePackages = [ "python3.14-ecdsa-0.19.2" ];
        };
        # Ansible with pywinrm in its OWN dependency closure, so the winrm
        # connection plugin (the ansible interpreter, not a sibling python) can
        # import it and manage the Windows guest in the vagrant-windows chamber.
        # withPackages does not work here: the `ansible` console script keeps its
        # ansible-core shebang and never sees a sibling pywinrm.
        ansibleEnv = pkgs.ansible.overridePythonAttrs (old: {
          propagatedBuildInputs =
            (old.propagatedBuildInputs or [ ]) ++ [ pkgs.python3Packages.pywinrm ];
        });
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
            kind      # local Kubernetes for the kind-* chambers
            k8sgpt    # LLM-backed Kubernetes triage (kind-k8sgpt chamber)
            kcat      # Kafka producer/consumer CLI
            go-task   # task runner (Taskfile)

            # VM lab + config management (vagrant-ansible chamber).
            # vagrant is unfree (BSL) and bundles vagrant-libvirt as a system
            # plugin; libvirtd itself is a host prerequisite (nixos-rebuild).
            vagrant
            ansibleEnv   # ansible + pywinrm (Linux + Windows/WinRM chambers)
            ansible-lint

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

            # AI/LLM stack (local-sre-copilot chamber): local model serving + a uv-managed
            # Python venv (the AI libraries move too fast for nixpkgs). The vector
            # store is Qdrant in qdrant-client's embedded local mode (in the venv),
            # so no separate server is needed.
            ollama
            uv
          ];

          shellHook = ''
            echo "sanctum shell"
            echo "terraform $(terraform version -json | jq -r .terraform_version) | $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)"
            # Binary Python wheels (pydantic-core, numpy, tokenizers, ...) need
            # libstdc++/zlib at runtime; NixOS has no FHS linker, so expose them
            # for the uv venv the local-sre-copilot chamber uses.
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            # Keep uv on the nix Python instead of downloading its own CPython.
            export UV_PYTHON_DOWNLOADS=never
          '';
        };
      });
}
