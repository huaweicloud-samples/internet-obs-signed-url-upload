'use strict';

// 按需签发对象上传授权 URL。
// 函数只做签名计算并返回 URL，文件字节由浏览器直接写入 OBS，不经过本函数。
const ObsClient = require('esdk-obs-nodejs');

const DEFAULT_CONTENT_TYPE = 'image/jpeg';
const DEFAULT_EXTENSION = 'jpg';
const DEFAULT_EXPIRES = 900;

// FunctionGraph 通过 IAM 云服务委托下发临时凭据；本地联调时由运行环境提供同名变量。
function readCredentials(context) {
  const ctx = context || {};
  const pick = (methodNames, envName) => {
    for (const name of methodNames) {
      if (typeof ctx[name] === 'function') {
        try {
          const value = ctx[name]();
          if (value) return value;
        } catch (err) {
          // 当前运行时不提供该方法时继续尝试下一个
        }
      }
    }
    return process.env[envName] || '';
  };

  return {
    accessKeyId: pick(['getSecurityAccessKey', 'getAccessKey'], 'HUAWEICLOUD_ACCESS_KEY'),
    secretAccessKey: pick(['getSecuritySecretKey', 'getSecretKey'], 'HUAWEICLOUD_SECRET_KEY'),
    securityToken: pick(['getSecurityToken', 'getToken'], 'HUAWEICLOUD_SECURITY_TOKEN'),
  };
}

function newObjectName() {
  // 与页面约定一致：随机十进制 ID + 固定扩展名，保证每次请求唯一。
  const id = Math.floor(Math.random() * 10000000);
  return `${id}.${process.env.UPLOAD_EXTENSION || DEFAULT_EXTENSION}`;
}

function reply(statusCode, payload) {
  return {
    statusCode,
    isBase64Encoded: false,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': process.env.CORS_ALLOW_ORIGIN || '*',
      'Cache-Control': 'no-store',
    },
    body: JSON.stringify(payload),
  };
}

exports.handler = async (event, context) => {
  const bucket = process.env.OBS_BUCKET;
  const endpoint = process.env.OBS_ENDPOINT;
  const contentType = process.env.UPLOAD_CONTENT_TYPE || DEFAULT_CONTENT_TYPE;
  const expires = Number(process.env.UPLOAD_EXPIRES || DEFAULT_EXPIRES);

  if (!bucket || !endpoint) {
    return reply(500, { error: 'OBS_BUCKET and OBS_ENDPOINT must be configured' });
  }

  const credentials = readCredentials(context);
  if (!credentials.accessKeyId || !credentials.secretAccessKey) {
    return reply(500, { error: 'temporary credentials are unavailable; attach an IAM agency to the function' });
  }

  const client = new ObsClient({
    access_key_id: credentials.accessKeyId,
    secret_access_key: credentials.secretAccessKey,
    security_token: credentials.securityToken || undefined,
    server: endpoint,
  });

  const key = newObjectName();
  const result = client.createSignedUrlSync({
    Method: 'PUT',
    Bucket: bucket,
    Key: key,
    Expires: expires,
    Headers: { 'Content-Type': contentType },
  });

  if (!result || !result.SignedUrl) {
    return reply(500, { error: 'failed to issue an upload URL' });
  }

  // 默认 OBS 签名会把临时凭据标识写入 URL query，浏览器无需附加额外请求头。
  return reply(200, {
    uploadURL: result.SignedUrl,
    photoFilename: key,
  });
};
