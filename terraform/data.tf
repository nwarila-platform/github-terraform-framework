#% ========================================================================================== %#
#% = File: data.tf                                                                            %#
#% ------------------------------------------------------------------------------------------ %#
#% Organization repository inventory lookups used by the advisory completeness check.         %#
#% ========================================================================================== %#

data "github_repositories" "owner" {
  for_each         = local.org_lookup
  query            = "org:${each.key} fork:true"
  results_per_page = 100
}

data "github_repositories" "public" {
  for_each         = local.org_lookup
  query            = "org:${each.key} is:public fork:true"
  results_per_page = 100
}
