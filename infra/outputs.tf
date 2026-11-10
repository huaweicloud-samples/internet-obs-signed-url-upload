locals {
  # 关闭公网入口档时资源列表为空；用 one() 取值可避免下标越界。
  ingress_address = try(coalesce(one(huaweicloud_apig_instance.main[*].ingress_address), ""), "")
  api_group_id    = try(one(huaweicloud_apig_group.main[*].id), "")
}

output "api_endpoint" {
  description = "浏览器调用的授权接口地址；轻量验证档返回说明文字"
  value = (
    var.enable_public_api
    ? (local.ingress_address != "" ? "https://${local.ingress_address}/release/upload-url" : "公网入口未启用，请检查网关入口配置")
    : "公网入口未启用（当前为轻量验证档，请直接调用函数）"
  )
}

output "internal_api_domain" {
  description = "网关分组的内网访问域名（同 VPC 内可达）"
  value = (
    local.api_group_id != ""
    ? "${local.api_group_id}.apic.${var.region}.huaweicloudapis.com"
    : "公网入口未启用"
  )
}

output "obs_bucket_name" {
  description = "接收直传对象的桶名"
  value       = huaweicloud_obs_bucket.uploads.bucket
}

output "function_name" {
  description = "签发授权 URL 的函数名；轻量验证档用它直接调用函数"
  value       = huaweicloud_fgs_function.issue_upload_url.name
}

output "function_urn" {
  description = "函数的 URN，供直接调用接口使用"
  value       = huaweicloud_fgs_function.issue_upload_url.urn
}

output "agency_name" {
  description = "函数使用的云服务委托名"
  value       = huaweicloud_identity_agency.functiongraph.name
}
