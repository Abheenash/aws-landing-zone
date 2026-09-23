"""Prove each SCP against concrete requests — what it blocks AND what it must not block."""
import json
import os
import subprocess

import pytest
from scp_eval import denied

ROOT = os.path.join(os.path.dirname(__file__), "..", "terraform")
POL = os.path.join(ROOT, "policies")

USER = "arn:aws:iam::111111111111:user/alice"
ORG_ROLE = "arn:aws:iam::111111111111:role/OrganizationAccountAccessRole"
ROOT_USER = "arn:aws:iam::111111111111:root"


def load(name):
    return json.load(open(os.path.join(POL, name)))


def render(name, **vars):
    """Render a .tftpl the way Terraform will, using terraform console."""
    expr = f"templatefile({json.dumps(os.path.join(POL, name))}, {json.dumps(vars)})"
    # `terraform` is resolved from PATH on purpose: CI installs it via
    # setup-terraform and a developer has their own. Hardcoding a path would
    # break both.
    out = subprocess.run(
        ["terraform", "console"],  # noqa: S607 — resolved from PATH on purpose
        input=expr, capture_output=True, text=True, cwd=ROOT, check=True,
    ).stdout
    # console prints multi-line strings as a heredoc: <<EOT ... EOT
    lines = out.strip().splitlines()
    if lines and lines[0].startswith("<<"):
        lines = lines[1:-1]
    body = "\n".join(lines)
    return json.loads(json.loads(body) if body.startswith('"') else body)


@pytest.fixture(scope="module")
def region_lock():
    return render("region-lock.json.tftpl", home_regions=json.dumps(["us-east-1", "us-west-2"]), required_tags=[], org_id="o-x")


@pytest.fixture(scope="module")
def require_tags():
    return render("require-tags.json.tftpl", home_regions="[]", required_tags=["Project", "Owner"], org_id="o-x")


# ---------------------------------------------------------------- deny-root-user
def test_root_cannot_do_ordinary_work_but_can_do_billing():
    p = load("deny-root-user.json")
    assert denied(p, "ec2:RunInstances", **{"aws:PrincipalArn": ROOT_USER})
    assert denied(p, "s3:GetObject", **{"aws:PrincipalArn": ROOT_USER})
    assert not denied(p, "billing:ViewBilling", **{"aws:PrincipalArn": ROOT_USER})
    assert not denied(p, "account:CloseAccount", **{"aws:PrincipalArn": ROOT_USER})
    assert not denied(p, "ec2:RunInstances", **{"aws:PrincipalArn": USER})  # normal users unaffected
    assert denied(p, "iam:CreateAccessKey", resource=ROOT_USER, **{"aws:PrincipalArn": USER})


# ---------------------------------------------------------------- region-lock
def test_region_lock_denies_other_regions_but_not_global_services(region_lock):
    p = region_lock
    ctx = {"aws:PrincipalArn": USER}
    assert denied(p, "ec2:RunInstances", **ctx, **{"aws:RequestedRegion": "eu-west-1"})
    assert not denied(p, "ec2:RunInstances", **ctx, **{"aws:RequestedRegion": "us-east-1"})
    assert not denied(p, "ec2:RunInstances", **ctx, **{"aws:RequestedRegion": "us-west-2"})
    # global services must keep working from anywhere
    for a in ("iam:CreateRole", "sts:AssumeRole", "route53:ChangeResourceRecordSets", "cloudfront:CreateInvalidation",
              "budgets:ViewBudget", "s3:ListAllMyBuckets", "organizations:DescribeOrganization"):
        assert not denied(p, a, **ctx, **{"aws:RequestedRegion": "eu-west-1"}), a
    # and s3 bucket operations in a foreign region ARE denied (only the account-level s3 calls are exempt)
    assert denied(p, "s3:CreateBucket", **ctx, **{"aws:RequestedRegion": "ap-south-1"})


def test_region_lock_exempts_the_org_access_role(region_lock):
    assert not denied(region_lock, "ec2:RunInstances", **{"aws:PrincipalArn": ORG_ROLE, "aws:RequestedRegion": "eu-west-1"})


