output "webhook_endpoint" {
  value = "${aws_api_gateway_deployment.telegram.invoke_url}/webhook"
}

output "sqs_update_user" {
  value = aws_sqs_queue.send_user_subs.name
}