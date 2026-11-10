'use strict';

// 本地端到端验证：用真实 OBS SDK 生成授权 URL，并验证浏览器直传的请求形状。
// 运行前先执行 scripts/package-function.sh 安装运行时依赖。
const assert = require('assert');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const FUNCTION = path.join(ROOT, 'src', 'functions', 'issue-upload-url', 'index.js');
const UPLOAD_CLIENT = path.join(ROOT, 'src', 'frontend', 'upload.js');

process.env.OBS_BUCKET = 'local-test-bucket';
process.env.OBS_ENDPOINT = 'https://obs.cn-north-4.myhuaweicloud.com';
process.env.UPLOAD_EXPIRES = '900';
process.env.UPLOAD_CONTENT_TYPE = 'image/jpeg';
process.env.CORS_ALLOW_ORIGIN = '*';

// 显式假值：含下划线，不会被误识别为真实凭据形态。
const FAKE_AK = 'LOCAL_TEST_AK';
const FAKE_SK = 'LOCAL_TEST_SK';
const FAKE_TOKEN = 'LOCAL_TEST_SECURITY_TOKEN';

const { handler } = require(FUNCTION);
const { putToSignedUrl } = require(UPLOAD_CLIENT);

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log('  PASS  ' + name);
    passed += 1;
  } catch (err) {
    console.log('  FAIL  ' + name + ' -> ' + err.message);
    failed += 1;
  }
}

function fakeContext() {
  return {
    getSecurityAccessKey: () => FAKE_AK,
    getSecuritySecretKey: () => FAKE_SK,
    getSecurityToken: () => FAKE_TOKEN,
    getRequestID: () => 'local-e2e-request',
  };
}

function parseBody(result) {
  return JSON.parse(result.body);
}

