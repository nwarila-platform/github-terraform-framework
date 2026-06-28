# Repository Configuration Design Document

> **Scope**: Every GitHub repository setting managed by this shared GitHub Terraform framework, with rationale grounded in industry standards, GitHub's own recommendations, and CI/CD best practices.
>
> **Audience**: Current and future maintainers who need to understand *why* every default was chosen, not just *what* it is.
>
> **Provider**: [`integrations/github` v6.12.1](https://registry.terraform.io/providers/integrations/github/latest/docs)
>
> **Last Updated**: 2026-06-06

---

## Table of Contents

- [1. Design Philosophy](#1-design-philosophy)
- [2. Repository Core Settings](#2-repository-core-settings)
  - [2.1 `name`](#21-name)
  - [2.2 `description`](#22-description)
  - [2.3 `visibility`](#23-visibility)
  - [2.4 `topics`](#24-topics)
  - [2.5 `homepage_url`](#25-homepage_url)
- [3. Repository Features](#3-repository-features)
  - [3.1 `has_issues`](#31-has_issues)
  - [3.2 `has_discussions`](#32-has_discussions)
  - [3.3 `has_projects`](#33-has_projects)
  - [3.4 `has_wiki`](#34-has_wiki)
  - [3.5 `is_template`](#35-is_template)
- [4. Merge Strategy](#4-merge-strategy)
  - [4.1 `allow_squash_merge`](#41-allow_squash_merge)
  - [4.2 `allow_merge_commit`](#42-allow_merge_commit)
  - [4.3 `allow_rebase_merge`](#43-allow_rebase_merge)
  - [4.4 `squash_merge_commit_title`](#44-squash_merge_commit_title)
  - [4.5 `squash_merge_commit_message`](#45-squash_merge_commit_message)
  - [4.6 `merge_commit_title` / `merge_commit_message`](#46-merge_commit_title--merge_commit_message)
  - [4.7 `delete_branch_on_merge`](#47-delete_branch_on_merge)
  - [4.8 `allow_auto_merge`](#48-allow_auto_merge)
  - [4.9 `allow_update_branch`](#49-allow_update_branch)
  - [4.10 `allow_forking`](#410-allow_forking)
  - [4.11 `web_commit_signoff_required`](#411-web_commit_signoff_required)
- [5. Initialization & Licensing](#5-initialization--licensing)
  - [5.1 `auto_init`](#51-auto_init)
  - [5.2 `license_template`](#52-license_template)
  - [5.3 `gitignore_template`](#53-gitignore_template)
- [6. Lifecycle Management](#6-lifecycle-management)
  - [6.1 `archived`](#61-archived)
  - [6.2 `archive_on_destroy`](#62-archive_on_destroy)
- [7. Security & Analysis](#7-security--analysis)
  - [7.1 `vulnerability_alerts`](#71-vulnerability_alerts)
  - [7.2 `dependabot_security_updates`](#72-dependabot_security_updates)
  - [7.3 `advanced_security`](#73-advanced_security)
  - [7.4 `code_security`](#74-code_security)
  - [7.5 `secret_scanning`](#75-secret_scanning)
  - [7.6 `secret_scanning_push_protection`](#76-secret_scanning_push_protection)
  - [7.7 `secret_scanning_ai_detection`](#77-secret_scanning_ai_detection)
  - [7.8 `secret_scanning_non_provider_patterns`](#78-secret_scanning_non_provider_patterns)
- [8. GitHub Pages](#8-github-pages)
- [9. Templates & Forking](#9-templates--forking)
- [10. Branch Protection via Rulesets](#10-branch-protection-via-rulesets)
  - [10.1 Why Rulesets over Branch Protection Rules](#101-why-rulesets-over-branch-protection-rules)
  - [10.2 Ruleset: Default Branch Protection](#102-ruleset-default-branch-protection)
    - [10.2.1 `creation`](#1021-creation)
    - [10.2.2 `deletion`](#1022-deletion)
    - [10.2.3 `non_fast_forward`](#1023-non_fast_forward)
    - [10.2.4 `required_linear_history`](#1024-required_linear_history)
    - [10.2.5 `required_signatures`](#1025-required_signatures)
    - [10.2.6 `update`](#1026-update)
  - [10.3 Ruleset: Pull Request Gate](#103-ruleset-pull-request-gate)
    - [10.3.1 `allowed_merge_methods`](#1031-allowed_merge_methods)
    - [10.3.2 `dismiss_stale_reviews_on_push`](#1032-dismiss_stale_reviews_on_push)
    - [10.3.3 `require_code_owner_review`](#1033-require_code_owner_review)
    - [10.3.4 `require_last_push_approval`](#1034-require_last_push_approval)
    - [10.3.5 `required_approving_review_count`](#1035-required_approving_review_count)
    - [10.3.6 `required_review_thread_resolution`](#1036-required_review_thread_resolution)
  - [10.4 Ruleset: Release Tag Protection](#104-ruleset-release-tag-protection)
    - [10.4.1 `deletion`](#1041-deletion)
    - [10.4.2 `non_fast_forward`](#1042-non_fast_forward)
    - [10.4.3 `required_signatures`](#1043-required_signatures)
  - [10.5 Ruleset: Bypass Actors](#105-ruleset-bypass-actors)
  - [10.6 Ruleset: Conditions](#106-ruleset-conditions)
  - [10.7 Rules Not Enabled by Default (and Why)](#107-rules-not-enabled-by-default-and-why)
- [11. Terraform Resource Lifecycle](#11-terraform-resource-lifecycle)
- [12. Properties Intentionally Omitted](#12-properties-intentionally-omitted)
- [13. Per-Repository Deviation Policy](#13-per-repository-deviation-policy)
- [14. Input Validation](#14-input-validation)
- [15. Infrastructure Security](#15-infrastructure-security)
  - [15.1 Version Control Hygiene (`.gitignore`)](#151-version-control-hygiene-gitignore)
  - [15.2 Credential Management](#152-credential-management)
  - [15.3 Terraform State Security](#153-terraform-state-security)
  - [15.4 Terraform Output Security](#154-terraform-output-security)
  - [15.5 Provider Version Pinning](#155-provider-version-pinning)
- [16. Environment Protection Rules](#16-environment-protection-rules)
  - [16.1 What environments are managed](#161-what-environments-are-managed)
  - [16.2 `wait_timer`](#162-wait_timer)
  - [16.3 `can_admins_bypass`](#163-can_admins_bypass)
  - [16.4 `prevent_self_review`](#164-prevent_self_review)
  - [16.5 Required reviewers](#165-required-reviewers)
  - [16.6 `deployment_branch_policy`](#166-deployment_branch_policy)
  - [16.7 Free-plan billing limits on private repos](#167-free-plan-billing-limits-on-private-repos)

---

## 1. Design Philosophy

This framework manages GitHub repositories as **code** — every setting is declarative, version-controlled, and auditable. The design priorities, in order:

1. **Security-first**: Every default leans toward the most restrictive option that doesn't impede normal maintainer workflows. Public repositories are a living security audit, whether they belong to an individual or an organization.
2. **Clean git history**: Squash-only merges, linear history, and signed commits produce a timeline that tells a story, not a tangle.
3. **Minimal surface area**: Features that are rarely worth the maintenance burden by default (Wiki, Projects) are disabled, while Discussions is enabled by default because both owner models use it as the standard support entry point.
4. **Convention over configuration**: Repos should only specify what makes them *different*. Everything else inherits from battle-tested defaults.

**Governing References**:

- [GitHub Security Best Practices](https://docs.github.com/en/code-security/getting-started/quickstart-for-securing-your-repository) — GitHub's own security quickstart
- [GitHub Repository Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) — GitHub's recommended successor to branch protection rules
- [OpenSSF Scorecard](https://securityscorecards.dev/) — Automated security health checks for open source projects
- [SLSA Framework](https://slsa.dev/) — Supply-chain Levels for Software Artifacts
- [OWASP Top 10](https://owasp.org/Top10/) — Industry-standard web application security risks
- [OWASP Secure by Default](https://owasp.org/www-project-developer-guide/draft/foundations/secure_by_default/) — Principle of secure default configurations
- [NIST SP 800-53](https://csf.tools/reference/nist-sp-800-53/r5/) — Security and Privacy Controls for Information Systems
- [Git Project Commit Signing](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) — Verification of commit authorship
- [Conventional Commits](https://www.conventionalcommits.org/) — Structured commit message specification
- [Developer Certificate of Origin (DCO)](https://developercertificate.org/) — Lightweight contributor agreement

---

## 2. Repository Core Settings

### 2.1 `name`

| | |
|---|---|
| **Type** | `string` (required) |
| **Source** | YML filename / map key |
| **Governance** | — |

The repository name is the map key in each `.yml` file. Names follow kebab-case convention (`lowercase-words-separated-by-hyphens`), which is the GitHub community standard and produces clean, readable URLs.

**Recommendation**: Always kebab-case. Never underscores, camelCase, or spaces. GitHub normalizes display names but URLs are permanent.

### 2.2 `description`

| | |
|---|---|
| **Type** | `string` (optional, strongly recommended) |
| **Default** | `null` |
| **Governance** | GitHub Community Standards |

The description appears in search results, profile pages, GitHub Explore, and social cards (Open Graph). For any public repository, **a description should be treated as required**. An empty description on a public repo looks unfinished.

**Recommendation**: Required for all public repos. Should be a single sentence (under 350 characters) that answers "what does this do and why would someone care?" Avoid marketing language; be specific and technical.

**Quality Criteria**:

- Starts with a noun or action (not "This repo..." or "A tool that...")
- Mentions the primary technology stack
- Differentiates from similar repos in the account

### 2.3 `visibility`

| | |
|---|---|
| **Type** | `string`: `"public"`, `"private"`, or `"internal"` |
| **Default** | `"private"` |
| **Governance** | [GitHub Docs: Repository Visibility](https://docs.github.com/en/repositories/creating-and-managing-repositories/about-repositories#about-repository-visibility) |

The default is `private` — repos must explicitly opt into public visibility. This prevents accidental exposure of work-in-progress or sensitive material.

**Recommendation**: Default to `private`. Portfolio/showcase repos are explicitly set to `public` in their YML. The `internal` visibility is only available for GitHub Enterprise and is not used here.

**Rationale**: The "private by default" pattern is a security fundamental ([OWASP: Secure by Default](https://owasp.org/www-project-developer-guide/draft/foundations/secure_by_default/)). A public repo is a deliberate publication decision, not an accident.

### 2.4 `topics`

| | |
|---|---|
| **Type** | `list(string)` |
| **Default** | `[]` |
| **Governance** | [GitHub Docs: Classifying Your Repository with Topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics) |

Topics power GitHub's search and discovery. GitHub allows up to 20 topics per repository. Topics must be lowercase, hyphenated, and under 50 characters.

**Recommendation**: Every public repo should have 5-15 well-chosen topics. Topics should include:

1. **Primary technology** (e.g., `terraform`, `ansible`, `packer`)
2. **Domain** (e.g., `infrastructure-as-code`, `security`, `compliance`)
3. **Platform** (e.g., `aws`, `proxmox`, `linux`)
4. **Methodology** (e.g., `devsecops`, `ci-cd`, `gitops`)

**Quality Criteria**:

- Use established community topics (check GitHub's [topic pages](https://github.com/topics))
- Topics must accurately describe the repo content — not aspirational
- Remove generic filler topics that don't aid discovery
- Each topic in the list must be unique across the repo's own topic list

### 2.5 `homepage_url`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `null` |
| **Governance** | — |

A URL displayed next to the description on the repo page. Useful for linking to documentation sites, deployed applications, or GitHub Pages.

**Recommendation**: Set only when a meaningful external URL exists (e.g., a GitHub Pages site, published documentation, or live demo). Do not set to the repo's own GitHub URL — that's redundant. For repos with GitHub Pages enabled, this is automatically populated by GitHub.

---

## 3. Repository Features

### 3.1 `has_issues`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Community Standards](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories) |

Issues are GitHub's built-in bug tracker and feature request system. GitHub's Community Standards checklist considers an issue tracker a sign of a healthy project.

**Recommendation**: `true` for all repos. Even for personal portfolio projects, enabled Issues signal that the repository is maintained and open to feedback. Employers reviewing your GitHub will see the Issues tab as a sign of professionalism.

### 3.2 `has_discussions`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Docs: Discussions](https://docs.github.com/en/discussions) |

GitHub Discussions is a forum-style feature for Q&A and open-ended conversation. It's most valuable for projects with active communities.

**Recommendation**: `true` by default. This framework standardizes on Discussions as the primary support channel for questions and open-ended conversation, while Issues remain reserved for actionable work. Repositories that want a different posture should override `has_discussions` explicitly in their YAML definition.

### 3.3 `has_projects`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | — |

GitHub Projects (V2) provides Kanban/roadmap boards attached to a repository.

**Recommendation**: `false` for all repos. Repository-level project boards are legacy (GitHub now recommends organization-level Projects V2). An empty Projects tab on a portfolio repo is visual noise. If you need project management, use organization-level Projects which don't create per-repo tabs.

### 3.4 `has_wiki`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | [Docs-as-Code methodology](https://www.writethedocs.org/guide/docs-as-code/) |

GitHub Wiki is a separate git repository attached to the main repo. Wikis cannot be protected with branch rules, cannot require PR review, and don't appear in code search.

**Recommendation**: `false` for all repos. The modern industry standard is **docs-as-code** — documentation lives in the repository itself (typically `docs/` or `README.md`), goes through the same PR review process as code, and benefits from the same branch protection. An empty Wiki tab is worse than no Wiki tab.

**Rationale**: The OpenSSF Scorecard [Documentation check](https://github.com/ossf/scorecard/blob/main/docs/checks.md#documentation) looks for documentation *in the repository*, not in a Wiki. Wikis are also a known attack vector for SEO spam on public repos.

### 3.5 `is_template`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | [GitHub Docs: Template Repositories](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository) |

Marks the repository as a template, enabling the "Use this template" button.

**Recommendation**: `false` unless the repository is explicitly designed to be scaffolded/cloned as a starting point. Most portfolio repos are reference implementations, not templates.

---

## 4. Merge Strategy

The merge strategy is one of the most opinionated and impactful configuration areas. The choices here directly affect git history readability, `git bisect` usability, and CI/CD pipeline reliability.

### 4.1 `allow_squash_merge`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [Git Project: Squash Merging](https://git-scm.com/docs/git-merge#_squash_merge), [GitHub Engineering Blog](https://github.blog/engineering/engineering-principles/commits-are-snapshots-not-diffs/) |

Squash merging combines all commits from a feature branch into a single commit on the target branch.

**Recommendation**: `true` — this is the **only** merge method enabled by default. Squash merging produces:

- **One commit per feature/fix** on the default branch — clean, scannable history
- **Atomic reverts** — any change can be reverted with a single `git revert`
- **Clean `git bisect`** — every commit on `main` is a complete, working state
- **Simplified `CHANGELOG` generation** — one commit = one entry

This aligns with the practices of GitHub, Google ([Google Engineering Practices](https://google.github.io/eng-practices/review/)), and most modern CI/CD pipelines.

### 4.2 `allow_merge_commit`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | Same as 4.1 |

Traditional merge commits create a merge node with two parents, preserving the full feature branch history.

**Recommendation**: `false`. Merge commits create a non-linear history that is harder to read, harder to bisect, and produces noisy `git log` output. The "merge commit per PR" pattern is a legacy of workflows where branch history was considered valuable — with squash merge, the PR itself preserves that history.

### 4.3 `allow_rebase_merge`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | Same as 4.1 |

Rebase merging replays each commit from the feature branch onto the target branch individually.

**Recommendation**: `false`. While rebase produces linear history, it creates *multiple* commits per PR on the target branch, negating the "one feature = one commit" benefit of squash. It also rewrites commit SHAs, which breaks signature verification for individual commits.

### 4.4 `squash_merge_commit_title`

| | |
|---|---|
| **Type** | `string`: `"PR_TITLE"` or `"COMMIT_OR_PR_TITLE"` |
| **Default** | `"PR_TITLE"` |
| **Governance** | [Conventional Commits](https://www.conventionalcommits.org/) |

Controls the default title of the squashed commit.

**Recommendation**: `"PR_TITLE"`. The PR title is a curated, human-written summary reviewed during the PR process. `COMMIT_OR_PR_TITLE` falls back to the first commit message, which is often a WIP or draft message like "initial attempt" or "fix thing". Using the PR title ensures the mainline history reads as a series of intentional, well-described changes.

### 4.5 `squash_merge_commit_message`

| | |
|---|---|
| **Type** | `string`: `"PR_BODY"`, `"COMMIT_MESSAGES"`, or `"BLANK"` |
| **Default** | `"PR_BODY"` |
| **Governance** | Same as 4.4 |

Controls the default body of the squashed commit.

**Recommendation**: `"PR_BODY"`. The PR description typically contains context, motivation, and test plans — exactly the information that should be preserved in the commit message. `COMMIT_MESSAGES` would dump all intermediate commit messages (often "fix lint", "address review", "oops") into the body. `BLANK` discards context entirely.

### 4.6 `merge_commit_title` / `merge_commit_message`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `null` (not set) |
| **Governance** | — |

These settings configure merge commit formatting. Since `allow_merge_commit = false`, these have no effect and are intentionally left unset.

**Recommendation**: `null`. Setting these when merge commits are disabled would be misleading dead configuration.

### 4.7 `delete_branch_on_merge`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Docs: Managing Branch Deletion](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches) |

Automatically deletes the head branch after a PR is merged.

**Recommendation**: `true`. Stale branches are technical debt. Automatic cleanup:

- Prevents the "200 branches" problem
- Removes confusion about which branches are active
- Keeps the branch namespace clean for `git fetch --prune`

Branches can always be restored from the PR page if needed.

### 4.8 `allow_auto_merge`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Docs: Auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) |

Allows PR authors to enable auto-merge, which merges the PR automatically once all required status checks and reviews pass.

**Recommendation**: `true`. Auto-merge reduces manual toil without reducing safety — the PR still must pass all branch protection rules before merging. This is especially valuable for Dependabot PRs and trivial fixes where waiting for a human to click "merge" after all checks pass is pure waste.

### 4.9 `allow_update_branch`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Docs: Keeping Your Pull Request in Sync](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/keeping-your-pull-request-in-sync-with-the-base-branch) |

Shows an "Update branch" button on PRs when they're behind the base branch.

**Recommendation**: `true`. This button provides a one-click way to bring a PR up to date with the base branch, which is essential when `strict_required_status_checks_policy` is enabled (requiring the branch to be tested against the latest base). Even without strict checks, it's a convenience with zero downside.

### 4.10 `allow_forking`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | [Open Source Licensing Principles](https://opensource.org/osd) |

Controls whether the repository can be forked (for private/internal org repos - public repos are always forkable per GitHub's terms of service).

**Recommendation**: Default this to `false` conceptually, but do not enforce it from the shared framework resource. Public repos are forkable by definition, and personal-account repositories cannot reliably update this field through the same API path as organization repositories. If an owner needs strict forking control, handle it in an owner-specific layer.

### 4.11 `web_commit_signoff_required`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [Developer Certificate of Origin (DCO)](https://developercertificate.org/), [CNCF DCO Requirement](https://github.com/cncf/foundation/blob/main/dco-guidelines.md) |

Requires contributors making commits via the GitHub web interface to sign off on their commits, adding a `Signed-off-by` trailer.

**Recommendation**: `true`. The DCO sign-off is a lightweight contributor agreement used by the Linux kernel, CNCF projects, and many enterprise open-source projects. It certifies the contributor has the right to submit the code. Combined with `required_signatures` in rulesets, this creates a complete chain of authorship verification.

---

## 5. Initialization & Licensing

### 5.1 `auto_init`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | — |

Creates an initial commit with a `README.md` when the repository is created.

**Recommendation**: `true`. An initialized repository with a README is immediately cloneable and visible. GitHub's Community Standards requires a README. The `lifecycle { ignore_changes = [auto_init] }` block ensures this only takes effect on creation and doesn't cause drift.

### 5.2 `license_template`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `"mit"` |
| **Governance** | [OSI Approved Licenses](https://opensource.org/licenses), [GitHub Docs: Licensing a Repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository), [OpenSSF Scorecard: License Check](https://github.com/ossf/scorecard/blob/main/docs/checks.md#license) |

The license applied to the repository on creation.

**Recommendation**: `"mit"` for all public repos. The MIT License is:

- The most popular open-source license on GitHub (~44% of licensed repos)
- Maximally permissive — allows commercial use, modification, and distribution
- Simple and well-understood by legal teams
- Required by OpenSSF Scorecard's License check

MIT is a strong default for broadly reusable public repositories because it signals openness without adding legal complexity. The `lifecycle { ignore_changes = [license_template] }` block prevents Terraform from fighting with manual license changes.

### 5.3 `gitignore_template`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `null` |
| **Governance** | — |

A GitHub-maintained `.gitignore` template applied on repo creation.

**Recommendation**: `null` (not set by default). Each repository's `.gitignore` should be tailored to its specific technology stack and managed as code in the repo itself, not as a one-time initialization artifact. The available templates are too generic for most real projects.

---

## 6. Lifecycle Management

### 6.1 `archived`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `false` |
| **Governance** | [GitHub Docs: Archiving Repositories](https://docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories) |

Archives the repository, making it read-only. Archived repos are clearly marked in the GitHub UI and cannot receive pushes, issues, or PRs.

**Recommendation**: `false` by default. Set to `true` explicitly in a repo's YML when the project is intentionally sunset. Archived repos retain their branch protection, rulesets are skipped (no writes possible), and branches are not managed.

**Important**: GitHub's API does not support un-archiving via the Terraform provider. Archiving is a one-way operation in this framework.

### 6.2 `archive_on_destroy`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [NIST SP 800-53 SC-5: Defense in Depth](https://csf.tools/reference/nist-sp-800-53/r5/sc/sc-5/) |

When `true`, `terraform destroy` will archive the repo instead of deleting it.

**Recommendation**: `true`. This works in concert with `prevent_destroy = true` in the resource lifecycle block to provide **defense in depth**:

1. **`prevent_destroy`** — Stops the Terraform plan from proceeding. This is the primary guard.
2. **`archive_on_destroy`** — Archives instead of deleting *if* destruction somehow proceeds (e.g., someone removes `prevent_destroy` from the lifecycle block and runs destroy).

These two controls protect against **different failure modes**. `prevent_destroy` is a Terraform-level guard that can be removed by editing a `.tf` file. `archive_on_destroy` is an API-level guard that ensures data preservation regardless of Terraform configuration changes. The cost of enabling both is zero; the cost of *not* having the fallback is potentially catastrophic data loss.

**Rationale**: Defense in depth is a core security principle ([NIST SP 800-53 SC-5](https://csf.tools/reference/nist-sp-800-53/r5/sc/sc-5/)). Multiple independent controls are always stronger than a single control, even when the primary control is robust.

---

## 7. Security & Analysis

Secret scanning and push protection remain the secure default, but availability can vary by owner, plan, and provider API behavior. Repositories that cannot have a `security_and_analysis` feature PATCHed can set `unmanaged_security_features` in their repo YAML to emit Terraform `null` for that feature. This is intentionally different from setting `security_and_analysis.<feature>: false`, which manages the feature as disabled and still sends a provider PATCH. Per [OWASP A02:2021 (Cryptographic Failures)](https://owasp.org/Top10/A02_2021-Cryptographic_Failures/), repositories handling credentials or configuration should use secret detection whenever the account can support it.

### 7.1 `vulnerability_alerts`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Governance** | [GitHub Docs: Dependabot Alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts), [OpenSSF Scorecard: Vulnerabilities Check](https://github.com/ossf/scorecard/blob/main/docs/checks.md#vulnerabilities) |

Enables Dependabot vulnerability alerts for known CVEs in dependencies.

**Recommendation**: `true` for all repos. Dependabot alerts are free, automatic, and essential. Ignoring known vulnerabilities in dependencies is the #6 item on the [OWASP Top 10 (A06:2021)](https://owasp.org/Top10/A06_2021-Vulnerable_and_Outdated_Components/). Enabling them is one of the clearest low-friction security defaults a repository can have.

### 7.2 `dependabot_security_updates`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` |
| **Resource** | `github_repository_dependabot_security_updates` |
| **Governance** | [GitHub Docs: Dependabot Security Updates](https://docs.github.com/en/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates) |

Enables Dependabot to automatically create PRs to fix vulnerable dependencies.

**Recommendation**: `true` for all non-archived repos. Automated security patches paired with auto-merge and branch protection create a continuous patching pipeline with zero manual intervention for safe upgrades. This is a core tenet of [SLSA Level 1](https://slsa.dev/spec/v1.0/levels#build-l1).

### 7.3 `advanced_security`

| | |
|---|---|
| **Type** | `bool` or `null` |
| **Default** | `null` (not set) |
| **Governance** | [GitHub Docs: GHAS](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security) |

GitHub Advanced Security (GHAS) is a paid feature for private/internal repos. For public repos, all GHAS features are free and automatically available.

**Recommendation**: `null` for all repos. Public repos get these features for free without enabling this flag. Private repos on a free plan cannot enable it. Setting it to `null` avoids provider errors while allowing the individual security features to be configured independently.

### 7.4 `code_security`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` (all visibilities) |
| **Governance** | [GitHub Docs: Code Security](https://docs.github.com/en/code-security) |

Enables the code security overview and recommendations for the repository.

**Recommendation**: `true` universally. Code security is a free feature that surfaces dependency vulnerabilities, code scanning alerts, and secret scanning results in a unified view. There is no cost or downside to enabling it.

### 7.5 `secret_scanning`

| | |
|---|---|
| **Type** | `bool` or unmanaged via `unmanaged_security_features` |
| **Default** | `true` when baseline and capability permit; unmanaged when listed in repo YAML |
| **Governance** | [GitHub Docs: Secret Scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning), [OWASP A02:2021: Cryptographic Failures](https://owasp.org/Top10/A02_2021-Cryptographic_Failures/) |

Scans repository contents for known secret patterns (API keys, tokens, certificates).

**Recommendation**: `true` wherever the owner/plan/API path supports it. If a repository is rejected when the provider PATCHes secret scanning, set `unmanaged_security_features: ["secret_scanning"]` for that repository so Terraform omits the feature instead of managing it as disabled. Leaked secrets in public repos are actively scraped by automated tools within seconds of exposure. Private repos are equally at risk from insider threats and compromised CI/CD pipelines.

### 7.6 `secret_scanning_push_protection`

| | |
|---|---|
| **Type** | `bool` or unmanaged via `unmanaged_security_features` |
| **Default** | `true` when baseline and capability permit; unmanaged when listed in repo YAML |
| **Governance** | [GitHub Docs: Push Protection](https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection) |

Blocks pushes that contain known secret patterns *before* they enter the repository.

**Recommendation**: `true` wherever the owner/plan/API path supports it. If push protection cannot be PATCHed for a repository, set `unmanaged_security_features: ["secret_scanning_push_protection"]` so Terraform omits it. This is the most critical secret scanning feature because it prevents secrets from ever being committed, rather than detecting them after the fact. Once a secret is in git history, it requires history rewriting to fully remove.

### 7.7 `secret_scanning_ai_detection`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` (all visibilities) |
| **Governance** | [GitHub Docs: AI-Powered Secret Detection](https://docs.github.com/en/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/generic-secret-detection/about-the-detection-of-generic-secrets-with-secret-scanning) |

Uses AI/ML models to detect secrets that don't match known provider patterns (e.g., custom API keys, internal tokens, hardcoded passwords).

**Recommendation**: `true` for all repos. AI detection catches the "long tail" of secrets that pattern-based scanning misses — custom API keys, internal tokens, hardcoded passwords, and other non-standard credential formats. This feature is now available for all repository visibilities.

### 7.8 `secret_scanning_non_provider_patterns`

| | |
|---|---|
| **Type** | `bool` |
| **Default** | `true` (all visibilities) |
| **Governance** | [GitHub Docs: Non-Provider Patterns](https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns#supported-secrets) |

Scans for secret patterns that aren't tied to specific service providers (e.g., generic private keys, HTTP basic auth credentials, connection strings).

**Recommendation**: `true` for all repos. Non-provider patterns catch infrastructure secrets like database connection strings and private keys that provider-specific patterns would miss. Combined with AI detection, this provides comprehensive secret coverage across all repository visibilities.

---

## 8. GitHub Pages

| | |
|---|---|
| **Type** | Nested object (optional) |
| **Default** | `null` (Pages not enabled) |
| **Governance** | [GitHub Docs: GitHub Pages](https://docs.github.com/en/pages) |

GitHub Pages hosts static websites directly from a repository. Configuration includes:

- **`build_type`**: `"workflow"` (GitHub Actions) or `"legacy"` (Jekyll). `"workflow"` is recommended as it provides full control over the build process.
- **`source.branch`**: The branch to deploy from (typically `"main"`).
- **`source.path`**: The directory within the branch (`"/"` or `"/docs"`).
- **`cname`**: Custom domain (optional).

**Recommendation**: Only enable for repos that genuinely serve a website (documentation sites, project landing pages). Currently only `proxmox-terraform-framework` uses Pages. The `workflow` build type is preferred over `legacy` because it:

- Supports any static site generator (not just Jekyll)
- Provides CI/CD visibility in the Actions tab
- Allows custom build steps and validation

---

## 9. Templates & Forking

### Template Configuration

| | |
|---|---|
| **Type** | Nested object (optional) |
| **Default** | `null` |

Used when creating a repository from a template. Includes `owner`, `repository`, and `include_all_branches`.

**Recommendation**: Only set when explicitly creating a repo from a template. `include_all_branches` defaults to `false` because template repos typically only need the default branch's content — additional branches are development artifacts of the template, not the consumer.

### Fork Configuration

| | |
|---|---|
| **Type** | `fork` (bool), `source_owner` (string), `source_repo` (string) |
| **Default** | `fork = false` |

Used when the repository is a fork of an upstream repository.

**Recommendation**: Only set when the repo is genuinely a fork. The framework correctly gates `source_owner` and `source_repo` behind `fork = true` to prevent orphaned configuration.

---

## 10. Branch Protection via Rulesets

### 10.1 Why Rulesets over Branch Protection Rules

GitHub offers three mechanisms for branch protection:

| Feature | `branch_protection` (GraphQL v4) | `branch_protection_v3` (REST) | `repository_ruleset` (REST, newer) |
|---------|-----------------------------------|-------------------------------|--------------------------------------|
| **Status** | Legacy | Legacy | **Recommended** |
| **Multi-rule per ref** | No | No | Yes (aggregate, most restrictive wins) |
| **Tag protection** | No | No | Yes |
| **Push protection** | No | No | Yes |
| **Evaluate mode** | No | No | Yes (dry-run) |
| **Merge queue** | No | No | Yes |
| **Code scanning gates** | No | No | Yes |
| **File restrictions** | No | No | Yes |

**Decision**: This framework uses `github_repository_ruleset` exclusively. GitHub's [official documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) states: *"Rulesets are the recommended way to manage branch and tag protections."* Rulesets replace branch protection rules with a more powerful, composable model.

### 10.2 Ruleset: Default Branch Protection

**Name**: `Default Branch Protection`
**Target**: `branch`
**Enforcement**: `active`
**Scope**: `~DEFAULT_BRANCH` (the repo's default branch, typically `main`)

This ruleset protects the integrity of the default branch with fundamental safety rules.

#### 10.2.1 `creation`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [SLSA: Source Integrity](https://slsa.dev/spec/v1.0/requirements#source-requirements) |

Prevents anyone without bypass permissions from creating refs matching the condition (i.e., creating a new branch named `main`). This prevents branch confusion attacks where an attacker creates a branch with the same name as the default branch.

#### 10.2.2 `deletion`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [GitHub Docs: Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#restrict-deletions) |

Prevents deletion of the default branch. Deleting the default branch is catastrophic and effectively destroys the repository's primary timeline.

#### 10.2.3 `non_fast_forward`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [Git Project: Force Push](https://git-scm.com/docs/git-push#Documentation/git-push.txt---force), [SLSA: Source Integrity](https://slsa.dev/spec/v1.0/requirements#source-requirements) |

Prevents force pushes to the default branch. Force pushing rewrites history, destroys commit signatures, breaks `git bisect`, and can silently remove commits. This is the single most important branch protection rule.

**Rationale**: Force pushing to a shared branch is universally considered a destructive anti-pattern. The SLSA framework specifically calls out history integrity as a source requirement. Even for a solo developer, force-push protection prevents accidents.

#### 10.2.4 `required_linear_history`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [Conventional Commits](https://www.conventionalcommits.org/), [Git Bisect Documentation](https://git-scm.com/docs/git-bisect) |

Requires a linear commit history on the default branch (no merge commits).

**Recommendation**: `true`. Combined with squash-only merging, this guarantees the default branch is a clean, linear sequence of atomic changes. Benefits:

- `git log --oneline` reads as a changelog
- `git bisect` works optimally (no merge nodes to confuse the binary search)
- Every commit on `main` represents a complete, tested state

#### 10.2.5 `required_signatures`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [Git Commit Signing](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work), [GitHub Docs: Commit Signature Verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification), [OpenSSF Scorecard: Signed-Releases](https://github.com/ossf/scorecard/blob/main/docs/checks.md#signed-releases) |

Requires all commits on the default branch to have verified GPG, SSH, or S/MIME signatures.

**Recommendation**: `true`. Commit signing provides:

- **Non-repudiation**: Proves who actually authored a commit (git's `author` field is trivially forgeable)
- **Tamper detection**: Signed commits cannot be modified without invalidating the signature
- **Supply chain security**: Part of SLSA Level 2+ requirements

Signed commits display a green "Verified" badge and provide a visible, low-friction signal that the repository treats authorship integrity seriously.

#### 10.2.6 `update`

| | |
|---|---|
| **Value** | `false` |
| **Governance** | — |

When `true`, prevents *all* pushes to the matching branches (not just force pushes). This would make the branch completely read-only, which is only appropriate for archived branches or release branches with strict promotion workflows.

**Recommendation**: `false`. The default branch needs to receive squash-merged PRs. Blocking all updates would prevent any development workflow.

### 10.3 Ruleset: Pull Request Gate

**Name**: `Pull Request Gate`
**Target**: `branch`
**Enforcement**: `active`
**Scope**: `~DEFAULT_BRANCH`
**Bypass**: Repository Admins (`actor_id: 5`, `actor_type: RepositoryRole`, `bypass_mode: always`)

This ruleset enforces the pull request workflow on the default branch.

#### 10.3.1 `allowed_merge_methods`

| | |
|---|---|
| **Value** | `["squash"]` |
| **Governance** | See [4.1 allow_squash_merge](#41-allow_squash_merge) |

Restricts the merge methods available via the PR merge button. Set to `["squash"]` only, reinforcing the squash-only merge strategy at the ruleset level (belt-and-suspenders with the repository-level `allow_merge_commit = false`).

#### 10.3.2 `dismiss_stale_reviews_on_push`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [GitHub Docs: Dismissing Stale Reviews](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/dismissing-a-pull-request-review) |

Automatically dismisses existing approvals when new commits are pushed to the PR.

**Recommendation**: `true`. Without this, a PR could be approved, then have its code completely changed, and still merge with the stale approval. This is a well-known attack vector in supply chain security — the [XZ Utils backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) exploited exactly this pattern (approved PR, then later force-pushed malicious code).

#### 10.3.3 `require_code_owner_review`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [GitHub Docs: CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) |

Requires at least one approving review from a designated code owner (defined in `.github/CODEOWNERS`).

**Recommendation**: `true` when a repository actually has maintainers to assign. A CODEOWNERS file formalizes ownership and creates an audit trail, but the concrete owners should be supplied per owner context rather than hard-coded into shared framework guidance.

#### 10.3.4 `require_last_push_approval`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [GitHub Docs: Last Push Approval](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-a-pull-request-before-merging) |

Requires that the most recent push to the PR be approved by someone other than the pusher.

**Recommendation**: `true`. This prevents a scenario where a developer pushes a malicious commit as the *last* commit in a PR (after the review), then merges before anyone notices. Combined with `dismiss_stale_reviews_on_push`, this creates airtight review coverage.

**Solo developer note**: This rule is bypassed by the admin bypass actor, which is necessary for a single-maintainer account. The rule's presence still demonstrates to employers that you understand the principle.

#### 10.3.5 `required_approving_review_count`

| | |
|---|---|
| **Value** | `1` |
| **Governance** | [Google Engineering Practices: Code Review](https://google.github.io/eng-practices/review/) |

The minimum number of approving reviews required before a PR can be merged.

**Recommendation**: `1`. For a solo developer account, this is bypassed via the admin bypass actor. Setting it to `1` (rather than `0`) demonstrates the configuration is *ready* for team use. Setting it higher than `1` would be theater — you'd always need to bypass it.

#### 10.3.6 `required_review_thread_resolution`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | — |

Requires all review conversation threads to be resolved before merging.

**Recommendation**: `true`. Unresolved review threads indicate open questions or concerns. Merging with unresolved threads means merging code that hasn't been fully vetted. This is a quality gate — every piece of feedback must be explicitly acknowledged (resolved or addressed).

### 10.4 Ruleset: Release Tag Protection

**Name**: `Release Tag Protection`
**Target**: `tag`
**Enforcement**: `active`
**Scope**: `~ALL` (every tag in the repository)
**Bypass**: Repository Admins (`actor_id: 5`, `actor_type: RepositoryRole`, `bypass_mode: always`)

Protects every tag from silent replacement, deletion, or unsigned creation. Published release tags (typically produced by release-please, `git tag -s`, or a release workflow) are high-value supply-chain artefacts — downstream consumers pin by tag, so a silently re-pointed tag is indistinguishable from a compromise.

Tag creation is intentionally left unrestricted so the normal release workflow works without bypass. The three enabled rules below close the drift vectors that matter.

#### 10.4.1 `deletion`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [SLSA: Source Integrity](https://slsa.dev/spec/v1.0/requirements#source-requirements), [OpenSSF Scorecard: Signed-Releases](https://github.com/ossf/scorecard/blob/main/docs/checks.md#signed-releases) |

Prevents deletion of any tag without bypass. Deleting a published release tag breaks every downstream consumer that pinned to it and destroys the audit trail that links a released artefact to its source commit.

Admin bypass is deliberate: the owner may need to delete a tag that accidentally embedded a leaked secret, was cut from the wrong SHA, or predates a public release decision.

#### 10.4.2 `non_fast_forward`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [Git Project: Tag Immutability](https://git-scm.com/book/en/v2/Git-Basics-Tagging), SLSA source integrity |

Prevents force-updating a tag to point at a different commit. Without this rule, `git tag -f v1.2.3 <new-sha> && git push --force origin v1.2.3` silently re-points the tag, and consumers that re-pull the same tag name receive different bytes than before. This is the classic supply-chain attack vector for tag-based distribution.

#### 10.4.3 `required_signatures`

| | |
|---|---|
| **Value** | `true` |
| **Governance** | [Git Commit Signing](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work), [OpenSSF Scorecard: Signed-Releases](https://github.com/ossf/scorecard/blob/main/docs/checks.md#signed-releases), [SLSA Level 2](https://slsa.dev/spec/v1.0/levels#build-l2) |

Requires the tag (and the commit it points at) to carry a verified GPG, SSH, or S/MIME signature. Combined with `deletion` and `non_fast_forward`, this gives every tag a cryptographically verifiable provenance chain that consumers can validate offline.

**Release-please / release-bot note**: release-automation bots must be configured to sign the tags they produce, either via a committed signing key or a GitHub App identity. An unsigned bot-created tag will be rejected by this rule. This is intentional — bot-authored releases carry the same supply-chain weight as human-authored ones.

### 10.5 Ruleset: Bypass Actors

The Pull Request Gate and Release Tag Protection rulesets include a bypass actor for Repository Admins:

```yaml
bypass_actors:
  - actor_id: 5
    actor_type: RepositoryRole
    bypass_mode: always
```

**Actor ID `5`** = Repository Admin role. This is essential for a solo developer account — without it, no one could merge PRs (since you can't approve your own PR) and no one could perform emergency tag remediation. The bypass is scoped to the Pull Request Gate and Release Tag Protection; the Default Branch Protection ruleset has **no bypass actors**, meaning even admins cannot force-push or delete the default branch.

**Available Actor IDs**:

| ID | Role |
|----|------|
| 1 | Organization Admin |
| 2 | Maintain |
| 4 | Write |
| 5 | Admin |

**Bypass Modes**:

- `always`: Can bypass for both direct pushes and PR merges
- `pull_request`: Can only bypass during PR merges
- `exempt`: Exempt from the rule entirely

### 10.6 Ruleset: Conditions

The Default Branch Protection and Pull Request Gate rulesets target `~DEFAULT_BRANCH` with no exclusions:

```yaml
conditions:
  include:
    - "~DEFAULT_BRANCH"
  exclude: []
```

`~DEFAULT_BRANCH` is a GitHub magic ref that always resolves to whatever the repo's default branch is (typically `main`). This is preferred over hardcoding `refs/heads/main` because:

- It automatically adapts if the default branch is renamed
- It works across repos that may use different default branch names
- `~ALL` is available to protect all branches, but would be overly restrictive

The Release Tag Protection ruleset targets `~ALL` with no exclusions:

```yaml
conditions:
  include:
    - "~ALL"
  exclude: []
```

`~ALL` on a tag-target ruleset matches every tag. Repositories that want to restrict the ruleset to a subset (e.g., only `v*` tags) should override `rules[*].conditions` in their YAML.

### 10.7 Rules Not Enabled by Default (and Why)

| Rule | Why Not Default | When to Enable |
|------|----------------|----------------|
| `required_status_checks` | No CI/CD workflows defined yet globally | Per-repo when CI pipelines exist |
| `required_code_scanning` | Requires CodeQL or other scanning tool setup | When code scanning Actions are configured |
| `required_deployments` | No deployment environments defined | When repos have deployment pipelines |
| `merge_queue` | Overkill for solo developer | When multiple contributors submit concurrent PRs |
| `copilot_code_review` | Requires GitHub Copilot subscription | When Copilot is available |
| `branch_name_pattern` | Enterprise-only feature | When GitHub Enterprise is in use |
| `commit_message_pattern` | Enterprise-only feature | When GitHub Enterprise is in use |
| `commit_author_email_pattern` | Enterprise-only feature | When GitHub Enterprise is in use |
| `committer_email_pattern` | Enterprise-only feature | When GitHub Enterprise is in use |
| `tag_name_pattern` | No tag-based release workflow yet | When semantic versioning releases are adopted |
| `file_path_restriction` | Push-target only, requires Team plan | When sensitive file paths need protection |
| `file_extension_restriction` | Push-target only, requires Team plan | When binary/large file extensions should be blocked |
| `max_file_size` | Push-target only, requires Team plan | When large file uploads should be prevented |
| `max_file_path_length` | Push-target only, requires Team plan | When path length limits are needed |

---

## 11. Terraform Resource Lifecycle

The `github_repository` resource includes:

```hcl
lifecycle {
  prevent_destroy = true
  ignore_changes  = [auto_init, license_template]
}
```

- **`prevent_destroy = true`**: Prevents accidental repository deletion via `terraform destroy`. Repositories contain irreplaceable git history — deletion should never be a side effect of infrastructure operations.
- **`ignore_changes = [auto_init, license_template]`**: These are creation-time-only settings. After the initial `terraform apply`, changes to the README or LICENSE file within the repo should not cause Terraform drift. Without this, Terraform would try to "re-initialize" already-populated repos.

---

## 12. Properties Intentionally Omitted

These `github_repository` properties exist in the provider but are intentionally not managed:

| Property | Reason for Omission |
|----------|---------------------|
| `private` | **Deprecated** — superseded by `visibility` |
| `default_branch` | **Deprecated** — use `github_branch_default` resource instead |
| `has_downloads` | **Deprecated** — controls a legacy GitHub feature |
| `ignore_vulnerability_alerts_during_read` | **Deprecated** — now handled automatically by the provider. Scheduled for removal from the framework in a future cleanup pass. |

---

## 13. Per-Repository Deviation Policy

The framework's power comes from strong defaults with explicit opt-outs. Deviations from defaults should be:

1. **Minimal**: Only specify what's different
2. **Justified**: Add a YAML comment explaining *why*
3. **Auditable**: The diff between a repo's YML and the defaults is the repo's "deviation surface"

This root module does not track live repository YAML definitions. Runner
repositories provide the `terraform/repos/{public,private}/` overlays and own
their deviation records. Keep deviation tables in the runner or inventory
repository that carries the YAML, not in this reusable framework.

---

## 14. Input Validation

| | |
|---|---|
| **Governance** | [OWASP Input Validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html), [NIST SP 800-53 SI-10: Information Input Validation](https://csf.tools/reference/nist-sp-800-53/r5/si/si-10/) |

All inputs at system boundaries must be validated. This framework ingests YAML files as its primary input, which are then processed by Terraform and sent to the GitHub API. Invalid inputs (e.g., `visibility: "banana"`, `enforcement: "off"`) could produce undefined behavior or silent misconfigurations.

The framework enforces validation at two levels:

### 14.1 Variable-Level Validation

Terraform `validation` blocks on input variables enforce constraints before the plan is computed:

- **`github_owner`**: Must match GitHub username format (alphanumeric and hyphens, cannot start/end with hyphen).
- **`github_token`**: Marked `sensitive = true` to prevent exposure in plan output or logs.

### 14.2 Plan-Time Checks

Terraform `check` blocks validate computed locals during `terraform plan`, catching YAML misconfigurations before they reach the GitHub API:

- **`validate_repo_visibility`**: All repository `visibility` values must be one of `public`, `private`, or `internal`.
- **`validate_ruleset_enforcement`**: All ruleset `enforcement` values must be one of `active`, `evaluate`, or `disabled`.
- **`validate_public_repos_have_description`**: All public repositories must have a non-empty `description` (per Section 2.2).

**Rationale**: The GitHub API may silently accept some invalid values or reject them with unhelpful error messages. Validating at the Terraform layer provides clear, actionable error messages before any API calls are made. This follows the principle of **fail fast** — catching errors as early as possible in the pipeline.

---

## 15. Infrastructure Security

This section covers security controls for the Terraform framework itself — the infrastructure that manages the infrastructure.

### 15.1 Version Control Hygiene (`.gitignore`)

| | |
|---|---|
| **Governance** | [OWASP: Sensitive Data Exposure](https://owasp.org/Top10/A02_2021-Cryptographic_Failures/), [OpenSSF Scorecard: Binary-Artifacts](https://github.com/ossf/scorecard/blob/main/docs/checks.md#binary-artifacts) |

This repository uses a **deny-all** `.gitignore` strategy: everything is ignored by default (`**`), and only explicitly allowlisted files are tracked. This prevents accidental commits of sensitive files (`.env`, state files, credentials) or build artifacts.

**Critical allowlist rules**:

- `!/terraform/repos/*.yml` and `!/terraform/repos/*.yaml` — Repository definition files (the framework's primary input).
- `!/terraform/*.tf` — Terraform configuration files.
- `!/DESIGN.md` — This governing design document.
- Standard repo files (`LICENSE`, `README.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`).

**Explicitly excluded** (not in allowlist):

- `.env` — Contains the GitHub Personal Access Token. Must never be committed.
- `terraform.tfstate` / `terraform.tfstate.backup` — State files contain sensitive data in plaintext (API tokens, resource metadata).
- `terraform.tfvars` — Intentionally excluded to prevent accidental credential commits. Sensitive variables must be provided via environment variables or `.env`. Only `terraform.auto.tfvars` is allowlisted for non-sensitive configuration overrides.
- `.terraform/` — Provider binaries and plugin cache.

**Rationale**: The deny-all approach inverts the typical `.gitignore` model. Instead of trying to enumerate everything that *shouldn't* be committed (a losing game), it enumerates only what *should* be committed. This is the more secure default — new files are ignored unless explicitly approved.

### 15.2 Credential Management

| | |
|---|---|
| **Governance** | [OWASP A07:2021: Identification and Authentication Failures](https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/), [NIST SP 800-53 IA-5: Authenticator Management](https://csf.tools/reference/nist-sp-800-53/r5/ia/ia-5/) |

The framework requires a GitHub Personal Access Token (PAT) for API authentication. Credential handling follows these principles:

1. **`github_token` is marked `sensitive = true`** in the variable definition, preventing it from appearing in `terraform plan` output or state file diffs.
2. **Credentials are provided via environment variables** (sourced from `.env`), not via `terraform.tfvars` or command-line arguments.
3. **`.env` is excluded from version control** by the deny-all `.gitignore` strategy — it is never allowlisted.
4. **`terraform.tfvars` is excluded from version control** to prevent the natural instinct of adding sensitive values to the conventional variable file.

**Recommendation**: Use environment variables (`TF_VAR_github_token`) or a secrets manager. Never store credentials in files that could be committed, even accidentally.

### 15.3 Terraform State Security

| | |
|---|---|
| **Governance** | [NIST SP 800-53 SC-28: Protection of Information at Rest](https://csf.tools/reference/nist-sp-800-53/r5/sc/sc-28/) |

Terraform state files contain the full configuration of all managed resources, including sensitive values like API tokens (post-apply). The current configuration uses **local state** (S3 backend is commented out in `00-providers.tf`).

**Current state**: Local backend (file-based).

**Security implications of local state**:

- No encryption at rest (state file is plaintext on disk)
- No state locking (risk of concurrent modification in CI/CD)
- No access control beyond filesystem permissions
- State contains the GitHub PAT in plaintext after `terraform apply`

**Recommended remediation**: Enable the S3 backend with:

- Server-side encryption (SSE-S3 or SSE-KMS)
- State locking via S3-native locking (DynamoDB is no longer required with S3's native lock support)
- Bucket policy restricting access to the CI/CD IAM role
- Versioning enabled for state rollback capability

This is a known limitation documented for future remediation when the S3 backend configuration is finalized.

### 15.4 Terraform Output Security

| | |
|---|---|
| **Governance** | [NIST SP 800-53 SI-11: Error Handling](https://csf.tools/reference/nist-sp-800-53/r5/si/si-11/) |

The `locals_debug` output is marked `sensitive = true` to prevent exposure of repository configurations, security settings, ruleset enforcement levels, and bypass actors in Terraform plan/apply output or CI/CD logs.

**Recommendation**: Debug outputs should only exist during development. In production CI/CD pipelines, consider removing debug outputs entirely or gating them behind a variable flag. Terraform's `sensitive` marker prevents the values from appearing in CLI output but does **not** encrypt them in the state file.

### 15.5 Provider Version Pinning

| | |
|---|---|
| **Governance** | [SLSA: Build Integrity](https://slsa.dev/spec/v1.0/requirements#build-requirements), [OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies) |

All provider versions are **exact-pinned** (e.g., `version = "6.12.1"`, not `version = "~> 6.12"`):

- **`integrations/github`**: `6.12.1`
- **`hashicorp/time`**: `0.12.1`
- **Terraform itself**: `1.15.4` (via `required_version`)

**Rationale**: Exact pinning prevents supply chain attacks where a compromised provider version is automatically pulled during `terraform init`. Range constraints (`~>`, `>=`) allow automatic upgrades that could introduce malicious code. Exact pins require explicit, reviewable version bumps — each upgrade is a deliberate, auditable decision.

This aligns with [SLSA Level 3](https://slsa.dev/spec/v1.0/levels#build-l3) requirements for hermetic, reproducible builds and the OpenSSF Scorecard's [Pinned-Dependencies check](https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies).

---

## 16. Environment Protection Rules

GitHub deployment environments give a workflow job a named gate it must pass before running. The framework manages environments via the `environments:` block in each repo's YAML and surfaces every environment-protection knob the GitHub API supports today.

This section documents what each knob does, what default the framework picks when the YAML omits it, and — critically — which knobs are billing-restricted on **private repositories on the GitHub Free plan**. The Free-tier limits are not exposed by the GitHub API as feature flags; they manifest only at create time as a generic 422 ("Failed to create the environment protection rule. Please ensure the billing plan supports the required reviewers protection rule"). Worse, **some restricted settings are silently ignored rather than rejected**: the create succeeds and returns a different value than the one requested. That is why the framework explicitly tracks the matrix below instead of trusting the API to refuse what it can't honour.

**Governing reference**: [GitHub Docs: Using environments for deployment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment).

### 16.1 What environments are managed

For each entry in a repo YAML's `environments:` map, the framework reconciles:

- the environment itself (`github_repository_environment`),
- the deployment-branch policies (custom branch patterns) that the env scopes deployments to (`github_repository_environment_deployment_policy`),
- environment-level variables and secrets, when declared (`github_actions_environment_variable`, `github_actions_environment_secret`).

Environments not listed in the YAML are not managed. Removing an environment from the YAML triggers a destroy on next apply.

### 16.2 `wait_timer`

| | |
|---|---|
| **Type** | `int` (minutes) |
| **Default** | `0` |
| **Range** | `0`–`43200` (30 days), validated by a precondition on the resource |
| **Free-plan availability** | Public: yes. Private: **paid plan only** when non-zero. |

Delays the start of any deployment to this environment by the configured number of minutes.

**Recommendation**: `0` unless the environment is one where a cooldown is genuinely useful (e.g. a destructive operation where a slow-down window gives a human time to abort). On private repos on Free, set this to `0` regardless of intent — non-zero values are silently ignored or 422 the apply.

### 16.3 `can_admins_bypass`

| | |
|---|---|
| **Type** | `bool` |
| **Default (framework)** | inherited from the YAML; the GitHub API default is `true` |
| **Free-plan availability** | Public: yes. Private: **paid plan only**. |

Controls whether repository admins can bypass the environment's protection rules.

**Critical caveat for private + Free**: setting `can_admins_bypass: false` on a private repo on Free **does not error and does not take effect**. The GitHub API accepts the create with `false`, but the resulting environment reports `can_admins_bypass: true`. Terraform's next refresh sees the drift and proposes to flip it back to `false`, and the next apply 422s on the billing rule.

**Recommendation**:

- Public repos: set the value you actually want; both work.
- Private repos on a paid plan: set the value you actually want; both work.
- **Private repos on Free: always set `can_admins_bypass: true`** to match the value GitHub will hold regardless of what you ask for. Anything else creates permanent drift.

### 16.4 `prevent_self_review`

| | |
|---|---|
| **Type** | `bool` |
| **Default (framework)** | inherited from the YAML; the GitHub API default is `false` |
| **Free-plan availability** | Effectively only meaningful when **required reviewers** are configured (see 16.5), which is itself paid-only on private. |

When `true`, the user who triggered the deployment cannot also approve it.

**Recommendation**: `false` (or omit) on every environment that has no required reviewers — there is no self-review to prevent. Set to `true` only on environments that genuinely run a multi-reviewer flow.

### 16.5 Required reviewers

| | |
|---|---|
| **Type** | `reviewers: { users: [...], teams: [...] }` |
| **Default (framework)** | omitted (no reviewer gate) |
| **Free-plan availability** | Public: yes. Private: **paid plan only** (Team / Enterprise / GHAS). |

Required reviewers force a named user or team to approve a deployment before the workflow proceeds.

This is the single biggest paid-plan feature on environments. On private repos on Free, declaring `reviewers:` with any users or teams returns a 422 "Failed to create the environment protection rule" at apply time, and the environment is not created.

**Recommendation**:

- Public repos: use as needed.
- Private repos on a paid plan: use as needed.
- **Private repos on Free: omit `reviewers:` entirely**. Use deployment branch policies and/or `wait_timer: 0` (omit) gates instead. Reviewer enforcement on a solo-maintainer private repo is theatre regardless of plan, since the only person who could approve is the same one who dispatches.

### 16.6 `deployment_branch_policy`

| | |
|---|---|
| **Type** | `{ protected_branches: bool, custom_branch_policies: bool }` |
| **Default (framework)** | omitted (any branch can deploy) |
| **Free-plan availability** | Both flavours work on every plan and every visibility. |

Controls which refs can target this environment. Mutually exclusive: at most one of the two booleans may be `true`.

- `protected_branches: true` — only branches that have at least one ruleset / branch-protection rule may deploy.
- `custom_branch_policies: true` — only refs matching one of the patterns in the sibling `branch_policies:` list may deploy. Patterns use GitHub's branch-pattern syntax (e.g. `release/stage/*`, `main`).

A precondition on the resource fails the plan if both are `true`.

**Recommendation**: this is the **primary deployment gate available on every plan**. On Free private repos especially, lean on `deployment_branch_policy` to restrict which refs trigger which environments, since reviewer / wait-timer / admin-bypass enforcement are paid features.

### 16.7 Free-plan billing limits on private repos

Summary table of what works where:

| Knob | Public (any plan) | Private + Free | Private + paid |
|---|---|---|---|
| `wait_timer = 0` | ✓ | ✓ | ✓ |
| `wait_timer > 0` | ✓ | ✗ silently dropped or 422 | ✓ |
| Required reviewers | ✓ | ✗ 422 at create | ✓ |
| `can_admins_bypass = true` | ✓ | ✓ | ✓ |
| `can_admins_bypass = false` | ✓ | ✗ silently kept as `true` | ✓ |
| `prevent_self_review` | only meaningful with reviewers | only meaningful with reviewers | ✓ |
| `deployment_branch_policy.protected_branches` | ✓ | ✓ | ✓ |
| `deployment_branch_policy.custom_branch_policies` | ✓ | ✓ | ✓ |
| Environment variables | ✓ | ✓ | ✓ |
| Environment secrets | ✓ | ✓ | ✓ |

When in doubt, the rule for **private + Free** is: **only `wait_timer = 0`, `deployment_branch_policy`, env vars, and env secrets actually enforce**. Set `can_admins_bypass: true` and omit reviewers and non-zero wait timers. Anything else is either silently ignored or fails apply with the generic 422.

Runner-owned repo YAMLs that fall under that constraint should reflect this
directly with `can_admins_bypass: true` on private Free-plan environments and
a local comment explaining why.
