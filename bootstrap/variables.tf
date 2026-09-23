variable "region" {
  description = "Region for the state bucket. Keep it fixed — moving state later is painful."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = <<-EOT
    Globally-unique name for the shared state bucket. Suggested form:
    <org>-tfstate-<account_id>. Every project stores state here under its own key,
    so there is one bucket to secure, version and audit rather than nine.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{2,62}$", var.bucket_name))
    error_message = "Bucket names are lowercase, 3-63 chars, and may not start with a separator."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long superseded state versions are kept. They are the undo button for a bad apply."
  type        = number
  default     = 90
}
