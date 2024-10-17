output "lambda_check_user_auth" {
  value = aws_lambda_function.check_user_auth.function_name
}

output "lambda_get_channel_subs" {
  value = aws_lambda_function.channel_subs.function_name
}

output "lambda_get_user_subs" {
  value = aws_lambda_function.get_user_subs.function_name
}