async function main() {
  console.log('=== 授权 URL 签发链路（FunctionGraph handler）===');

  const result = await handler({}, fakeContext());
  const body = parseBody(result);
  const signed = new URL(body.uploadURL);

  await check('返回 200 与标准 HTTP 响应结构', () => {
    assert.strictEqual(result.statusCode, 200);
    assert.strictEqual(result.isBase64Encoded, false);
    assert.strictEqual(result.headers['Content-Type'], 'application/json');
  });

  await check('响应带跨域头与禁用缓存头', () => {
    assert.strictEqual(result.headers['Access-Control-Allow-Origin'], '*');
    assert.strictEqual(result.headers['Cache-Control'], 'no-store');
  });

  await check('响应体包含 uploadURL 与 photoFilename', () => {
    assert.ok(body.uploadURL.startsWith('https://'));
    assert.ok(body.photoFilename.length > 0);
  });

  await check('授权 URL 指向 OBS 桶中的目标对象', () => {
    assert.strictEqual(signed.hostname, 'local-test-bucket.obs.cn-north-4.myhuaweicloud.com');
    assert.strictEqual(signed.pathname, '/' + body.photoFilename);
  });

  await check('URL 自带签名、有效期与临时凭据标识', () => {
    for (const key of ['AccessKeyId', 'Expires', 'Signature', 'x-obs-security-token']) {
      assert.ok(signed.searchParams.has(key), 'missing query parameter: ' + key);
    }
  });

  await check('临时凭据标识与函数委托下发的值一致', () => {
    assert.strictEqual(signed.searchParams.get('x-obs-security-token'), FAKE_TOKEN);
  });

  await check('有效期为「当前时间 + 900 秒」的绝对时间戳', () => {
    // OBS 签名的 Expires 是 Unix 秒级时间戳，不是相对秒数。
    const expiresAt = Number(signed.searchParams.get('Expires'));
    const now = Math.floor(Date.now() / 1000);
    assert.ok(expiresAt >= now + 890 && expiresAt <= now + 900,
      'unexpected expiry window: ' + expiresAt + ' vs now=' + now);
  });

  await check('对象名格式为随机数字 ID + .jpg', () => {
    assert.match(body.photoFilename, /^\d+\.jpg$/);
  });

  await check('每次请求生成不同对象名', async () => {
    const another = parseBody(await handler({}, fakeContext()));
    assert.notStrictEqual(another.photoFilename, body.photoFilename);
  });

  await check('签名覆盖 Content-Type（PUT 请求须携带一致的值）', () => {
    const ObsClient = require(path.join(ROOT, 'src', 'functions', 'issue-upload-url', 'node_modules', 'esdk-obs-nodejs'));
    const client = new ObsClient({
      access_key_id: FAKE_AK,
      secret_access_key: FAKE_SK,
      security_token: FAKE_TOKEN,
      server: process.env.OBS_ENDPOINT,
    });
    const sample = client.createSignedUrlSync({
      Method: 'PUT',
      Bucket: process.env.OBS_BUCKET,
      Key: body.photoFilename,
      Expires: 900,
      Headers: { 'Content-Type': 'image/jpeg' },
    });
    assert.strictEqual(sample.ActualSignedRequestHeaders['Content-Type'], 'image/jpeg');
    assert.ok(sample.SignedUrl.includes('x-obs-security-token'));
  });

  await check('缺少临时凭据时返回 500 且不出具 URL', async () => {
    const saved = ['HUAWEICLOUD_ACCESS_KEY', 'HUAWEICLOUD_SECRET_KEY', 'HUAWEICLOUD_SECURITY_TOKEN'];
    const backup = saved.map((k) => process.env[k]);
    saved.forEach((k) => delete process.env[k]);
    try {
      const denied = await handler({}, {});
      assert.strictEqual(denied.statusCode, 500);
      assert.ok(!parseBody(denied).uploadURL);
    } finally {
      saved.forEach((k, i) => { if (backup[i] !== undefined) process.env[k] = backup[i]; });
    }
  });

  await check('本地联调可通过运行环境提供凭据', async () => {
    process.env.HUAWEICLOUD_ACCESS_KEY = FAKE_AK;
    process.env.HUAWEICLOUD_SECRET_KEY = FAKE_SK;
    process.env.HUAWEICLOUD_SECURITY_TOKEN = FAKE_TOKEN;
    try {
      const fallback = await handler({}, {});
      assert.strictEqual(fallback.statusCode, 200);
      assert.ok(new URL(parseBody(fallback).uploadURL).searchParams.has('x-obs-security-token'));
    } finally {
      delete process.env.HUAWEICLOUD_ACCESS_KEY;
      delete process.env.HUAWEICLOUD_SECRET_KEY;
      delete process.env.HUAWEICLOUD_SECURITY_TOKEN;
    }
  });

  await check('缺少桶配置时返回 500', async () => {
    const saved = process.env.OBS_BUCKET;
    delete process.env.OBS_BUCKET;
    try {
      const denied = await handler({}, fakeContext());
      assert.strictEqual(denied.statusCode, 500);
    } finally {
      process.env.OBS_BUCKET = saved;
    }
  });

  console.log('=== 浏览器直传链路（upload.js + 注入的 fetch）===');

  const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

  await check('PUT 到授权 URL，字节与内容类型原样送达', async () => {
    let captured = null;
    const fakeFetch = async (url, options) => {
      captured = { url, options };
      return { ok: true, status: 200 };
    };
    const status = await putToSignedUrl(body.uploadURL, bytes, 'image/jpeg', fakeFetch);
    assert.strictEqual(status, 200);
    assert.strictEqual(captured.url, body.uploadURL);
    assert.strictEqual(captured.options.method, 'PUT');
    assert.strictEqual(captured.options.headers['Content-Type'], 'image/jpeg');
    assert.strictEqual(captured.options.body, bytes);
    assert.ok(captured.url.includes('x-obs-security-token'));
  });

  await check('服务端拒绝时抛出错误', async () => {
    const fakeFetch = async () => ({ ok: false, status: 403 });
    await assert.rejects(() => putToSignedUrl(body.uploadURL, bytes, 'image/jpeg', fakeFetch), /403/);
  });

  console.log('');
  console.log('=== 汇总: ' + passed + ' passed, ' + failed + ' failed ===');
  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('E2E runner error:', err);
  process.exitCode = 1;
});
