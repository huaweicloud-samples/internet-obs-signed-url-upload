# internet-obs-signed-url-upload / Direct-to-OBS Image Uploads

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-FunctionGraph-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> [中文版](README.cn.md)

> A function issues a time-limited upload authorization URL; the browser writes the image straight to Object Storage Service (OBS).

---

## 1. Introduction / Overview

This practice implements a serverless pattern in which the backend issues authorization only and the client transfers the file. A web page requests a PUT authorization URL for a single object, then sends the image bytes directly to object storage. The function never handles the file body and never holds long-lived keys. It is intended for backend, frontend, and DevOps engineers as a reference architecture and learning sample.

### Key Capabilities

- **On-demand issuance**: each request makes FunctionGraph generate a random object name and a signed PUT authorization URL.
- **No payload relay**: the browser uploads to OBS directly; no application server receives, buffers, or forwards file bytes.
- **Temporary credentials**: an IAM cloud service agency supplies temporary AK / SK / SecurityToken at runtime, rotated by the platform.
- **Narrow authorization scope**: each URL is bound to one object, one HTTP method, one content type, and a validity period; the bucket stays private.

---

## 2. Contents

- [1. Introduction / Overview](#1-introduction--overview)
- [2. Contents](#2-contents)
- [3. Architecture](#3-architecture)
- [4. Highlights](#4-highlights)
- [5. Cloud Services](#5-cloud-services)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Details](#11-details)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)

---

## 3. Architecture

> Control and data flows are separated: the API returns authorization only, while image bytes travel directly to object storage.

```
                         ┌──────────────────┐
                         │    User browser  │
                         │ Select JPEG file │
                         └─────────┬────────┘
                                   │ (1) GET /upload-url
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                    APIG dedicated instance (public entry)          │
│       GET /upload-url - CORS enabled - synchronous invoke          │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│          FunctionGraph  issue-upload-url (Node.js 18)              │
│   Read temp credentials -> sign object PUT URL (15 min)            │
│   Return uploadURL + photoFilename only; never handles bytes       │
└───────────┬─────────────────────────────────────┬──────────────────┘
            │ return JSON                         │ read temp creds
            ▼                                     ▼
┌────────────────────────────┐    ┌──────────────────────────────────┐
│ Browser direct upload      │    │ IAM cloud service agency         │
│ (2) PUT bytes -> OBS       │    │ Temp AK / SK / SecurityToken     │
└──────────────┬─────────────┘    └──────────────────────────────────┘
               │ (2) https://<bucket>.obs.<region>/<key>
               ▼
┌────────────────────────────────────────────────────────────────────┐
│               OBS private bucket (CORS rule allows PUT)            │
│  Key <random>.jpg - bucket stays private - function sees no bytes  │
└────────────────────────────────────────────────────────────────────┘
```

**Lightweight verification profile** (`-var enable_public_api=false`): the gateway instance, its public entry point, and the network resources are not created; the function is invoked directly.

```
                         ┌──────────────────┐
                         │  Invoke function │
                         │ (console or CLI) │
                         └─────────┬────────┘
                                   │ (1) trigger signing
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│          FunctionGraph  issue-upload-url (Node.js 18)              │
│   Read temp credentials -> sign object PUT URL (15 min)            │
└───────────────────────────┬────────────────────────────────────────┘
                            │ (2) return uploadURL + photoFilename
                            ▼
┌────────────────────────────────────────────────────────────────────┐
│              Client PUTs bytes with the signed URL                 │
│              https://<bucket>.obs.<region>/<key>                   │
└───────────────────────────┬────────────────────────────────────────┘
                            │ (3) OBS validates signature, writes object
                            ▼
┌────────────────────────────────────────────────────────────────────┐
│               OBS private bucket (CORS rule allows PUT)            │
│  Private bucket - function sees no bytes - no keys on disk         │
└────────────────────────────────────────────────────────────────────┘
```

The component responsibilities, workflow, and security design are documented in [`docs/architecture.md`](docs/architecture.md).

**Key components**:

- **API Gateway (APIG) dedicated instance**: exposes `GET /upload-url`, enables CORS, and invokes the function synchronously.
- **FunctionGraph**: generates the PUT authorization URL and returns only the URL and object name.
- **Object Storage Service (OBS)**: private bucket with a CORS rule that allows browser PUT requests.
- **Identity and Access Management (IAM)**: cloud service agency that supplies temporary credentials at runtime.

---

## 4. Highlights

- **Serverless**: the function runs per request; no servers or resident processes to manage.
- **Short path**: authorization and upload take two steps, and the file never passes through the application layer.
- **Secure defaults**: private bucket, temporary credentials, single-object authorization, and a no-store response header.
- **One-command deployment**: every resource is declared in Terraform, with a packaging script and local end-to-end checks included.

---

## 5. Cloud Services

| Service | Purpose | Notes |
|---|---|---|
| FunctionGraph | Issues object upload authorization URLs on demand | Node.js 18 runtime, 128 MB / 10 s |
| API Gateway (APIG) | Exposes the authorization API | BASIC dedicated edition, CORS enabled, explicitly published |
| Object Storage Service (OBS) | Receives browser-uploaded image objects | Private bucket with CORS rule and bucket policy |
| Identity and Access Management (IAM) | Cloud service agency for temporary credentials | Delegated service `op_svc_cff` |
| Virtual Private Cloud (VPC) | Hosts the dedicated gateway instance | Includes a subnet and a security group |

> **Note**: all services above are created by the Terraform configuration in this repository. For cleanup, see [Section 10](#10-cleanup).

---

## 6. Prerequisites

| Item | Requirement | Notes |
|---|---|---|
| **Account** | An activated Huawei Cloud account with real-name verification | Must be allowed to create VPC / APIG / FunctionGraph / OBS / IAM agencies |
| **Permissions** | Tenant Administrator or equivalent | Required for the gateway instance and the cloud service agency |
| **Region** | `cn-north-4` recommended | Changing the region also changes availability zones and the OBS endpoint |
| **Terraform** | `>= 1.5.0` | IaC deployment tool |
| **huaweicloud Provider** | `>= 1.97.0` | Huawei Cloud Terraform provider |
| **Node.js / npm** | Node.js `>= 18` | Packages function runtime dependencies |
| **Python** | `>= 3.8` | Generates the function code zip |
| **Access keys** | Obtain an Access Key from **My Credentials** in the Huawei Cloud console and configure it in the deployment terminal | Do not write credentials into any repository file |

---

## 7. Quick Start

```bash
# 1. Clone this repository
git clone <repo-https-url> internet-obs-signed-url-upload
cd internet-obs-signed-url-upload

# 2. Package the function code and dependencies
bash scripts/package-function.sh

# 3. Prepare deployment variables (globally unique bucket name and account Domain ID)
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit infra/terraform.tfvars

# 4. Configure access keys in the deployment terminal
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 5. Deploy
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> Creating a dedicated gateway instance usually takes several minutes. Full steps and expected output for each stage are in [Section 8](#8-step-by-step-deployment) and [`docs/deployment-guide.md`](docs/deployment-guide.md).
>
> **Lightweight verification profile**: append `-var enable_public_api=false` to the `terraform plan` and `terraform apply` commands to skip the gateway instance, its public entry point, and the VPC resources. The function is then invoked directly and the upload still goes straight to OBS. See [Section 9](#9-usage--verification).

---

## 8. Step-by-Step Deployment

### Step 1: Package the function

```bash
bash scripts/package-function.sh
```

**Expected output**: `ZIP=.../build/issue-upload-url.zip` containing `index.js`, `package.json`, and `node_modules`.

### Step 2: Initialize the working directory

```bash
cd infra
terraform init
```

**Expected output**: `Terraform has been successfully initialized!`

### Step 3: Preview the changes

```bash
terraform validate && terraform plan
```

**Expected output**: `Success! The configuration is valid.` and `Plan: N to add, 0 to change, 0 to destroy.`

### Step 4: Apply

```bash
terraform apply -auto-approve
```

**Expected output**: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

For the lightweight verification profile, use the same command with the switch appended. Keep the identical `-var` value for `plan`, `apply`, and `destroy`:

```bash
terraform apply -auto-approve -var enable_public_api=false
```

### Step 5: Record the outputs

```bash
terraform output
```

**Expected output**: lists `api_endpoint`, `obs_bucket_name`, `function_name`, `function_urn`, `agency_name`, and other fields. Keep `api_endpoint` for the full profile, or `function_name` / `function_urn` for the lightweight profile.

---

## 9. Usage / Verification

### Check 1: Local end-to-end (executed)

```bash
node scripts/local-e2e/run_e2e.js
```

**Expected output** (excerpt):

```
=== Signed URL issuance (FunctionGraph handler) ===
  PASS  URL carries signature, expiry and temporary credential identifier
  PASS  Token in URL matches the value supplied by the function agency
  PASS  Signature covers Content-Type (the PUT request must send the same value)
=== Browser direct upload (upload.js + injected fetch) ===
  PASS  PUT to the signed URL preserves bytes and content type
=== Summary: 15 passed, 0 failed ===
```

### Check 2: Terraform validation (executed)

```bash
terraform -chdir=infra validate
```

**Expected output**: `Success! The configuration is valid.`

### Check 3: Cloud authorization API (run after deployment)

```bash
API=$(terraform -chdir=infra output -raw api_endpoint)
curl -sS "$API" | python -m json.tool
```

**Expected output**:

```json
{
  "uploadURL": "https://<bucket>.obs.cn-north-4.myhuaweicloud.com/<id>.jpg?AccessKeyId=...&Expires=...&x-obs-security-token=...&Signature=...",
  "photoFilename": "<id>.jpg"
}
```

### Check 4: Browser direct upload (run after deployment)

```bash
URL=$(curl -sS "$API" | python -c "import json,sys; print(json.load(sys.stdin)['uploadURL'])")
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X PUT -H 'Content-Type: image/jpeg' \
  --data-binary @photo.jpg "$URL"
```

**Expected result**: `200`, and the object appears in the bucket under the returned `photoFilename`. You can also open `src/frontend/index.html` in a browser, enter the authorization API address, and pick a JPEG file to run the same two steps.

### Check 3 alternative: direct function invocation (lightweight profile)

With `-var enable_public_api=false` there is no public authorization API, so the function is invoked directly:

1. Read the function name with `terraform -chdir=infra output -raw function_name`.
2. In the FunctionGraph console, open that function, create a test event with an empty `{}` body, and run it.
3. Copy `uploadURL` from the result and use it in Check 4's `curl -X PUT` command. Any SDK or CLI that signs requests can call the synchronous invocation API instead; the URN is in `terraform output function_urn`.

The upload leg is unchanged: the client still PUTs bytes straight to OBS and the function never sees the file body. The `src/frontend/index.html` demo page needs the public API and is not available in this profile. Full steps are in section 6.5 of [`docs/deployment-guide.md`](docs/deployment-guide.md).

> After deployment, please follow the steps in this section to verify the deployment yourself and confirm that the feature works before treating delivery as complete. Checks 1 and 2 are local checks already executed for this repository; checks 3 and 4 (or the direct-invocation alternative plus Check 4) require a completed `terraform apply`. See [`docs/deployment-guide.md`](docs/deployment-guide.md).

---

## 10. Cleanup

```bash
cd infra
terraform destroy -auto-approve
```

**Expected output**: `Destroy complete! Resources: N destroyed.`

> **Avoid leftovers**: `terraform destroy` releases only resources tracked in Terraform state. Resources created separately through the console or scripts (for example a manually bound Elastic IP or manually uploaded objects) must be deleted individually.

---

## 11. Details

### Workflow

1. The browser sends `GET /upload-url`; APIG invokes the FunctionGraph function synchronously.
2. The function reads the temporary credentials from the agency, generates a random object name, and computes a signed authorization URL for the PUT method.
3. The function returns `uploadURL` and `photoFilename` with a CORS response header and `Cache-Control: no-store`.
4. The browser sends the JPEG bytes with PUT directly to that URL; OBS validates the signature, expiry, and temporary credential identifier before storing the object.

### Configuration

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Deployment region |
| `app_name` | `obs-signed-url-upload` | Resource name prefix |
| `obs_bucket_name` | none (required) | Globally unique bucket name |
| `domain_id` | none (required) | Account Domain ID used by the bucket policy |
| `cors_allowed_origins` | `["*"]` | Origins allowed to upload cross-origin |
| `signed_url_expires` | `900` | Authorization URL validity in seconds |
| `upload_content_type` | `image/jpeg` | Content type included in the signature; must match the browser PUT header |
| `enable_public_api` | `true` | Create the gateway instance and public entry point; `false` selects the lightweight direct-invocation profile |

### API

| Item | Value |
|---|---|
| Method / path | `GET /release/upload-url` |
| Authentication | None (for teaching purposes) |
| Request parameters | None |
| Success response | `200`, `{"uploadURL": "https://...", "photoFilename": "<id>.jpg"}` |
| Failure response | `500`, `{"error": "..."}` |

`Expires` in `uploadURL` is an absolute Unix timestamp in seconds. The OBS SDK puts `x-obs-security-token` into the signed URL automatically, so the browser needs no extra header, but it must send the same `Content-Type` used for signing.

---

## 12. Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC orchestration |
| huaweicloud Provider | `>= 1.97.0` | Huawei Cloud resources |
| Node.js | `>= 18` | Function runtime and packaging environment |
| `esdk-obs-nodejs` | `^3.26.2` | Generates object upload authorization URLs |
| Python | `>= 3.8` | Builds the function code zip |

---

## 13. FAQ / Troubleshooting

### Q1: Why does the function package include the OBS SDK?

**A**: The SDK bundled with the runtime is older; its signed URL API puts the temporary credential identifier in a request header, which forces the browser to send an extra header during direct upload. Packaging a newer version makes the authorization URL self-contained, preserving the "one URL is enough to upload" flow.

### Q2: Why does PUT return 403 with a signature mismatch?

**A**: The most common cause is a `Content-Type` header that differs from the value used for signing, followed by an expired URL. Keep `image/jpeg` consistent and request a fresh URL. If the failure persists, check that the bucket policy allows the account domain principal.

### Q3: Why is the API domain `apic` rather than `apig`?

**A**: The default internal domain of a dedicated gateway instance uses the `apic` segment and is reachable only inside the VPC. For public access, use the `api_endpoint` value from `terraform output`.

### Troubleshooting checklist

| Symptom | Likely cause | Action |
|---|---|---|
| API returns 404 / not published | API not published, or the domain is misspelled | Check the publishment resource and the domain spelling |
| Function returns 500 with credentials unavailable | Agency not attached or not yet effective | Verify `agency` and re-apply |
| Browser reports a CORS error | Bucket CORS rule or API CORS switch missing | Check both `cors_rule` and `cors = true` |
| `terraform plan` cannot find the function zip | Packaging script not run first | Re-run `scripts/package-function.sh` |

---

## 14. Contributing

Issues and pull requests are welcome. Please follow this flow:

1. **Issue**: describe the problem or suggestion with reproduction commands and expected versus actual output.
2. **PR**: create a feature branch from `main`; before submitting, run `terraform fmt -check -recursive infra`, `terraform -chdir=infra validate`, and `node scripts/local-e2e/run_e2e.js`.
3. **Code Review**: merged after review by [@<github-username>](https://github.com/<github-username>).

---

## 15. License

This practice is released under the **MIT No Attribution** license. See the root [`LICENSE`](LICENSE) file.

```
MIT No Attribution

Copyright Huawei Cloud. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.
```

---

## 16. Contact / Maintainers

| Item | Value |
|---|---|
| **Created by** | [@<github-username>](https://github.com/<github-username>) |
| **Maintained by** | [@<github-username>](https://github.com/<github-username>) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contributing)) |
