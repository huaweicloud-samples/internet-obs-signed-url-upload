# internet-obs-signed-url-upload / 图片直传对象存储最佳实践

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-FunctionGraph-red.svg)](https://support.huaweicloud.com/intl/zh-cn/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> [English](README.md)

> 用函数签发有时效的对象上传授权 URL，让浏览器把图片直接写入 OBS。

---

## 1. 简介 / Overview

本实践提供一套「服务端只签发授权、文件由客户端直传」的无服务器方案：Web 页面向接口请求一个针对单个对象的 PUT 授权 URL，再用该 URL 把图片字节直接写入对象存储。函数全程不接触文件体，也不持有长期密钥。面向后端、前端与 DevOps 工程师，可作为参考架构与教学样例使用。

### 核心能力

- **按需签发**：每次请求由 FunctionGraph 实时生成随机对象名与带签名的 PUT 授权 URL。
- **文件零中转**：浏览器直传 OBS，应用服务器不接收、不缓存、不转发文件字节。
- **临时凭据**：凭 IAM 云服务委托在运行时获取临时 AK / SK / SecurityToken，平台自动轮换。
- **最小授权面**：URL 限定对象、HTTP 方法、内容类型与有效期；桶保持私有，跨域规则按需开放。

---

## 2. 目录

- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)

---

## 3. 架构图

> 控制流与数据流分离：接口只返回授权信息，图片字节走对象存储直传链路。

```
                         ┌──────────────────┐
                         │    用户浏览器    │
                         │  选择 JPEG 图片  │
                         └─────────┬────────┘
                                   │ ① GET /upload-url
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                    APIG 专享版（公网入口）                         │
│       GET /upload-url · 跨域已开启 · 同步调用函数                  │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│          FunctionGraph  issue-upload-url（Node.js 18）             │
│   读取委托下发的临时凭据 → 生成对象 PUT 授权 URL（15 分钟）        │
│   只返回 uploadURL + photoFilename，不接收任何文件字节             │
└───────────┬─────────────────────────────────────┬──────────────────┘
            │ 返回 JSON                           │ 读取临时凭据
            ▼                                     ▼
┌────────────────────────────┐    ┌──────────────────────────────────┐
│ 浏览器用授权 URL 直传      │    │ IAM 云服务委托                   │
│ ② PUT 文件字节 → OBS       │    │ 临时 AK / SK / SecurityToken     │
└──────────────┬─────────────┘    └──────────────────────────────────┘
               │ ② https://<bucket>.obs.<region>/<key>
               ▼
┌────────────────────────────────────────────────────────────────────┐
│               OBS 私有桶（跨域规则允许 PUT）                       │
│  对象名 <random>.jpg · 桶保持私有 · 函数不接触文件字节             │
└────────────────────────────────────────────────────────────────────┘
```

**轻量验证档**（`-var enable_public_api=false`）：不创建网关实例、公网入口与配套网络资源，改为直接调用函数。

```
                         ┌──────────────────┐
                         │   直接调用函数   │
                         │  （控制台或 CLI）│
                         └─────────┬────────┘
                                   │ ① 触发签发
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│          FunctionGraph  issue-upload-url（Node.js 18）             │
│   读取委托下发的临时凭据 → 生成对象 PUT 授权 URL（15 分钟）        │
└───────────────────────────┬────────────────────────────────────────┘
                            │ ② 返回 uploadURL + photoFilename
                            ▼
┌────────────────────────────────────────────────────────────────────┐
│              客户端用授权 URL 直传（PUT 文件字节）                 │
│              https://<bucket>.obs.<region>/<key>                   │
└───────────────────────────┬────────────────────────────────────────┘
                            │ ③ 签名校验后写入对象
                            ▼
┌────────────────────────────────────────────────────────────────────┐
│               OBS 私有桶（跨域规则允许 PUT）                       │
│  桶保持私有 · 函数不接触文件字节 · 凭据不落盘                      │
└────────────────────────────────────────────────────────────────────┘
```

组件职责、工作流程与安全设计详见 [`docs/architecture.md`](docs/architecture.md)。

**关键组件说明**：

