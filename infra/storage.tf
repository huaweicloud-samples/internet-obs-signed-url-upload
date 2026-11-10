# 私有桶：对象只能凭函数签发的授权 URL 写入，桶本身不开放公共写权限。
resource "huaweicloud_obs_bucket" "uploads" {
  bucket        = var.obs_bucket_name
  acl           = "private"
  force_destroy = true

  # 浏览器从页面所属来源直接 PUT 对象，必须配置桶级跨域规则。
  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }

  tags = {
    project = local.name_prefix
  }
}

# 桶策略显式声明账号域内主体的对象写权限。
# 仅授予 IAM 委托侧权限时，OBS 数据面会拒绝由委托身份签发的请求。
resource "huaweicloud_obs_bucket_policy" "uploads" {
  bucket        = huaweicloud_obs_bucket.uploads.bucket
  policy_format = "obs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowUploadFromAccount"
        Effect = "Allow"
        Principal = {
          ID = ["domain/${var.domain_id}"]
        }
        Action = [
          "PutObject",
          "GetObject",
          "ListBucket",
        ]
        Resource = [
          huaweicloud_obs_bucket.uploads.bucket,
          "${huaweicloud_obs_bucket.uploads.bucket}/*",
        ]
      },
    ]
  })
}
