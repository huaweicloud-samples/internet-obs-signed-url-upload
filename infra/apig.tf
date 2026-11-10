locals {
  # 专享实例自带的 RELEASE 环境 ID 为固定常量，不用 data source 查询：
  # 实例发生变更时 data source 在 plan 期会取不到值，导致发布资源报错。
  release_env_id = "DEFAULT_ENVIRONMENT_RELEASE_ID"
}

# 轻量验证档（enable_public_api = false）不创建网关实例与公网入口。
# 此时直接调用函数即可取得授权 URL，对象直传仍走 OBS 公网端点，业务链路保持完整。
resource "huaweicloud_apig_instance" "main" {
  count = var.enable_public_api ? 1 : 0

  name              = "${local.name_prefix}-apig"
  edition           = "BASIC"
  vpc_id            = huaweicloud_vpc.main[0].id
  subnet_id         = huaweicloud_vpc_subnet.main[0].id
  security_group_id = huaweicloud_networking_secgroup.main[0].id

  availability_zones = var.apig_availability_zones

  # 公网入口：带宽值与模式参数必须成对给出，且不能与 eip_id 同时使用。
  ingress_bandwidth_size          = var.apig_ingress_bandwidth_size
  ingress_bandwidth_charging_mode = var.apig_ingress_bandwidth_charging_mode

  maintain_begin = "02:00:00"

  tags = {
    project = local.name_prefix
  }
}

resource "huaweicloud_apig_group" "main" {
  count = var.enable_public_api ? 1 : 0

  name        = "${local.name_prefix}-group"
  instance_id = huaweicloud_apig_instance.main[0].id
  description = "Upload authorization API group"
}

resource "huaweicloud_apig_api" "issue_upload_url" {
  count = var.enable_public_api ? 1 : 0

  name        = "issue-upload-url"
  instance_id = huaweicloud_apig_instance.main[0].id
  group_id    = huaweicloud_apig_group.main[0].id
  description = "Issue a time-limited PUT authorization URL"

  type             = "FunctionGraph"
  request_protocol = "HTTPS"
  request_method   = "GET"
  request_path     = "/upload-url"
  cors             = true

  # 教学演示接口不设访问鉴权；生产环境应启用认证并对来源做限制。
  security_authentication = "NONE"

  func_graph {
    # 去掉版本后缀，避免函数代码更新时触发网关侧不支持的原地更新。
    function_urn     = trimsuffix(huaweicloud_fgs_function.issue_upload_url.urn, ":latest")
    invocation_type  = "sync"
    timeout          = var.function_timeout * 1000
    network_type     = "V1"
    request_protocol = "HTTPS"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# API 创建后不会自动对外提供访问，必须显式发布到环境。
resource "huaweicloud_apig_api_publishment" "issue_upload_url" {
  count = var.enable_public_api ? 1 : 0

  instance_id = huaweicloud_apig_instance.main[0].id
  api_id      = huaweicloud_apig_api.issue_upload_url[0].id
  env_id      = local.release_env_id
}
