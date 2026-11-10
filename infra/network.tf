# 网关专享实例需要 VPC、子网与安全组；函数本身不挂载 VPC。
# 轻量验证档不创建网关，这一组网络资源也随之不创建。
resource "huaweicloud_vpc" "main" {
  count = var.enable_public_api ? 1 : 0

  name = "${local.name_prefix}-vpc"
  cidr = "10.0.0.0/16"
}

resource "huaweicloud_vpc_subnet" "main" {
  count = var.enable_public_api ? 1 : 0

  name       = "${local.name_prefix}-subnet"
  vpc_id     = huaweicloud_vpc.main[0].id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  count = var.enable_public_api ? 1 : 0

  name        = "${local.name_prefix}-sg"
  description = "Security group for ${local.name_prefix}"
}

resource "huaweicloud_networking_secgroup_rule" "allow_https" {
  count = var.enable_public_api ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main[0].id
}

resource "huaweicloud_networking_secgroup_rule" "allow_http" {
  count = var.enable_public_api ? 1 : 0

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main[0].id
}
