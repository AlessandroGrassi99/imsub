resource "aws_dynamodb_table" "twitch_tokens" {
  name           = "${local.resource_name_prefix}-twitch-tokens"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "telegram_user_id"

  attribute {
    name = "telegram_user_id"
    type = "S"
  }

  tags = {
    Environment = local.environment
    App         = local.app
  }
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name   = "${local.resource_name_prefix}-dynamodb-access"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.twitch_tokens.arn
    }]
  })
}