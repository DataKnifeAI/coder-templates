# Coder Templates - Local validation
# Run `make test` to validate all templates
# Run `make test V=1` for verbose/debug output

.NOTPARALLEL:

TEMPLATES := kubernetes dkai-dev dkai-arch dkai-agent dkai-hermes
TERRAFORM := terraform

# V=1 enables verbose/debug output
ifneq ($(V),1)
  Q := @
  TF_LOG :=
else
  Q :=
  TF_LOG := TF_LOG=DEBUG
endif

# Use project-local plugin cache to avoid ~/.terraformrc path issues
TF_PLUGIN_CACHE_DIR ?= $(CURDIR)/.terraform.d/plugin-cache
export TF_PLUGIN_CACHE_DIR

# Coder CLI: push from repo root with --directory templates/<name> (not cwd=. or upload has no .tf files)
CODER_ORGANIZATION ?= coder
# Kubernetes namespace for templates that define var.namespace (must match templates/<name>/terraform.tfvars)
K8S_NAMESPACE ?= coder-workspaces

.PHONY: test test-all fmt-check init validate clean fmt debug check-dkai-startup template-push push-dkai-agent push-dkai-hermes

# Validate all templates (init, validate, format check)
test: test-all

test-all: ensure-plugin-cache init validate fmt-check check-dkai-startup

# Shell syntax check on Arch template startup_scripts (Terraform $$ → $ as Coder sees it)
check-dkai-startup:
	$(Q)scripts/check-dkai-startup-shell.sh

# Ensure plugin cache dir exists (avoids Terraform CLI config warnings)
ensure-plugin-cache:
	$(Q)mkdir -p $(TF_PLUGIN_CACHE_DIR)

# Initialize Terraform for each template
init:
	$(Q)for template in $(TEMPLATES); do \
		echo "==> Initializing templates/$$template"; \
		$(TF_LOG) $(TERRAFORM) -chdir=templates/$$template init -backend=false || exit 1; \
	done

# Validate Terraform configuration for each template
validate:
	$(Q)for template in $(TEMPLATES); do \
		echo "==> Validating templates/$$template"; \
		$(TF_LOG) $(TERRAFORM) -chdir=templates/$$template validate || exit 1; \
	done

# Check Terraform formatting
fmt-check:
	$(Q)for template in $(TEMPLATES); do \
		echo "==> Format check templates/$$template"; \
		$(TF_LOG) $(TERRAFORM) -chdir=templates/$$template fmt -check -recursive -diff || exit 1; \
	done

# Debug: run test with verbose Terraform output
debug:
	$(MAKE) test V=1

# Format Terraform files (fix)
fmt:
	@for template in $(TEMPLATES); do \
		echo "==> Formatting templates/$$template"; \
		$(TERRAFORM) -chdir=templates/$$template fmt -recursive; \
	done

# Remove Terraform cache and lock files
clean:
	@for template in $(TEMPLATES); do \
		echo "==> Cleaning templates/$$template"; \
		rm -rf templates/$$template/.terraform; \
		rm -f templates/$$template/.terraform.lock.hcl; \
	done

# Push a template to Coder (requires: coder login). Example: make template-push TEMPLATE=dkai-agent
template-push:
	@test -n "$(TEMPLATE)" || (echo "usage: make template-push TEMPLATE=dkai-agent [MSG=...]"; exit 1)
	coder templates push "$(TEMPLATE)" \
		--directory "$(CURDIR)/templates/$(TEMPLATE)" \
		--yes \
		--ignore-lockfile \
		--variable namespace="$(K8S_NAMESPACE)" \
		--variable use_kubeconfig=false \
		-O "$(CODER_ORGANIZATION)" \
		-m "$(if $(MSG),$(MSG),$(TEMPLATE): template push)"

push-dkai-agent:
	@$(MAKE) template-push TEMPLATE=dkai-agent MSG="$(MSG)"

push-dkai-hermes:
	@$(MAKE) template-push TEMPLATE=dkai-hermes MSG="$(MSG)"