- **APIG 专享版**：对外提供 `GET /upload-url`，开启跨域并同步调用函数。
- **FunctionGraph**：生成 PUT 授权 URL，只返回 URL 与对象名。
- **OBS**：私有桶，配置跨域规则允许浏览器 PUT。
- **IAM 云服务委托**：运行时下发临时凭据，不落盘。

---

## 4. 方案亮点

- **无服务器**：函数按请求触发，无需管理服务器或常驻进程。
- **链路短**：授权与上传两步完成，文件不经过应用层。
- **安全默认**：私有桶 + 临时凭据 + 单次对象级授权 + 禁止缓存响应。
- **一键部署**：全部资源由 Terraform 声明，配套打包脚本与本地端到端验证。

---

## 5. 涉及云服务

| 服务 | 用途 | 备注 |
|---|---|---|
| 函数工作流 FunctionGraph | 实时签发对象上传授权 URL | Node.js 18 运行时，128 MB / 10 s |
| API 网关 APIG | 对外暴露授权接口 | 专享版 BASIC，开启跨域并显式发布 |
| 对象存储服务 OBS | 接收浏览器直传的图片对象 | 私有桶，配置跨域规则与桶策略 |
| 统一身份认证 IAM | 云服务委托下发临时凭据 | 委托主体 `op_svc_cff` |
| 虚拟私有云 VPC | 承载网关专享实例 | 含子网与安全组 |

