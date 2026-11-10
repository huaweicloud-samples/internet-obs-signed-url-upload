terraform {
  required_version = ">= 1.5.0"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.97.0"
    }
  }
}

# 访问密钥由运行环境提供，不写入任何配置文件。
provider "huaweicloud" {
  region = var.region
}

locals {
  name_prefix = var.app_name
}
