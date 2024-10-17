resource "upstash_redis_database" "cache" {
  database_name = "${local.resource_name_prefix}-cache"
  primary_region = local.aws_region
  auto_scale = false
  region = "global"
  tls = true
}

output "upstash_redis_database_endpoint" {
  value = upstash_redis_database.cache.endpoint
}

output "upstash_redis_database_password" {
  value = upstash_redis_database.cache.password
}
