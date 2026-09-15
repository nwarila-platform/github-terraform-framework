output "locals_debug" {
  description = "All computed locals for debugging. Marked sensitive to prevent exposure in CI/CD logs."
  sensitive   = true
  value = {
    all_repositories = local.all_repositories
    branch_rulesets  = local.branch_rulesets
  }
}

output "all_repositories" {
  description = "Computed repository map. Non-sensitive so terraform test assertions can inspect normalized values."
  value       = local.all_repositories
}

output "branch_rulesets" {
  description = "Computed branch rulesets map. Non-sensitive so terraform test assertions can inspect ruleset counts and values."
  value       = local.branch_rulesets
}

output "validation_errors" {
  description = "Aggregated framework validation errors. Empty when configuration is valid."
  value       = nonsensitive(local.global_validation_errors)
}

output "security_capability_gap_preview" {
  description = "List of capability-gap preview messages."
  value       = local.security_capability_gap_preview
}

output "provider_gap_desired_state" {
  description = "Closed desired-state projection consumed by the GET-only provider-gap verifier."
  value = {
    schema_version             = 1
    github_owner               = var.github_owner
    github_is_organization     = var.github_is_organization
    organization_provider_gaps = var.provider_gaps
    repositories = {
      for name, repository in local.all_repositories : name => {
        name          = repository.name
        visibility    = repository.visibility
        archived      = repository.archived
        provider_gaps = repository.provider_gaps
      }
    }
  }
}
