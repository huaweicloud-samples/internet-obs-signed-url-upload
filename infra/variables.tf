variable "region" {
  description = "部署区域"
  type        = string
  default     = "cn-north-4"
}

variable "app_name" {
  description = "资源名前缀，小写字母、数字与连字符"
  type        = string
  default     = "obs-signed-url-upload"
}

variable "obs_bucket_name" {
  description = "接收上传对象的 OBS 桶名，需全局唯一"
  type        = string
}

variable "domain_id" {
  description = "账号 Domain ID，用于 OBS 桶策略声明可写主体"
  type        = string
}

variable "cors_allowed_origins" {
  description = "允许跨域直传的来源列表"
  type        = list(string)
  default     = ["*"]
}

variable "signed_url_expires" {
  description = "授权 URL 有效期（秒）"
  type        = number
  default     = 900
}

variable "upload_content_type" {
  description = "参与签名的上传内容类型，须与浏览器 PUT 请求头一致"
  type        = string
  default     = "image/jpeg"
}

variable "function_memory_size" {
  description = "函数内存（MB）"
  type        = number
  default     = 128
}

variable "function_timeout" {
  description = "函数超时（秒）"
  type        = number
  default     = 10
}

variable "apig_availability_zones" {
  description = "网关实例可用区"
  type        = list(string)
  default     = ["cn-north-4a"]
}

variable "apig_ingress_bandwidth_size" {
  description = "网关公网入口带宽；与模式参数必须成对出现"
  type        = number
  default     = 5
}

variable "apig_ingress_bandwidth_charging_mode" {
  description = "网关公网入口带宽的模式参数"
  type        = string
  default     = "traffic"
}

variable "enable_public_api" {
  description = "是否创建网关专享实例与公网入口；关闭后可用函数直调完成链路验证"
  type        = bool
  default     = true
}
