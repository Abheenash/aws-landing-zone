output "bucket" {
  description = "Put this in each project's backend.hcl"
  value       = aws_s3_bucket.state.id
}

output "kms_key_arn" {
  value = aws_kms_key.state.arn
}

output "backend_hcl" {
  description = "Paste into <repo>/terraform/backend.hcl, changing only the key."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "<project-name>/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    kms_key_id   = "${aws_kms_key.state.arn}"
    use_lockfile = true
  EOT
}
