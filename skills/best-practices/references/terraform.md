## Terraform / Terragrunt

- _Terraform_: Pin provider versions in every module (`required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }`). An unpinned provider can change resource schema between plan and apply, producing destructive diffs nobody asked for.
- _Terraform_: Pin Terraform itself with `required_version = ">= 1.6.0, < 2.0.0"` in every module. Across-major upgrades deprecate behavior; pinning forces a deliberate upgrade path.
- _Terraform_: Remote state with locking is non-negotiable for any shared environment. S3 + DynamoDB or GCS + native locks. Local state is fine for a single-author personal stack and disastrous for a team.
- _Terraform_: Run `terraform plan` in CI on every PR and require the plan output as a review artifact. A merged PR whose plan was never inspected is a merge to production by-accident.
- _Terraform_: Treat `terraform apply` as a privileged operation. Apply happens through CI on a protected branch, never from a developer's laptop in a shared environment.
- _Terragrunt_: Use Terragrunt to orchestrate multiple Terraform modules with shared inputs. The DRY pattern (`terragrunt.hcl` per environment, generating provider/backend blocks) is what Terragrunt is for; treat the per-env files as configuration, not code.
- _Terragrunt_: Run `terragrunt run-all plan` from the root only when you genuinely need to plan everything. For day-to-day work, `cd` into the affected module and run `terragrunt plan` there — it's faster and the blast radius is one module.
- _Terraform_: Module inputs must be typed (`variable "x" { type = string }`). An untyped variable accepts anything and surfaces type errors deep in the resource block instead of at the boundary.
- _Terraform_: Don't use `null_resource` + `local-exec` to glue together what providers can do natively. Glue scripts have no dependency graph, no idempotency, and no rollback — they're the easiest way to make a deterministic system non-deterministic.
- _Terraform_: Tag every resource with a standard set (owner, environment, cost-center, managed-by-terraform=true). Tags are the only path from "what is this resource?" to an answer the cost-management and audit teams can use.
- _Terraform_: Run `tflint` and `tfsec` (or `checkov`) in CI. tflint catches style and provider-specific issues; tfsec/checkov catches security misconfigurations (public S3 buckets, unencrypted volumes) before they're applied.
- _Terraform_: Refactor with `moved` blocks, not `terraform state rm` + `terraform import`. `moved` is reversible, declarative, and reviewable; manual state surgery is none of those.
