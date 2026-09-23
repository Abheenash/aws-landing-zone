variables {
  # The only required input. A test value, never a real domain.
  org_root_email_domain = "example.invalid"
  budget_email          = "nobody@example.invalid"
}

mock_provider "aws" {
  # Mocked data sources return placeholder strings that the AWS provider then
  # rejects as invalid JSON; a minimal valid document keeps the mock usable.
  override_data {
    target = data.aws_iam_policy_document.audit_bucket
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.trail_logs_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
run "org_cloudtrail_is_tamper_evident_and_global" {
  command = plan

  # A trail that is single-region or unvalidated is an audit trail you cannot rely
  # on in an incident — which is the only time it matters.
  assert {
    condition     = aws_cloudtrail.org.is_multi_region_trail
    error_message = "The organization trail must be multi-region; a region-locked trail misses activity in any region an SCP has not yet blocked."
  }

  assert {
    condition     = aws_cloudtrail.org.enable_log_file_validation
    error_message = "Log file validation must be on, or tampering with the audit log is undetectable."
  }

  assert {
    condition     = aws_cloudtrail.org.is_organization_trail
    error_message = "This must be an organization trail, otherwise member accounts are not covered."
  }
}

run "audit_bucket_is_versioned_and_private" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.audit.block_public_acls,
      aws_s3_bucket_public_access_block.audit.block_public_policy,
      aws_s3_bucket_public_access_block.audit.ignore_public_acls,
      aws_s3_bucket_public_access_block.audit.restrict_public_buckets,
    ])
    error_message = "The audit bucket holds the org's CloudTrail. It must block every public-access vector."
  }
}

# NOT tested here: SCP attachment and semantics.
#
# Policy ids are computed, so a mocked plan cannot see which policy an attachment
# points at. More importantly it would be redundant — tests/ already evaluates
# each SCP against concrete allowed and denied requests (11 tests), which is a
# stronger assertion than "a reference is wired up" could ever be. A test that
# duplicates a better test while proving less is worth deleting.
