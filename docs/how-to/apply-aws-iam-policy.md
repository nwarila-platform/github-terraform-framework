# How to apply the AWS IAM policy to the runner OIDC role

**Type**: How-to (Diátaxis). For the policy itself, see [`reference/aws-iam-policy.md`](../reference/aws-iam-policy.md). For rationale, see [`explanation/runner-credentials.md`](../explanation/runner-credentials.md).

This guide walks through attaching the runner's IAM policy to the IAM role that GitHub Actions assumes via OIDC during a terraform run. The role itself is created by an external bootstrap process (account-level IaC); this guide only covers the policy attached to that role.

## Prerequisites

- You have an AWS principal with `iam:CreatePolicy`, `iam:CreatePolicyVersion`, `iam:AttachRolePolicy`, and `iam:GetRolePolicy` on the target role.
- The IAM role exists already, has a trust policy that trusts GitHub Actions OIDC for the `nwarila-platform/github-terraform-runner` repo, and is referenced in the runner's `AWS_ROLE_TO_ASSUME` Actions secret.
- The S3 bucket that stores both the framework's terraform state and the private repo definitions exists. Its name is referenced in the runner's `AWS_S3_BUCKET` Actions secret.
- You have AWS credentials in your shell (`aws sts get-caller-identity` succeeds).

## Procedure: render the policy

The reference doc defines the policy with `<BUCKET>` placeholders. Render it with your real bucket name:

```bash
BUCKET="<your-bucket-name>"  # e.g. 793496711039-terraform
curl -fsSL https://raw.githubusercontent.com/nwarila-platform/github-terraform-framework/main/docs/reference/aws-iam-policy.md \
  | awk '/^```json$/,/^```$/' | sed '1d;$d' \
  | sed "s/<BUCKET>/${BUCKET}/g" \
  > /tmp/runner-policy.json
```

Verify the rendered file is valid JSON and contains your bucket name in every `Resource`:

```bash
jq -e . /tmp/runner-policy.json > /dev/null && echo "valid JSON"
jq -r '.Statement[].Resource' /tmp/runner-policy.json
```

Every resource ARN must contain `arn:aws:s3:::${BUCKET}` literally (with the placeholder substituted). If any line still shows `<BUCKET>`, re-run the substitution.

## Procedure: attach the policy to the role

Two install patterns are supported. Pick one and stay consistent.

### Pattern A: managed policy (recommended)

Create a managed policy and attach it to the role. Managed policies have versions, support rollback, and can be reattached if the role is recreated.

```bash
ROLE_NAME="<role-name>"  # the role referenced by AWS_ROLE_TO_ASSUME
POLICY_NAME="github-terraform-runner-state"

# Create the managed policy (first time only).
aws iam create-policy \
  --policy-name "${POLICY_NAME}" \
  --policy-document file:///tmp/runner-policy.json \
  --description "Runner OIDC role policy: read repos/*.yml + r/w terraform.tfstate + r/w/d lockfile"

# Capture the ARN.
POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn | [0]" --output text)

# Attach to the role.
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
```

To **update** an existing managed policy with a new version:

```bash
aws iam create-policy-version \
  --policy-arn "${POLICY_ARN}" \
  --policy-document file:///tmp/runner-policy.json \
  --set-as-default
```

If the policy already has 5 versions, delete the oldest non-default version first:

```bash
aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --output table
aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id <oldest-non-default>
```

### Pattern B: inline policy

Attach the policy inline to the role. Faster to install, but cannot be rolled back to a prior version and cannot be reattached if the role is recreated.

```bash
ROLE_NAME="<role-name>"

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name github-terraform-runner-state \
  --policy-document file:///tmp/runner-policy.json
```

## Verification

Confirm the role has the policy and that the role can perform the expected actions.

```bash
# Confirm attachment.
aws iam list-attached-role-policies --role-name "${ROLE_NAME}"      # for managed policy
aws iam list-role-policies          --role-name "${ROLE_NAME}"      # for inline policy

# Trigger the terraform workflow and watch.
gh workflow run terraform.yml --repo nwarila-platform/github-terraform-runner
RUN_ID=$(sleep 4 && gh run list --repo nwarila-platform/github-terraform-runner \
           --workflow terraform.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "${RUN_ID}" --repo nwarila-platform/github-terraform-runner --exit-status
```

Expected: the **Download Private Repo Definitions from S3** step prints `Downloaded N private repo definitions.` (with N > 0). The **Terraform Init** step succeeds. No `AccessDenied` errors anywhere in the log.

If the run fails with `AccessDenied (...) when calling the ListObjectsV2 operation` on `s3:ListBucket`, the most common cause is a `NumericLessThanEquals s3:max-keys` condition on the `ListBucket` statement. Remove it — see [`explanation/runner-credentials.md`](../explanation/runner-credentials.md) for the diagnosis trail.

## Procedure: roll back to a previous policy version

Only available for **Pattern A** (managed policy):

```bash
aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --output table
aws iam set-default-policy-version --policy-arn "${POLICY_ARN}" --version-id <previous-version>
```

The role immediately uses the prior version on its next assume-role call.

## Procedure: revoke (incident response)

If you suspect the role has been misused:

1. Detach the policy: `aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"` (Pattern A) or `aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name github-terraform-runner-state` (Pattern B).
2. Audit CloudTrail for any unexpected `AssumeRoleWithWebIdentity` events on the role and any S3 actions thereafter.
3. Investigate, then re-apply the policy by following **Procedure: attach the policy to the role**.

## Related

- [`reference/aws-iam-policy.md`](../reference/aws-iam-policy.md) — the policy this procedure installs.
- [`explanation/runner-credentials.md`](../explanation/runner-credentials.md) — rationale and known gotchas.
- [ADR-0002 (Adopt Diátaxis)](https://github.com/nwarila-platform/.github/blob/main/docs/decision-records/0002-adopt-diataxis-documentation-framework.md) — why this doc lives in `how-to/`.
