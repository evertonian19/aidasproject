# # github.tf

# # ─── AWS 자격증명만 (CI/CD 필수) ─────────────────────────────────
# resource "github_actions_secret" "aws_access_key" {
#   repository      = "aidas"
#   secret_name     = "AWS_ACCESS_KEY_ID"
#   plaintext_value = var.aws_access_key
# }

# resource "github_actions_secret" "aws_secret_key" {
#   repository      = "aidas"
#   secret_name     = "AWS_SECRET_ACCESS_KEY"
#   plaintext_value = var.aws_secret_key
# }