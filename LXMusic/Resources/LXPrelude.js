/*
 * LXPrelude.js — 洛雪自定义源脚本在 iOS 上的宿主环境
 *
 * Swift 侧通过 __lxNative 注入原生能力，这里按 lx-music-desktop / lx-music-mobile
 * 的《自定义源脚本编写说明》还原 globalThis.lx，并补齐音源脚本常用的 Web/Node API。
 * 目标：让现成的洛雪音源脚本（.js）无需修改即可在 iPhone 上运行。
 */
(function () {
  'use strict';
  if (globalThis.__lxBooted) return;
  globalThis.__lxBooted = true;

  var N = globalThis.__lxNative;
  var seq = 0;
  function nextId(prefix) {
    seq += 1;
    return prefix + '_' + seq + '_' + Date.now();
  }

  // 洛雪文档：部分脚本写 JSON.parse(resp.body)，而宿主返回的 body 可能已经是对象。
  // 这里让 JSON.parse 对非字符串入参原样返回，两种写法都能兼容。
  var __jsonParse = JSON.parse;
  JSON.parse = function (text, reviver) {
    if (typeof text !== 'string') return text;
    return __jsonParse(text, reviver);
  };

  // ---------------------------------------------------------------- 编码工具
  function binaryFromU8(u8) {
    var s = '';
    var CHUNK = 0x8000;
    for (var i = 0; i < u8.length; i += CHUNK) {
      s += String.fromCharCode.apply(null, u8.subarray(i, i + CHUNK));
    }
    return s;
  }
  function u8FromBinary(s) {
    var out = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
    return out;
  }
  function b64ToU8(b64) { return u8FromBinary(N.b64decode(String(b64))); }
  function u8ToB64(u8) { return N.b64encode(binaryFromU8(u8)); }
  function utf8Encode(str) { return b64ToU8(N.utf8Encode(String(str))); }
  function utf8Decode(u8) { return N.utf8Decode(u8ToB64(u8)); }

  globalThis.btoa = globalThis.btoa || function (s) { return N.b64encode(String(s)); };
  globalThis.atob = globalThis.atob || function (s) { return N.b64decode(String(s)); };

  if (typeof globalThis.TextEncoder === 'undefined') {
    globalThis.TextEncoder = function () {
      this.encode = function (s) { return utf8Encode(s); };
    };
  }
  if (typeof globalThis.TextDecoder === 'undefined') {
    globalThis.TextDecoder = function () {
      this.decode = function (b) {
        return utf8Decode(b instanceof Uint8Array ? b : new Uint8Array(b || []));
      };
    };
  }

  // ---------------------------------------------------------------- Buffer
  var buffer = {
    from: function (data, enc) {
      if (data instanceof Uint8Array) return new Uint8Array(data);
      if (enc === 'base64') return b64ToU8(String(data));
      if (Array.isArray(data)) return new Uint8Array(data);
      if (data && data.__lxB64) return b64ToU8(data.__lxB64);
      if (data && typeof data === 'object') return utf8Encode(JSON.stringify(data));
      return utf8Encode(data == null ? '' : String(data));
    },
    bufToString: function (buf, format) {
      var u8 = buf instanceof Uint8Array ? buf : buffer.from(buf);
      return N.bufToString(u8ToB64(u8), String(format || 'utf8'));
    },
    isBuffer: function (v) { return v instanceof Uint8Array; },
    concat: function (list) {
      var total = 0;
      list.forEach(function (item) { total += item.length; });
      var out = new Uint8Array(total);
      var offset = 0;
      list.forEach(function (item) { out.set(item, offset); offset += item.length; });
      return out;
    },
    alloc: function (size) { return new Uint8Array(Number(size) || 0); }
  };
  globalThis.Buffer = globalThis.Buffer || {
    from: buffer.from,
    concat: buffer.concat,
    alloc: buffer.alloc,
    isBuffer: buffer.isBuffer,
    byteLength: function (v) { return buffer.from(v).length; }
  };

  // ---------------------------------------------------------------- Crypto
  var cryptoUtils = {
    md5: function (s) { return N.md5(String(s)); },
    sha1: function (s) { return N.sha1(String(s)); },
    randomBytes: function (size) { return b64ToU8(N.randomBytes(Number(size) || 16)); },
    aesEncrypt: function (buf, mode, key, iv) {
      var b64 = N.aesEncrypt(u8ToB64(buffer.from(buf)),
                             String(mode || 'aes-128-cbc'),
                             String(key || ''),
                             String(iv || ''));
      return b64 ? b64ToU8(b64) : new Uint8Array(0);
    },
    rsaEncrypt: function (buf, key) {
      var b64 = N.rsaEncrypt(u8ToB64(buffer.from(buf)), String(key || ''));
      return b64 ? b64ToU8(b64) : new Uint8Array(0);
    }
  };
  try {
    if (typeof globalThis.crypto === 'undefined' || globalThis.crypto === null) {
      globalThis.crypto = {};
    }
    globalThis.crypto.getRandomValues = function (arr) {
      var r = cryptoUtils.randomBytes(arr.length);
      arr.set(r);
      return arr;
    };
  } catch (e) { /* 某些系统运行时 crypto 为只读，忽略即可 */ }

  // ---------------------------------------------------------------- zlib
  var zlibCallbacks = {};
  var zlibUtils = {
    inflate: function (buf) {
      return new Promise(function (resolve, reject) {
        var id = nextId('z');
        zlibCallbacks[id] = { resolve: resolve, reject: reject };
        N.zlib(id, u8ToB64(buffer.from(buf)), false);
      });
    },
    deflate: function (buf) {
      return new Promise(function (resolve, reject) {
        var id = nextId('z');
        zlibCallbacks[id] = { resolve: resolve, reject: reject };
        N.zlib(id, u8ToB64(buffer.from(buf)), true);
      });
    }
  };
  globalThis.__lxZlibDone = function (id, ok, b64) {
    var cb = zlibCallbacks[id];
    delete zlibCallbacks[id];
    if (!cb) return;
    if (ok) cb.resolve(b64ToU8(b64));
    else cb.reject(new Error('zlib 操作失败'));
  };

  // ---------------------------------------------------------------- 日志
  function fmt(v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return v.message || String(v);
    if (typeof v === 'object') {
      try { return JSON.stringify(v); } catch (e) { return String(v); }
    }
    return String(v);
  }
  function joinArgs(args) {
    return Array.prototype.map.call(args, fmt).join(' ');
  }
  globalThis.console = {
    log: function () { N.log('log', joinArgs(arguments)); },
    info: function () { N.log('info', joinArgs(arguments)); },
    warn: function () { N.log('warn', joinArgs(arguments)); },
    error: function () { N.log('error', joinArgs(arguments)); },
    debug: function () { N.log('debug', joinArgs(arguments)); },
    group: function () { N.log('group', joinArgs(arguments)); },
    groupEnd: function () { N.log('groupEnd', ''); },
    table: function () { N.log('table', joinArgs(arguments)); },
    time: function () {},
    timeEnd: function () {},
    trace: function () { N.log('trace', joinArgs(arguments)); }
  };

  // ---------------------------------------------------------------- 定时器
  var timerFns = {};
  globalThis.setTimeout = function (fn, ms) {
    var id = nextId('t');
    timerFns[id] = fn;
    N.setTimeout(id, Number(ms) || 0, false);
    return id;
  };
  globalThis.setInterval = function (fn, ms) {
    var id = nextId('i');
    timerFns[id] = fn;
    N.setTimeout(id, Math.max(Number(ms) || 0, 20), true);
    return id;
  };
  globalThis.clearTimeout = globalThis.clearInterval = function (id) {
    var key = String(id);
    delete timerFns[key];
    N.clearTimer(key);
  };
  globalThis.__lxTimerFire = function (id, repeating) {
    var fn = timerFns[id];
    if (!fn) return;
    if (!repeating) delete timerFns[id];
    try { fn(); } catch (e) { N.log('error', 'timer: ' + fmt(e)); }
  };

  // ---------------------------------------------------------------- 事件
  var EVENT_NAMES = Object.freeze({
    inited: 'inited',
    request: 'request',
    updateAlert: 'updateAlert'
  });
  var handlers = {};

  function on(name, handler) {
    if (typeof handler === 'function') handlers[String(name)] = handler;
  }
  function send(name, data) {
    N.send(String(name), JSON.stringify(data === undefined ? null : data));
  }

  // ---------------------------------------------------------------- HTTP
  var reqCallbacks = {};

  function lxRequest(url, options, callback) {
    var id = nextId('r');
    if (typeof callback === 'function') reqCallbacks[id] = callback;
    N.request(String(url), JSON.stringify(options || {}), id);
    return function () {
      delete reqCallbacks[id];
      N.cancel(id);
    };
  }

  // Swift 完成请求后调用；resp.rawBody 为原始字符串，这里补出 body / bodyString
  globalThis.__lxRequestDone = function (id, err, resp) {
    var cb = reqCallbacks[id];
    delete reqCallbacks[id];
    var r = resp || {};
    if (r.rawBody == null) r.rawBody = '';
    var body = r.rawBody;
    if (typeof body === 'string' && body.length > 0) {
      try {
        var parsed = __jsonParse(body);
        if (parsed !== null && typeof parsed === 'object') body = parsed;
      } catch (e) { /* 非 JSON 响应保持字符串 */ }
    }
    r.body = body;
    r.bodyString = typeof body === 'string' ? body : JSON.stringify(body);
    r.text = r.bodyString;
    r.status = r.statusCode || 0;
    r.statusText = '';
    if (cb) cb(err ? new Error(String(err)) : null, r, r.body);
  };

  // ---------------------------------------------------------------- fetch
  function lxFetch(url, options) {
    return new Promise(function (resolve, reject) {
      lxRequest(String(url), options || {}, function (err, resp) {
        if (err) return reject(err instanceof Error ? err : new Error(String(err)));
        var r = resp || {};
        var text = typeof r.body === 'string' ? r.body : String(r.rawBody || '');
        var h = r.headers || {};
        resolve({
          ok: (r.statusCode >= 200 && r.statusCode < 300),
          status: r.statusCode || 0,
          statusText: '',
          url: String(url),
          headers: {
            get: function (k) { return h[String(k).toLowerCase()] || h[String(k)] || null; },
            forEach: function (fn) { Object.keys(h).forEach(function (k) { fn(h[k], k); }); }
          },
          text: function () { return Promise.resolve(text); },
          json: function () { return Promise.resolve(__jsonParse(text)); },
          arrayBuffer: function () { return Promise.resolve(utf8Encode(text).buffer); },
          clone: function () { return lxFetch(url, options); },
          body: text
        });
      });
    });
  }
  globalThis.fetch = lxFetch;
  globalThis.httpFetch = lxFetch;

  // ---------------------------------------------------------------- 其它兼容
  if (typeof globalThis.URLSearchParams === 'undefined') {
    globalThis.URLSearchParams = function (init) {
      var pairs = [];
      if (typeof init === 'string') {
        String(init).replace(/^\?/, '').split('&').forEach(function (kv) {
          if (!kv) return;
          var i = kv.indexOf('=');
          pairs.push([decodeURIComponent(i < 0 ? kv : kv.slice(0, i)),
                      decodeURIComponent(i < 0 ? '' : kv.slice(i + 1))]);
        });
      } else if (init && typeof init === 'object') {
        Object.keys(init).forEach(function (k) {
          var v = init[k];
          if (Array.isArray(v)) v.forEach(function (x) { pairs.push([k, String(x)]); });
          else pairs.push([k, String(v)]);
        });
      }
      this.append = function (k, v) { pairs.push([String(k), String(v)]); };
      this.set = function (k, v) {
        pairs = pairs.filter(function (p) { return p[0] !== k; });
        pairs.push([String(k), String(v)]);
      };
      this.get = function (k) {
        var hit = pairs.filter(function (p) { return p[0] === k; })[0];
        return hit ? hit[1] : null;
      };
      this.has = function (k) { return pairs.some(function (p) { return p[0] === k; }); };
      this.delete = function (k) { pairs = pairs.filter(function (p) { return p[0] !== k; }); };
      this.toString = function () {
        return pairs.map(function (p) {
          return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
        }).join('&');
      };
    };
  }
  if (typeof globalThis.process === 'undefined') {
    globalThis.process = {
      env: {},
      platform: 'ios',
      version: '1.0.0',
      nextTick: function (fn) { globalThis.setTimeout(fn, 0); }
    };
  }

  // ---------------------------------------------------------------- globalThis.lx
  var scriptInfo = {};
  try { scriptInfo = __jsonParse(N.currentScriptInfo() || '{}'); } catch (e) { scriptInfo = {}; }

  var utils = {
    buffer: buffer,
    crypto: cryptoUtils,
    zlib: zlibUtils,
    httpFetch: lxFetch
  };

  var lx = {
    version: N.apiVersion(),
    env: N.env(),
    EVENT_NAMES: EVENT_NAMES,
    currentScriptInfo: scriptInfo,
    on: on,
    send: send,
    request: lxRequest,
    utils: utils,
    httpFetch: lxFetch
  };
  globalThis.lx = lx;

  // ---------------------------------------------------------------- 宿主调用入口
  globalThis.__lxInvoke = function (callId, payload) {
    var handler = handlers.request;
    if (!handler) {
      N.resolve(callId, false, '音源脚本未注册 request 事件');
      return;
    }
    try {
      Promise.resolve(handler(payload)).then(function (value) {
        var encoded;
        try {
          encoded = JSON.stringify(value === undefined ? null : value);
        } catch (e) {
          encoded = JSON.stringify(String(value));
        }
        N.resolve(callId, true, encoded || 'null');
      }, function (err) {
        N.resolve(callId, false, String(err && err.message ? err.message : err));
      });
    } catch (e) {
      N.resolve(callId, false, String(e && e.message ? e.message : e));
    }
  };
})();
