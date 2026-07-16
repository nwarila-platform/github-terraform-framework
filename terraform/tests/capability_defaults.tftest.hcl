mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner     = "test-owner"
  github_auth_mode = "token"
  github_token     = "fake-token-for-unit-tests"
  repo_yaml_path   = "tests/fixtures/good-empty"
}

run "default_capability_and_baseline_matrices_are_free_only" {
  command = plan

  assert {
    condition = (
      var.github_security_capabilities.public.secret_scanning &&
      var.github_security_capabilities.public.secret_scanning_push_protection &&
      !var.github_security_capabilities.private.secret_scanning &&
      !var.github_security_capabilities.private.secret_scanning_push_protection &&
      !var.github_security_capabilities.internal.secret_scanning &&
      !var.github_security_capabilities.internal.secret_scanning_push_protection
    )
    error_message = "default secret-scanning capabilities must be public-only"
  }

  assert {
    condition = alltrue(flatten([
      for vis in ["public", "private", "internal"] : [
        !var.github_security_capabilities[vis].advanced_security,
        !var.github_security_capabilities[vis].code_security,
        !var.github_security_capabilities[vis].secret_scanning_ai_detection,
        !var.github_security_capabilities[vis].secret_scanning_non_provider_patterns,
      ]
    ]))
    error_message = "all advanced/code/extra capabilities must default false"
  }

  assert {
    condition = alltrue(flatten([
      for vis in ["public", "private", "internal"] : [
        for feat in ["advanced_security", "code_security", "secret_scanning", "secret_scanning_push_protection", "secret_scanning_ai_detection", "secret_scanning_non_provider_patterns"] :
        var.security_baseline[vis][feat] == (vis == "public" && contains(["secret_scanning", "secret_scanning_push_protection"], feat))
      ]
    ]))
    error_message = "default baseline must enable only free public secret scanning and push protection"
  }
}
