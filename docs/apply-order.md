# Applying this for real — order of operations and what it costs

This repo is **validated, tested and scanned, not applied**. Creating member accounts is effectively
irreversible (a closed account lingers 90 days; its email can never be reused), so the apply is a
deliberate, staged decision rather than a `terraform apply` in CI.

| Stage | What | Cost |
| --- | --- | --- |
| 1 | `aws_organizations_organization` + OUs + SCPs + tag policy | **$0** — Organizations and policies are free |
| 2 | Member accounts (4) | **$0** — but needs four real, unique email addresses; plus-addressing (`aws+dev@…`) works with Gmail/Fastmail |
| 3 | Account baselines (S3 block, password policy, EBS encryption, OIDC deploy roles, budgets) | **$0** — the first two budgets per account are free; budgets 3+ are $0.02/day |
| 4 | Organization CloudTrail → Security account bucket + root-usage alarm | **~$0** — the first copy of management events is free; S3 for a small org is cents/month; one alarm |
| 5 | *(not in this repo yet)* Config org aggregator, GuardDuty and Security Hub delegated admin | **$10–30/month** — Config item charges and GuardDuty per-event pricing; the `aws_service_access_principals` are pre-enabled so it's an additive change |

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in real emails
terraform init
terraform apply -target=aws_organizations_organization.org      # stage 1: org
terraform apply -target=aws_organizations_policy_attachment.root_deny_root \
                -target=aws_organizations_policy_attachment.root_region_lock \
                -target=aws_organizations_policy_attachment.root_protect_baseline
terraform apply                                                  # stages 2–4
terraform output deploy_roles                                    # → each repo's AWS_ROLE_ARN variable
```

**Before stage 1** the management account itself gets no SCP (SCPs never apply to the management
account), so keep it empty of workloads — that is the whole point of a landing zone.

**Region lock and existing workloads:** the lock exempts `OrganizationAccountAccessRole`, so a
break-glass session can still reach any region. Everything in this portfolio already runs in
`us-east-1`.
