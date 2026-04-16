output "locals_debug" {
  description = "All computed locals for debugging. Marked sensitive to prevent exposure in CI/CD logs."
  sensitive   = true
  value = {
    all_repositories = local.all_repositories
    branch_rulesets  = local.branch_rulesets
    # add more locals here as you create them
  }
}

output "validation_errors" {
  description = "Aggregated framework validation errors. Empty when configuration is valid. Exposed so terraform test run blocks can assert on len() == 0 in positive cases."
  value       = local.global_validation_errors
}

output "security_capability_gap_preview" {
  description = "List of capability-gap preview messages. Populated whenever var.security_baseline demands a feature not supported by var.github_security_capabilities. In strict mode these also appear in validation_errors. In compatibility mode they surface only via check.security_baseline_preview."
  value       = local.security_capability_gap_preview
}
