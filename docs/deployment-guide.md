# 部署指导

## 1. 前置条件

| 项 | 要求 |
|---|---|
| 账号 | 已开通华为云账号，具备创建 VPC / APIG / FunctionGraph / OBS / IAM 委托的权限 |
| 区域 | `cn-north-4`（默认值；换区域时同步调整 `apig_availability_zones` 与对象存储端点） |
| Terraform | `>= 1.5.0` |
| 华为云 Provider | `>= 1.97.0` |
| Node.js / npm | Node.js `>= 18`，用于把函数依赖打包成 zip |
| Python | `>= 3.8`，打包脚本用它生成 zip |
| 访问密钥 | 在华为云控制台「我的凭证」页面获取 Access Key，并在执行部署命令的终端中配置；不要写入仓库文件 |
| 参数 | 一个全局唯一的 OBS 桶名、账号 Domain ID |

## 2. 打包函数代码

函数依赖 `esdk-obs-nodejs`，需随代码一起打成 zip 供 FunctionGraph 使用。

```bash
bash scripts/package-function.sh
```

**预期输出**：

```
[1/3] 安装运行时依赖到函数目录
added 14 packages in 6s
[2/3] 打包 index.js / package.json / node_modules
  files=225
[3/3] 完成
ZIP=.../build/issue-upload-url.zip
```

`infra/functions.tf` 通过 `func_code` 读取该文件，因此**必须先打包再执行 `terraform plan` / `apply`**。

## 3. 配置部署参数

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

编辑 `infra/terraform.tfvars`，填入实际值：

| 变量 | 说明 |
|---|---|
| `obs_bucket_name` | 全局唯一的桶名，只能包含小写字母、数字与连字符 |
| `domain_id` | 账号 Domain ID，用于 OBS 桶策略声明可写主体 |
| `app_name` | 资源名前缀，默认 `obs-signed-url-upload` |
| `cors_allowed_origins` | 允许跨域直传的来源，默认 `["*"]`；生产环境建议改为具体站点 |
| `signed_url_expires` | 授权 URL 有效期（秒），默认 `900` |
| `upload_content_type` | 参与签名的内容类型，默认 `image/jpeg` |
| `apig_availability_zones` | 网关实例可用区，默认 `["cn-north-4a"]` |
| `enable_public_api` | 是否创建网关专享实例与公网入口，默认 `true`；设为 `false` 进入轻量验证档 |

> `infra/terraform.tfvars` 已被 `.gitignore` 排除，不会进入版本库。

## 4. 初始化与部署

```bash
cd infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

```bash
terraform validate
```

**预期输出**：`Success! The configuration is valid.`

```bash
terraform plan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`（N 为本次需创建的资源数）

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

> 网关专享实例创建通常需要数分钟，请等待 apply 完全结束。

### 4.1 轻量验证档

只需验证「签发授权 URL → 对象直传」这条链路时，可在命令行覆盖开关，不改动任何文件：

```bash
terraform plan  -var enable_public_api=false
terraform apply -auto-approve -var enable_public_api=false
```

该档只创建 4 个资源：云服务委托、签发函数、OBS 私有桶、桶策略；不创建网关实例、分组、API、发布动作以及 VPC / 子网 / 安全组。授权 URL 改由直接调用函数取得，文件字节仍由客户端 PUT 到 OBS 公网端点，函数不接触文件体。

| 对比项 | 完整档（默认） | 轻量验证档 |
|---|---|---|
| 网关实例与公网入口 | 创建 | 不创建 |
| VPC / 子网 / 安全组 | 创建 | 不创建 |
| 云服务委托 / 函数 / OBS 桶 / 桶策略 | 创建 | 创建 |
| 授权 URL 的取得方式 | 浏览器请求 `GET /upload-url` | 直接调用函数 |
| 对象直传链路 | 一致 | 一致 |

> 轻量验证档没有对外授权接口，`src/frontend/index.html` 演示页在该档下不可用；完成链路验证后，若需要浏览器演示，把开关改回 `true` 重新 apply 即可。

## 5. 获取访问地址

```bash
terraform output
```

| 输出 | 用途 |
|---|---|
| `api_endpoint` | 浏览器调用的授权接口完整地址 |
| `internal_api_domain` | 网关分组的内网域名，格式为 `<分组ID>.apic.<region>.huaweicloudapis.com` |
| `obs_bucket_name` | 接收直传对象的桶名 |
| `function_name` | 签发函数名，用于日志检索 |
| `agency_name` | 函数使用的云服务委托名 |

若 `api_endpoint` 返回「公网入口未启用」，说明实例未分配到公网入口地址；请检查 `apig_ingress_bandwidth_size` 与 `apig_ingress_bandwidth_charging_mode` 是否成对配置，或改用同 VPC 内的内网域名访问。

## 6. 验证

### 6.1 本地端到端（无需云端资源）

```bash
node scripts/local-e2e/run_e2e.js
```

该命令使用真实 OBS SDK 生成授权 URL，并验证浏览器直传的请求形状、签名参数、临时凭据标识、有效期、跨域响应头与负向用例。

**预期输出**：`=== 汇总: 15 passed, 0 failed ===`

### 6.2 云端接口（部署完成后执行）

```bash
API=$(terraform -chdir=infra output -raw api_endpoint)
curl -sS "$API" | python -m json.tool
```

**预期输出**：

```json
{
  "uploadURL": "https://<bucket>.obs.cn-north-4.myhuaweicloud.com/<id>.jpg?AccessKeyId=...&Expires=...&x-obs-security-token=...&Signature=...",
  "photoFilename": "<id>.jpg"
}
```

### 6.3 浏览器直传（部署完成后执行）

```bash
URL=$(curl -sS "$API" | python -c "import json,sys; print(json.load(sys.stdin)['uploadURL'])")
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X PUT -H 'Content-Type: image/jpeg' \
  --data-binary @photo.jpg "$URL"
