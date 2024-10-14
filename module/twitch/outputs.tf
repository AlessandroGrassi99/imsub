output "lambda_check_user_auth" {
  value = aws_lambda_function.auth_check.function_name
}

output "lambda_get_channel_subs" {
  value = aws_lambda_function.channel_subs.function_name
}

output "lambda_get_user_subs" {
  value = aws_lambda_function.user_subs.function_name
}

