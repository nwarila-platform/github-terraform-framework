# AWS IAM policy

**Type**: Reference (Diátaxis). For procedural setup, see [`how-to/apply-aws-iam-policy.md`](../how-to/apply-aws-iam-policy.md). For rationale, see [`explanation/runner-credentials.md`](../explanation/runner-credentials.md).

This document specifies the IAM policy required by the OIDC role that `github-terraform-runner` assumes during CI. The policy grants only what the runner needs: read access to private repository definitions in S3, read/write access to the terraform state object, and read/write/delete access to the state lock object — nothing else.

The role itself is created externally to this framework (typically in a separate AWS account-bootstrap repository). This document specifies only the **policy attached to that role**, not the role's trust relationship.

## Inputs

The policy below assumes:

- **Bucket**: a single S3 bucket holds both the framework's terraform state and the private repo definitions. The placeholder is `<BUCKET>`.
- **Prefix**: all framework artifacts live under `nwarila-platform/github-terraform-runner/`. Replace if the install path differs.
- **State object**: `nwarila-platform/github-terraform-runner/terraform.tfstate`.
- **Lock object**: `nwarila-platform/github-terraform-runner/terraform.tfstate.tflock` (S3-native locking, no DynamoDB).

## Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListRepoFolders",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<BUCKET>",
      "Condition": {
        "StringEquals": {
          "s3:prefix": [
            "nwarila-platform/github-terraform-runner/",
            "nwarila-platform/github-terraform-runner/repos/"
          ]
        }
      }
    },
    {
      "Sid": "ReadRepoDefinitions",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/repos/*.yml"
    },
    {
      "Sid": "ReadWriteStateFileOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/terraform.tfstate"
    },
    {
      "Sid": "ManageS3LockfileOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/terraform.tfstate.tflock"
    },
    {
      "Sid": "DenyDeleteStateFile",
      "Effect": "Deny",
      "Action": "s3:DeleteObject",
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/terraform.tfstate"
    },
    {
      "Sid": "DenyUnencryptedPuts",
      "Effect": "Deny",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    },
    {
      "Sid": "DenyPutsWithoutEncryptionHeader",
      "Effect": "Deny",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<BUCKET>/nwarila-platform/github-terraform-runner/*",
      "Condition": {
        "Null": {
          "s3:x-amz-server-side-encryption": "true"
        }
      }
    }
  ]
}
```

## Statement-by-statement

### `ListRepoFolders` (Allow `s3:ListBucket`)

Permits the runner to list objects under exactly two prefixes: the framework root and the `repos/` subprefix that holds private repo YAML definitions. `StringEquals` (not `StringLike`) keeps this tight: arbitrary prefix patterns are rejected.

This is the statement that allows `aws s3 sync s3://<BUCKET>/nwarila-platform/github-terraform-runner/repos/ ...` to enumerate the YAML files. Without this, the runner would have to hard-code every private repo name in its workflow — a metadata leak from a public workflow file.

**Do NOT add a `NumericLessThanEquals` condition on `s3:max-keys`.** AWS CLI's default `ListObjectsV2` request specifies `max-keys=1000` per page; any condition tighter than that fails the call with a generic "no identity-based policy allows the s3:ListBucket action" — see the explanation doc for the diagnosis trail.

### `ReadRepoDefinitions` (Allow `s3:GetObject`)

Permits reading any `*.yml` file under the `repos/` prefix. Scoped to `*.yml` so non-YAML objects (notes, backups) cannot be exfiltrated through this role.

### `ReadWriteStateFileOnly` (Allow `s3:GetObject` + `s3:PutObject`)

The terraform state object lives at exactly one path; the role can read it and write it but cannot read or write any other object under the framework root. There is no `*` wildcard here.

### `ManageS3LockfileOnly` (Allow `s3:GetObject` + `s3:PutObject` + `s3:DeleteObject`)

The S3-native lock object is short-lived: terraform creates it on lock, deletes it on unlock. `Delete` is required for unlock. Scoped to the exact lockfile path only.

### `DenyDeleteStateFile` (Deny `s3:DeleteObject`)

Belt-and-suspenders. Even if a future change to `ReadWriteStateFileOnly` accidentally widens its `Action` to include `Delete`, this explicit Deny prevents state-object deletion. Explicit Deny in IAM always wins over Allow.

### `DenyUnencryptedPuts` (Deny `s3:PutObject` when encryption is non-AES256)

Catches any PUT request that specifies an SSE algorithm other than `AES256`. The bucket's expectation is SSE-S3 with AES256; alternative algorithms (e.g. SSE-KMS) are explicitly rejected at the role level so the bucket policy and role policy agree.

### `DenyPutsWithoutEncryptionHeader` (Deny `s3:PutObject` when SSE header missing)

Catches PUTs that omit the SSE header entirely. Combined with the previous statement, this requires every write to the framework prefix to carry `x-amz-server-side-encryption: AES256`.

Terraform's S3 backend with `-backend-config=encrypt=true` satisfies both Deny conditions automatically. Hand-uploaded YAMLs must use `aws s3 cp ... --sse AES256`.

## What this policy intentionally does NOT grant

- No `s3:DeleteObject` on the state object (explicit Deny above).
- No `s3:GetObject` outside the `repos/*.yml` and state-object/lockfile paths.
- No KMS permissions. Bucket uses SSE-S3, not SSE-KMS.
- No bucket-level configuration (lifecycle, versioning, policy) — those are managed by the bucket-bootstrap stack, not this role.
- No DynamoDB. State locking uses the [S3-native lock](https://developer.hashicorp.com/terraform/language/backend/s3#s3-state-locking) introduced in terraform 1.10, not the legacy DynamoDB approach.

## Trust relationship (out of scope)

This document specifies the **permissions** policy attached to the role, not the **trust** policy that gates who can assume it. The trust policy should:

1. Trust the GitHub OIDC provider (`token.actions.githubusercontent.com`).
2. Restrict the `sub` claim to the specific repository and branch authorized to assume the role (e.g., `repo:nwarila-platform/github-terraform-runner:ref:refs/heads/main`).
3. Restrict the `aud` claim to `sts.amazonaws.com`.

Trust-policy specifics live in the AWS bootstrap stack, not in this framework.
