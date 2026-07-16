mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = false
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null

  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

run "F1_public_omitted_defaults_true" {
  command = plan
  variables { repo_yaml_path = "tests/fixtures/good-minimal" }
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_forking == true
    error_message = "F1: public omitted allow_forking must default to true"
  }
}

run "F2_org_private_omitted_defaults_false" {
  command = plan
  variables {
    repo_yaml_path         = "tests/fixtures/good-forking-defaults"
    github_is_organization = true
    repo_default_rules     = []
  }
  assert {
    condition     = output.all_repositories["private-default-repo"].allow_forking == false
    error_message = "F2: organization-owned private omitted allow_forking must default to false"
  }
}

run "F3_internal_omitted_defaults_false" {
  command = plan
  variables {
    repo_yaml_path         = "tests/fixtures/good-forking-defaults"
    github_is_organization = true
    repo_default_rules     = []
  }
  assert {
    condition     = output.all_repositories["internal-default-repo"].allow_forking == false
    error_message = "F3: internal omitted allow_forking must default to false"
  }
}

run "F4_org_private_explicit_true_passes_through" {
  command = plan
  variables {
    repo_yaml_path         = "tests/fixtures/good-forking-explicit"
    github_is_organization = true
    repo_default_rules     = []
  }
  assert {
    condition     = output.all_repositories["private-explicit-repo"].allow_forking == true
    error_message = "F4: organization-owned private explicit true must pass through"
  }
}

run "F5_public_explicit_false_fails" {
  command = plan
  variables { repo_yaml_path = "tests/fixtures/bad-allow-forking" }
  expect_failures = [terraform_data.framework_validation]
}

run "F6_personal_private_omitted_defaults_null" {
  command = plan
  variables {
    repo_yaml_path         = "tests/fixtures/good-forking-defaults"
    github_is_organization = false
  }
  assert {
    condition     = output.all_repositories["private-default-repo"].allow_forking == null
    error_message = "F6: personal-account private omitted allow_forking must default to null"
  }
}

run "F7_personal_private_explicit_true_passes_through" {
  command = plan
  variables {
    repo_yaml_path         = "tests/fixtures/good-forking-explicit"
    github_is_organization = false
  }
  assert {
    condition     = output.all_repositories["private-explicit-repo"].allow_forking == true
    error_message = "F7: personal-account private explicit true must pass through"
  }
}
