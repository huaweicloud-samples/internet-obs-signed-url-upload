# 云服务委托：函数运行时由此获得临时 AK/SK/SecurityToken，凭据不落盘、不轮换。
resource "huaweicloud_identity_agency" "functiongraph" {
  name                   = "${local.name_prefix}-fgs-agency"
  description            = "Agency for FunctionGraph to issue object upload authorization URLs"
  delegated_service_name = "op_svc_cff"

  domain_roles = [
    "OBS OperateAccess",
  ]
}

# 函数代码与依赖由 scripts/package-function.sh 打成 zip，通过 func_code 直接上传。
resource "huaweicloud_fgs_function" "issue_upload_url" {
  name        = "${local.name_prefix}-issue-upload-url"
  app         = "default"
  agency      = huaweicloud_identity_agency.functiongraph.name
  handler     = "index.handler"
  runtime     = "Node.js18.18"
  memory_size = var.function_memory_size
  timeout     = var.function_timeout

  code_type     = "zip"
  code_filename = "issue-upload-url.zip"
  func_code     = filebase64("${path.module}/../build/issue-upload-url.zip")

  user_data = jsonencode({
    OBS_BUCKET          = huaweicloud_obs_bucket.uploads.bucket
    OBS_ENDPOINT        = "https://obs.${var.region}.myhuaweicloud.com"
    UPLOAD_EXPIRES      = tostring(var.signed_url_expires)
    UPLOAD_CONTENT_TYPE = var.upload_content_type
    CORS_ALLOW_ORIGIN   = "*"
  })

  # 委托在 IAM 侧生效有短暂延迟，未就绪时建函数会返回 FSS.1501。
  depends_on = [huaweicloud_identity_agency.functiongraph]
}
