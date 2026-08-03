# Develop this module

## Local setup

Install the same pinned tools used by CI:

- Terraform 1.15.4
- TFLint 0.62.0
- terraform-docs 0.23.0
- OPA 1.10.0
- Python 3.12 with `pyyaml`, `ruff`, `yamllint`, `zizmor`

## The development loop

```sh
make fmt        # format Terraform
make ci         # run every gate
make docs       # regenerate docs/reference/terraform.md
```

## Before opening a PR

```sh
make ci
```

Local `make ci` is broader than the Terraform test workflow in CI: the hosted
workflow runs `fmt-check`, `init`, `validate`, and `test`, but not the other six
gates, including `docs-diff`.
