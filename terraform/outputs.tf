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
