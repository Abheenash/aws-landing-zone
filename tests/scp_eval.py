"""A small, honest subset of IAM policy evaluation — enough to prove what each SCP
denies and, just as importantly, what it leaves alone.

Supported: Action / NotAction with wildcards, Resource ARN globs, and the condition
operators the policies use: StringEquals, StringNotEquals, StringLike, ArnLike,
ArnNotLike, Null, NumericGreaterThan, and the ForAnyValue: set prefix. SCPs are
deny-only filters, so a request is "denied" if any Deny statement matches.
"""
import json
import re


def _glob(pattern, value):
    return re.fullmatch(re.escape(pattern).replace(r"\*", ".*").replace(r"\?", "."), value or "") is not None


def _as_list(v):
    return v if isinstance(v, list) else [v]


def _cond_ok(operator, key, expected, ctx):
    """True when this condition entry is satisfied by the request context."""
    set_prefix = None
    if ":" in operator:
        set_prefix, operator = operator.split(":", 1)
    actual = ctx.get(key)
    actuals = _as_list(actual) if actual is not None else []
    expected = _as_list(expected)

    def one(a):
        if operator == "StringEquals":
            return a in expected
        if operator == "StringNotEquals":
            return a not in expected
        if operator in ("StringLike", "ArnLike"):
            return any(_glob(e, a) for e in expected)
        if operator in ("StringNotLike", "ArnNotLike"):
            return not any(_glob(e, a) for e in expected)
        if operator == "NumericGreaterThan":
            return float(a) > float(expected[0])
        if operator == "Bool":
            return str(a).lower() == str(expected[0]).lower()
        raise NotImplementedError(operator)

    if operator == "Null":
        want_missing = str(expected[0]).lower() == "true"
        return (actual is None) == want_missing
    if actual is None:
        # A missing key fails positive matches and satisfies negative ones.
        return operator in ("StringNotEquals", "StringNotLike", "ArnNotLike")
    if set_prefix == "ForAnyValue":
        return any(one(a) for a in actuals)
    if set_prefix == "ForAllValues":
        return all(one(a) for a in actuals)
    return one(actuals[0])


def _matches(stmt, action, resource, ctx):
    if "Action" in stmt and not any(_glob(a, action) for a in _as_list(stmt["Action"])):
        return False
    if "NotAction" in stmt and any(_glob(a, action) for a in _as_list(stmt["NotAction"])):
        return False
    if not any(_glob(r, resource) for r in _as_list(stmt.get("Resource", "*"))):
        return False
    for operator, entries in stmt.get("Condition", {}).items():
        for key, expected in entries.items():
            if not _cond_ok(operator, key, expected, ctx):
                return False
    return True


def denied(policy, action, resource="*", **ctx):
    """True if any Deny statement in the SCP matches the request."""
    doc = json.loads(policy) if isinstance(policy, str) else policy
    return any(s.get("Effect") == "Deny" and _matches(s, action, resource, ctx) for s in doc["Statement"])
