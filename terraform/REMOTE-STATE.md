# Why this one repo has no `backend "s3"` block

Every other project here declares a partial S3 backend. This one deliberately
does not, and the reason is worth writing down rather than leaving as an
inconsistency someone later "fixes".

The SCP test suite (`tests/`, 11 tests) evaluates each policy against concrete
allowed and denied requests by driving **`terraform console`**. `terraform
console` refuses to run against an uninitialised backend — and unlike `validate`,
`fmt` and `test`, it has no `-backend=false` escape hatch. Declaring a backend
here means nobody can run the tests without S3 credentials, in a repo whose entire
value is that its guardrails are unit-tested before they ever touch an account.

That trade is the wrong way round, so the backend stays out.

It also costs almost nothing: this repo is **validated, deliberately not applied**
(creating member accounts is irreversible — see `docs/apply-order.md`), so there
is no live state to protect. If it is ever applied for real, add the backend then
and move the console-driven tests to a copy of the module without it.

The state bucket every *other* project uses is created by
[`../bootstrap`](../bootstrap/), which lives in this repo.
