'use strict';

// 浏览器直传动作的唯一实现：把文件字节 PUT 到函数签发的授权 URL。
// 抽出为可注入 fetch 的纯函数，便于在 Node.js 中验证请求形状。
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.uploadClient = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  async function putToSignedUrl(url, bytes, contentType, fetchImpl) {
    const doFetch = fetchImpl || (typeof fetch === 'function' ? fetch : null);
    if (!doFetch) throw new Error('fetch is not available in this environment');
    if (!url) throw new Error('signed URL is required');

    const response = await doFetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': contentType },
      body: bytes,
    });

    if (!response.ok) {
      throw new Error('upload failed with status ' + response.status);
    }
    return response.status;
  }

  return { putToSignedUrl };
});