# ---------------------------------------------------------------- protect-security-baseline
def test_baseline_cannot_be_disabled_by_members():
    p = load("protect-security-baseline.json")
    ctx = {"aws:PrincipalArn": USER}
    for a in ("cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "config:StopConfigurationRecorder",
              "guardduty:DeleteDetector", "securityhub:DisableSecurityHub", "organizations:LeaveOrganization"):
        assert denied(p, a, **ctx), a
    assert denied(p, "iam:DeleteRole", resource=ORG_ROLE, **ctx)
    assert not denied(p, "iam:DeleteRole", resource="arn:aws:iam::111111111111:role/app-role", **ctx)
    assert not denied(p, "iam:DeleteRole", resource=ORG_ROLE, **{"aws:PrincipalArn": ORG_ROLE})  # the role itself may
    assert not denied(p, "cloudtrail:LookupEvents", **ctx)  # reading is fine
    assert denied(p, "s3:PutAccountPublicAccessBlock", **ctx)


# ---------------------------------------------------------------- require-tags
def test_cost_bearing_resources_need_both_tags(require_tags):
    p = require_tags
    both = {"aws:RequestTag/Project": "x", "aws:RequestTag/Owner": "a@b.c"}
    assert not denied(p, "ec2:RunInstances", **both)
    assert not denied(p, "rds:CreateDBInstance", **both)
    assert denied(p, "ec2:RunInstances", **{"aws:RequestTag/Project": "x"})   # Owner missing
    assert denied(p, "ec2:RunInstances", **{"aws:RequestTag/Owner": "a@b.c"})  # Project missing
    assert denied(p, "lambda:CreateFunction")
    assert denied(p, "eks:CreateCluster")
    # untagged READS and non-cost-bearing writes are not the SCP's business
    assert not denied(p, "ec2:DescribeInstances")
    assert not denied(p, "iam:CreateRole")
    assert not denied(p, "dynamodb:PutItem")


def test_require_tags_statement_ids_are_unique_and_rendered_per_tag(require_tags):
    sids = [s["Sid"] for s in require_tags["Statement"]]
    assert len(sids) == len(set(sids)) == 4
    assert {"RequireProjectTagOnCreate", "RequireOwnerTagOnBucket"} <= set(sids)


# ---------------------------------------------------------------- sandbox-limits
def test_sandbox_blocks_expensive_and_persistent_services():
    p = load("sandbox-limits.json")
    for a in ("rds:CreateDBInstance", "eks:CreateCluster", "ec2:CreateNatGateway", "savingsplans:CreateSavingsPlan",
              "route53domains:RegisterDomain", "elasticache:CreateCacheCluster"):
        assert denied(p, a), a
    inst = "arn:aws:ec2:us-east-1:111111111111:instance/*"
    assert not denied(p, "ec2:RunInstances", resource=inst, **{"ec2:InstanceType": "t3.micro"})
    assert denied(p, "ec2:RunInstances", resource=inst, **{"ec2:InstanceType": "m5.large"})
    assert denied(p, "ec2:RunInstances", resource=inst, **{"ec2:InstanceType": "p3.2xlarge"})
    vol = "arn:aws:ec2:us-east-1:111111111111:volume/*"
    assert not denied(p, "ec2:CreateVolume", resource=vol, **{"ec2:VolumeSize": "20"})
    assert denied(p, "ec2:CreateVolume", resource=vol, **{"ec2:VolumeSize": "500"})
    assert not denied(p, "lambda:CreateFunction")  # serverless experiments are fine
    assert not denied(p, "s3:CreateBucket")


# ---------------------------------------------------------------- shape checks on every policy
@pytest.mark.parametrize("name", ["deny-root-user.json", "protect-security-baseline.json", "sandbox-limits.json"])
def test_every_scp_is_deny_only_and_under_the_size_limit(name):
    p = load(name)
    assert p["Version"] == "2012-10-17"
    assert all(s["Effect"] == "Deny" for s in p["Statement"]), "SCPs here are deny-only filters"
    assert len(json.dumps(p, separators=(",", ":"))) < 5120, "SCP max size is 5,120 bytes"


def test_rendered_templates_are_under_the_size_limit(region_lock, require_tags):
    for p in (region_lock, require_tags):
        assert len(json.dumps(p, separators=(",", ":"))) < 5120