```

**预期输出**：`200`

也可以在浏览器中打开 `src/frontend/index.html`，填入授权接口地址并选择一张 JPEG 图片，页面会完成「请求授权 → 直传」两步。若从 `file://` 打开时接口跨域被拦截，请用任意静态服务器托管该目录。

### 6.4 核对对象

对象名即接口返回的 `photoFilename`。可在控制台对应桶中查看，或另行签发 GET 授权 URL 读取；桶保持私有，不提供匿名访问。

### 6.5 轻量验证档：直接调用函数

该档没有对外授权接口，改为直接触发函数取得授权 URL：

1. 取得函数名：`terraform -chdir=infra output -raw function_name`。
2. 在 FunctionGraph 控制台打开该函数 → 「代码」页 → 「配置测试事件」→ 新建空事件 `{}` → 保存并点击「测试」。
3. 从执行结果中取出 `uploadURL` 与 `photoFilename`。也可使用任意支持请求签名的 SDK 或 CLI 调用同步执行接口，函数 URN 由 `terraform -chdir=infra output -raw function_urn` 给出。

把 `uploadURL` 代入 6.3 的命令，再用 6.4 的方法核对对象：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X PUT -H 'Content-Type: image/jpeg' \
  --data-binary @photo.jpg "<uploadURL>"
```

**预期结果**：返回 `200`，桶中出现同名对象且字节一致。对象直传仍走 OBS 公网端点，与完整档完全相同；唯一差别是授权 URL 由直接调用函数取得，而非经对外接口取得。

## 7. 排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `createSignedUrlSync is not a function` | 函数包未包含新版 OBS SDK | 重跑 `scripts/package-function.sh` 后重新 `terraform apply` |
| 函数返回 500，`temporary credentials are unavailable` | 委托未绑定或未就绪 | 核对 `infra/functions.tf` 的 `agency` 与 `depends_on`，重新 apply |
| `FSS.1501 The delegate not exist` | IAM 委托生效有延迟 | 委托已建好后重新执行 `terraform apply` |
| `APIG.3205 environment name already exists` | 重复创建实例自带的 `RELEASE` 环境 | 不自建同名环境，发布资源使用固定环境 ID |
| 接口返回 `The API does not exist or has not been published` | API 未发布，或访问域名写成 `apig` 而非 `apic` | 确认 `huaweicloud_apig_api_publishment` 已创建，并核对内网域名拼写 |
| 公网无法解析内网域名 | 专享实例默认只有 VPC 内网入口 | 使用 `api_endpoint` 公网地址；仅在同 VPC 内才使用内网域名 |
| PUT 返回 403 `SignatureDoesNotMatch` | 请求头 `Content-Type` 与签名时不一致、URL 已过期或桶策略未放行 | 保持 `image/jpeg` 一致、重新取 URL、检查 `huaweicloud_obs_bucket_policy` |
| 浏览器控制台报 CORS 错误 | 桶跨域规则或接口跨域开关缺失 | 同时检查 `infra/storage.tf` 的 `cors_rule` 与 `infra/apig.tf` 的 `cors = true` |
| `terraform plan` 报找不到函数 zip | 未先执行打包脚本 | 先跑 `bash scripts/package-function.sh` |

## 8. 清理资源

```bash
cd infra
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

轻量验证档请补上部署时使用的同一个开关：

```bash
terraform destroy -auto-approve -var enable_public_api=false
```

> 销毁前请确认桶内对象可一并释放（`force_destroy = true` 已启用）。若曾通过控制台或脚本另外创建过资源（例如手工绑定的弹性公网 IP、手工上传的对象），需单独删除，避免残留。
