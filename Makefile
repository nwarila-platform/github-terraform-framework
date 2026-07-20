PYTHON ?= python3
TFLINT ?= tflint

# Mutating: rewrites HCL in place. Use locally before committing.
fmt:
	terraform -chdir=terraform fmt -recursive

# Non-mutating: fails if any file would change. Use in CI.
fmt-check:
	terraform -chdir=terraform fmt -check -recursive

init:
	terraform -chdir=terraform init -backend=false -input=false

validate:
	terraform -chdir=terraform validate

test:
	terraform -chdir=terraform test

# Mutating: regenerates the injected block in docs/reference/terraform.md.
docs:
	terraform-docs --config .terraform-docs.yml terraform

# Non-mutating: fails if docs/reference/terraform.md is out of sync with terraform/.
docs-diff:
	terraform-docs --config .terraform-docs.yml --output-check terraform

docs-check:
	$(PYTHON) tools/check_docs_layout.py

tflint:
	$(TFLINT) --config "$(CURDIR)/.tflint.hcl" --chdir terraform

opa-test:
	@if find policies/opa -name '*.rego' -print -quit | grep -q .; then \
		opa test policies/opa; \
	else \
		echo "no OPA policies to test"; \
	fi

destroy-guard-test:
	$(PYTHON) tools/test_destroy_guard.py

assemble-guard-test:
	bash tools/test_assemble_guard.sh

ci:
	$(MAKE) fmt-check
	$(MAKE) init
	$(MAKE) validate
	$(MAKE) test
	$(MAKE) tflint
	$(MAKE) docs-diff
	$(MAKE) docs-check
	$(MAKE) opa-test
	$(MAKE) assemble-guard-test
	$(MAKE) destroy-guard-test
