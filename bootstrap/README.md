# Terraform state backend

The chicken-and-egg root of every other project: the thing that creates the state
backend cannot itself live in the state backend. This is applied **once, by hand**,
and it is the only Terraform in my projects whose state is deliberately local.

## What it creates

One S3 bucket, shared by every project, with:

- **versioning** — superseded state is the undo button for a bad apply
- **a KMS CMK** with rotation, not SSE-S3 — state contains resource attributes and
  occasionally secrets, and a CMK lets access be revoked independently of the
  bucket policy
- **`prevent_destroy`** — losing state is worse than losing the infrastructure,
  because you lose the ability to manage what's left
- **a bucket policy that denies non-TLS requests and unencrypted uploads** — the
  default policy permits plaintext HTTP, which would put state on the wire in clear
- **a lifecycle rule** expiring noncurrent versions after 90 days and aborting
  stale multipart uploads

No DynamoDB lock table. S3-native locking (`use_lockfile = true`) replaced it in
Terraform 1.10; keeping one now is cargo cult.

## Why one bucket, not nine

One bucket to version, encrypt, audit and pay for — with each project under its
own key. Per-project buckets multiply the number of things that have to be got
right and the number of places a misconfiguration can hide.

## Using it

```bash
cd bootstrap
terraform init
terraform apply -var bucket_name=abheenash-tfstate-<account_id>
terraform output backend_hcl        # prints the block to paste
```

Then in each project:

```bash
cd <repo>/terraform
cp backend.hcl.example backend.hcl  # fill in from the output above
terraform init -backend-config=backend.hcl
```

`backend.hcl` is gitignored because the bucket name embeds an account id; the
`.example` is what's committed.

CI never needs any of this — `fmt`, `validate` and `terraform test` all run with
`-backend=false`, so a pull request is checked without touching AWS at all.

## Verified

`terraform validate` clean, **15 checkov checks pass, 0 fail**. Not applied — the
bucket it would create is real, persistent, and outlives the demos, so it is a
deliberate manual step rather than something a CI run can do by accident.
