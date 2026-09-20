# aws-landing-zone

> **Sep 2026:** first release — Organizations + OU tree, five SCPs unit-tested against concrete requests, OIDC deploy roles with permissions boundaries, org CloudTrail; validated, deliberately not applied.

A multi-account AWS foundation in Terraform — **Organizations, an OU tree, service control
policies as guardrails, per-account baselines, keyless GitHub OIDC deploy roles scoped to
named repos, budgets, and an organization CloudTrail with a root-usage alarm** — with every
guardrail **unit-tested against concrete requests** before it ever touches an account.

[![ci](https://github.com/Abheenash/aws-landing-zone/actions/workflows/ci.yml/badge.svg)](https://github.com/Abheenash/aws-landing-zone/actions/workflows/ci.yml)

**Status:** validated (`terraform validate`), scanned (checkov, 91 passed / 0 failed against a
reviewed baseline), and tested (11 policy tests) — **deliberately not applied.** Creating member
accounts is irreversible, so [docs/apply-order.md](docs/apply-order.md) stages it and prices it
(stages 1–4 are free; only the optional Config/GuardDuty stage costs money).

## Why this exists

My other AWS projects each live in one account. That's fine for a demo and wrong for a company:
production and experiments share a blast radius, a leaked key reaches everything, and there is no
place to enforce "nobody uses root" or "nothing runs in ap-south-1" that a workload can't undo.
Governance is a whole domain of the DevOps Professional exam that a single-account portfolio
can't show. This repo is that domain, done the way I'd do it for a team.

## Layout

```
Root ──── SCPs: deny-root-user · region-lock · protect-security-baseline · tag-shape (tag policy)
├── Security       → org CloudTrail bucket (versioned, KMS, 400-day retention, TLS-only), root-usage alarm
├── Workloads      → SCP: require-cost-tags
│   ├── Dev        → OIDC deploy role for 3 repos, $20 budget
│   └── Prod       → OIDC deploy role for 1 repo,  $20 budget
└── Sandbox        → SCP: sandbox-limits (no RDS/EKS/NAT/reservations, nothing above *.medium, volumes ≤ 50 GB)
```

Every account gets the baseline module: account-wide S3 public-access block, a 16-char IAM
password policy, EBS encryption by default, a budget alerting at 80% forecast and 100% actual,
and — for workload accounts — a **GitHub OIDC role** whose trust is `repo:<owner>/<name>:ref:refs/heads/main`
for the named repos only (a fork's PR or a feature branch cannot assume it), with a
**permissions boundary** that caps what the role can ever be widened to and that explicitly denies
touching Organizations, CloudTrail, Config, GuardDuty, or creating IAM users and access keys.

## The guardrails, and what proves them

SCPs are JSON files in [`terraform/policies/`](terraform/policies/) — reviewers read a policy, not
HCL that generates one — and [`tests/test_policies.py`](tests/test_policies.py) evaluates each one
against concrete requests with a small IAM-condition simulator ([`tests/scp_eval.py`](tests/scp_eval.py)).
The tests assert what is blocked **and what must keep working**, because an over-broad deny is the
classic SCP failure (locking IAM out of every region, for instance):

| Policy | Blocks | Proven to leave alone |
| --- | --- | --- |
| `deny-root-user` | the root user doing any ordinary work; creating root access keys | root doing billing / account closure / support; every non-root principal |
| `region-lock` (templated from `home_regions`) | any regional call outside the home regions | IAM, STS, Route 53, CloudFront, Budgets, Organizations, account-level S3; the break-glass `OrganizationAccountAccessRole` |
| `protect-security-baseline` | stopping/deleting CloudTrail, Config, GuardDuty, Security Hub; leaving the org; editing the org access role; loosening the account S3 block | reading CloudTrail; deleting *other* roles; the org access role managing itself |
| `require-cost-tags` (templated from `required_tags`) | creating EC2/EBS/RDS/Lambda/DynamoDB/ECS/EKS/ALB/S3 without **Project** and **Owner** | reads; non-cost-bearing writes like `iam:CreateRole` or `dynamodb:PutItem` |
| `sandbox-limits` | RDS, EKS, ElastiCache, OpenSearch, SageMaker, NAT gateways, reservations, domain registration; instances above `t3/t4g.medium`; volumes > 50 GB | Lambda, S3, small instances |

Shape checks confirm every SCP is deny-only, has unique statement ids, and stays under the
5,120-byte limit *after* templating.

## Repo map

| Path | What |
| --- | --- |
| `terraform/organization.tf` | Organization, OU tree, enabled policy types and service principals |
| `terraform/accounts.tf` | Member accounts (`prevent_destroy`, never `close_on_deletion`) and per-account provider aliases |
| `terraform/scps.tf` | Policies and their attachments (Root vs OU) + the tag policy |
| `terraform/policies/` | The SCP documents; `.tftpl` ones take `home_regions` / `required_tags` |
| `terraform/modules/account-baseline/` | S3 block, password policy, EBS encryption, OIDC deploy role + boundary, budget |
| `terraform/cloudtrail.tf` | Org trail → Security-account bucket, log-file validation, root-usage metric filter + alarm |
| `tests/` | `scp_eval.py` (evaluator) and `test_policies.py` |
| `docs/apply-order.md` | Staged apply with costs |

## What I'd add next

Config organization aggregator + conformance packs and GuardDuty/Security Hub delegated
administration in the Security account (the service principals are pre-enabled; it's the one stage
that costs money), IAM Identity Center permission sets instead of the org access role for humans,
and an `aws_organizations_delegated_administrator` for CloudTrail so the management account holds
nothing but the org itself.
