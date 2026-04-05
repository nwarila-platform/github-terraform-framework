output "locals_debug" {
  description = "All computed locals for debugging. Marked sensitive to prevent exposure in CI/CD logs."
  sensitive   = true
  value = {
    all_repositories = local.all_repositories
    branch_rulesets  = local.branch_rulesets
    # add more locals here as you create them
  }
}