> **提示**：以上服务均可通过本仓库的 Terraform 一键创建；如需清理，请参见 [第 10 节「清理资源」](#10-清理资源)。

---

## 6. 前置条件

| 项 | 要求 | 说明 |
|---|---|---|
| **账号** | 已开通华为云账号并完成实名认证 | 需具备创建 VPC / APIG / FunctionGraph / OBS / IAM 委托的权限 |
| **权限** | Tenant Administrator 或等效权限 | 用于创建网关实例与云服务委托 |
| **Region** | 推荐 `cn-north-4` | 换区域需同步调整可用区与对象存储端点 |
| **Terraform** | `>= 1.5.0` | IaC 部署工具 |
| **huaweicloud Provider** | `>= 1.97.0` | 华为云 Terraform Provider |
| **Node.js / npm** | Node.js `>= 18` | 打包函数运行时依赖 |
| **Python** | `>= 3.8` | 打包脚本生成 zip |
| **访问密钥** | 在华为云「我的凭证」页面获取 Access Key，并在执行部署命令的终端中配置 | 不要写入仓库中的任何文件 |

---

## 7. 快速开始

```bash
# 1. 克隆本仓库
git clone <repo-https-url> internet-obs-signed-url-upload
cd internet-obs-signed-url-upload

# 2. 打包函数代码与依赖
bash scripts/package-function.sh

# 3. 准备部署参数（填入全局唯一桶名与账号 Domain ID）
cp infra/terraform.tfvars.example infra/terraform.tfvars
# 编辑 infra/terraform.tfvars

# 4. 在部署终端中配置访问密钥
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 5. 一键部署
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> 网关专享实例创建通常需要数分钟。完整步骤与每步预期输出见 [第 8 节「分步部署」](#8-分步部署) 与 [`docs/deployment-guide.md`](docs/deployment-guide.md)。
>
> **轻量验证档**：在 `terraform plan` / `terraform apply` 后追加 `-var enable_public_api=false`，即不创建网关实例、公网入口与配套网络资源；改为直接调用函数，对象仍直传 OBS。详见[第 9 节「使用方法 / 验证」](#9-使用方法--验证)。

---

## 8. 分步部署

### 步骤 1：打包函数

```bash
bash scripts/package-function.sh
```

**预期输出**：`ZIP=.../build/issue-upload-url.zip`（含 `index.js` / `package.json` / `node_modules`）。

### 步骤 2：初始化工作目录

```bash
cd infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

### 步骤 3：预演资源变更

```bash
terraform validate && terraform plan
```

**预期输出**：`Success! The configuration is valid.` 与 `Plan: N to add, 0 to change, 0 to destroy.`

### 步骤 4：执行部署

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

轻量验证档在命令后追加开关即可；`plan`、`apply`、`destroy` 三步请使用完全相同的 `-var` 值：

```bash
terraform apply -auto-approve -var enable_public_api=false
```

### 步骤 5：记录关键输出

```bash
terraform output
```

**预期输出**：列出 `api_endpoint`、`obs_bucket_name`、`function_name`、`function_urn`、`agency_name` 等字段。完整档保存 `api_endpoint`，轻量验证档保存 `function_name` / `function_urn` 供后续验证使用。

---

## 9. 使用方法 / 验证

### 验证 1：本地端到端（已实测）

```bash
node scripts/local-e2e/run_e2e.js
```

**预期输出**（节选）：

```
=== 授权 URL 签发链路（FunctionGraph handler）===
  PASS  URL 自带签名、有效期与临时凭据标识
  PASS  临时凭据标识与函数委托下发的值一致
  PASS  签名覆盖 Content-Type（PUT 请求须携带一致的值）
=== 浏览器直传链路（upload.js + 注入的 fetch）===
  PASS  PUT 到授权 URL，字节与内容类型原样送达
=== 汇总: 15 passed, 0 failed ===
```

### 验证 2：Terraform 配置校验（已实测）

```bash
terraform -chdir=infra validate
```

**预期输出**：`Success! The configuration is valid.`

### 验证 3：云端授权接口（部署完成后执行）

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

### 验证 4：浏览器直传（部署完成后执行）

```bash
URL=$(curl -sS "$API" | python -c "import json,sys; print(json.load(sys.stdin)['uploadURL'])")
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X PUT -H 'Content-Type: image/jpeg' \
  --data-binary @photo.jpg "$URL"
```

**预期结果**：返回 `200`，对象以接口给出的 `photoFilename` 出现在桶中。也可在浏览器打开 `src/frontend/index.html`，填入授权接口地址并选择 JPEG 图片完成同样的两步操作。

### 验证 3 的替代：轻量验证档直接调用函数

使用 `-var enable_public_api=false` 时不创建对外授权接口，改为直接触发函数：

1. 取得函数名：`terraform -chdir=infra output -raw function_name`。
2. 在 FunctionGraph 控制台打开该函数 → 「代码」页 → 新建内容为 `{}` 的测试事件 → 点击「测试」。
3. 从执行结果中复制 `uploadURL`，代入验证 4 的 `curl -X PUT` 命令。也可改用任意支持请求签名的 SDK / CLI 调用同步执行接口，函数 URN 见 `terraform output function_urn`。

对象直传链路完全不变：客户端仍把字节直接 PUT 到 OBS，函数不接触文件体。`src/frontend/index.html` 演示页依赖对外接口，在该档下不可用。完整步骤见 [`docs/deployment-guide.md`](docs/deployment-guide.md) 第 6.5 节。

> 部署完成后请按本节步骤自行验证，确认业务功能可用，方可视为交付完成。验证 1、2 为本仓库已实测通过的本地检查；验证 3、4（或「直接调用函数」替代方案 + 验证 4）需在 `terraform apply` 完成后执行，详见 [`docs/deployment-guide.md`](docs/deployment-guide.md)。

---

## 10. 清理资源

```bash
cd infra
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

> **避免资源残留**：`terraform destroy` 只释放 Terraform state 中追踪的资源；若曾通过控制台或脚本另外创建过资源（手工绑定的弹性公网 IP、手工上传的对象等），需单独删除。

---

## 11. 详细说明

### 工作流程

1. 浏览器 `GET /upload-url`；APIG 同步调用 FunctionGraph 函数。
2. 函数读取委托下发的临时凭据，生成随机对象名，为 `PUT` 方法计算带签名的授权 URL。
3. 函数返回 `uploadURL` 与 `photoFilename`，并设置跨域响应头与 `Cache-Control: no-store`。
4. 浏览器用 `PUT` 把 JPEG 字节直接写到该 URL；OBS 校验签名、有效期与临时凭据标识后写入对象。

### 配置项

| 变量 | 默认值 | 说明 |
|---|---|---|
| `region` | `cn-north-4` | 部署区域 |
| `app_name` | `obs-signed-url-upload` | 资源名前缀 |
| `obs_bucket_name` | 无（必填） | 全局唯一桶名 |
| `domain_id` | 无（必填） | 账号 Domain ID，用于桶策略 |
| `cors_allowed_origins` | `["*"]` | 允许跨域直传的来源 |
| `signed_url_expires` | `900` | 授权 URL 有效期（秒） |
| `upload_content_type` | `image/jpeg` | 参与签名的内容类型，须与浏览器 PUT 请求头一致 |
| `enable_public_api` | `true` | 是否创建网关实例与公网入口；`false` 为轻量验证档（直接调用函数） |

### 接口 / API

| 项 | 内容 |
|---|---|
| 方法 / 路径 | `GET /release/upload-url` |
| 认证 | 无（教学演示用途） |
| 请求参数 | 无 |
| 成功响应 | `200`，`{"uploadURL": "https://...", "photoFilename": "<id>.jpg"}` |
| 失败响应 | `500`，`{"error": "..."}` |

`uploadURL` 中 `Expires` 为 Unix 秒级绝对时间戳；`x-obs-security-token` 由 SDK 随签名 URL 自动携带，浏览器无需附加额外请求头，但必须发送与签名一致的 `Content-Type`。

---

## 12. 依赖

| 名称 | 版本 | 用途 |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC 编排 |
| huaweicloud Provider | `>= 1.97.0` | 华为云资源 |
| Node.js | `>= 18` | 函数运行时与打包环境 |
| `esdk-obs-nodejs` | `^3.26.2` | 生成对象上传授权 URL |
| Python | `>= 3.8` | 生成函数代码 zip |

---

## 13. FAQ / 故障排除

### Q1：为什么函数包里要自带 OBS SDK？

**A**：运行时内置的 SDK 版本较旧，其签名 URL 接口把临时凭据标识放在请求头里，浏览器直传时还需额外携带请求头。随包使用较新版本可让授权 URL 自包含凭据标识，保持「拿到一个 URL 即可上传」的链路。

### Q2：PUT 返回 403 签名不匹配怎么办？

**A**：最常见原因是请求头 `Content-Type` 与签名时使用的值不一致，其次是 URL 已超过有效期。保持 `image/jpeg` 一致并重新取 URL 即可；若仍失败，检查桶策略是否放行账号域内主体。

### Q3：接口域名为什么是 `apic` 而不是 `apig`？

**A**：网关专享实例的默认内网域名使用 `apic` 段，且仅在 VPC 内可达。公网访问请使用 `terraform output api_endpoint` 给出的地址。

### 故障排查清单

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| 接口 404 / 未发布 | API 未显式发布或域名写错 | 检查发布资源与域名拼写 |
| 函数 500 且提示凭据不可用 | 委托未绑定或未就绪 | 核对 `agency` 后重新 apply |
| 浏览器报 CORS 错误 | 桶跨域规则或接口跨域开关缺失 | 同时检查 `cors_rule` 与 `cors = true` |
| `terraform plan` 找不到函数 zip | 未先执行打包脚本 | 重跑 `scripts/package-function.sh` |

---

## 14. 贡献指南

欢迎提交 Issue 与 PR。请遵循以下流程：

1. **Issue**：描述问题或建议，附复现命令、预期与实际输出。
2. **PR**：基于 `main` 新建 feature 分支；提交前运行 `terraform fmt -check -recursive infra`、`terraform -chdir=infra validate` 与 `node scripts/local-e2e/run_e2e.js`。
3. **Code Review**：由 [@<github-username>](https://github.com/<github-username>) 审核通过后合并。

---

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证发布。详见仓库根目录 [`LICENSE`](LICENSE) 文件。

```
MIT No Attribution

Copyright Huawei Cloud. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.
```

---

## 16. 联系方式 / 维护者

| 项 | 内容 |
|---|---|
| **创建者** | [@<github-username>](https://github.com/<github-username>) |
| **维护者** | [@<github-username>](https://github.com/<github-username>) |
| **联系方式** | GitHub Issues / PR（见 [第 14 节](#14-贡献指南)） |
