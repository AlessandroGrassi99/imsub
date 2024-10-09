resource "aws_dynamodb_table" "users" {
  name         = "${local.resource_name_prefix}-dynamodb-table-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}

output "dynamodb_table_users" {
  value = aws_dynamodb_table.users.name
}
