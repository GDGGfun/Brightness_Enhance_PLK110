/* =========================================================================
 * Brightness_Enhance_PLK110 —— WebUI 前端
 * 数据源：模块内 bin/status.sh（只读），2 秒轮询。
 * 页面：首页（实时读数 + 自动亮度曲线）/
 *       反馈（读取日志 / 提取配置文件 / 模块开关）/ 关于。
 * ========================================================================= */

'use strict';

var MODID = 'Brightness_Enhance_PLK110';
var MODDIR = '/data/adb/modules/' + MODID;
var STATUS = MODDIR + '/bin/status.sh';
var MODCTL = MODDIR + '/bin/modctl.sh';   // 模块开关：写/删 skip_mount，再重启
var POLL_MS = 2000;

var GH_URL = 'https://github.com/GDGGfun/Brightness_Enhance_PLK110';
var GH_PROXY = 'https://gh-proxy.org/' + GH_URL;
var QQ_GROUP = '695176727';
var QQ_URL = 'https://qm.qq.com/q/LtewtREg0i';

/* ---------- 执行 shell：兼容 KernelSU 注入的 ksu.exec 两种形态 ---------- */
function sh(cmd) {
  return new Promise(function (resolve) {
    var k = window.ksu || window.$ksu || null;
    if (!k || typeof k.exec !== 'function') {
      resolve({ errno: -1, stdout: '', stderr: 'no-ksu' });
      return;
    }
    try {
      var r = k.exec(cmd, JSON.stringify({}));
      if (r && typeof r.then === 'function') {
        r.then(function (x) { resolve(x || {}); },
               function () { resolve({ errno: -1, stdout: '' }); });
        return;
      }
    } catch (e) { /* 退回回调形态 */ }
    try {
      var cb = 'kcb_' + Date.now() + '_' + Math.floor(Math.random() * 1e6);
      window[cb] = function (errno, stdout, stderr) {
        try { delete window[cb]; } catch (e) {}
        resolve({ errno: errno, stdout: stdout || '', stderr: stderr || '' });
      };
      k.exec(cmd, JSON.stringify({}), cb);
    } catch (e) {
      resolve({ errno: -1, stdout: '', stderr: String(e) });
    }
  });
}

/* WebUI 是 WebView，a[target=_blank] 不会跳转 —— 用 am start 交给系统浏览器 */
function openUrl(url) {
  return sh('am start --user 0 -a android.intent.action.VIEW -d "' + url + '"')
    .then(function (r) {
      if (!r || r.errno !== 0) { try { window.open(url, '_blank'); } catch (e) {} }
    });
}

/* onclick 覆盖式绑定，避免每次轮询重复挂监听 */
function bindLink(id, url) {
  var a = $(id);
  if (!a) return;
  a.href = url;
  a.onclick = function (e) { e.preventDefault(); openUrl(url); return false; };
}

var $ = function (id) { return document.getElementById(id); };
function setText(id, v) {
  var e = $(id);
  if (e) e.textContent = (v === undefined || v === null || v === '') ? '--' : v;
}
/* 提示条：空串必须真的清空，否则 setText 会写成 '--'（看着像两条黄杠） */
function setMsg(t) {
  var e = $('msg');
  if (e) e.textContent = t || '';
}
function num(v, d) { var n = parseFloat(v); return isFinite(n) ? n : (d || 0); }

/* ---------- 状态 ---------- */
var curve = [];   // [{lux, nit}]
var cur = null;   // 最近一次读数
var lastKv = null; // 最近一次 status.sh 键值（确认文案要用机型适配字段）

/* ---------- 解析 status.sh 输出 ---------- */
function parse(out) {
  var kv = {}, c = [], inCurve = false;
  out.split('\n').forEach(function (line) {
    line = line.replace(/\r$/, '');
    if (line === 'curve_begin') { inCurve = true; return; }
    if (line === 'curve_end') { inCurve = false; return; }
    if (inCurve) {
      var p = line.split(',');
      if (p.length === 2) {
        var x = parseFloat(p[0]), y = parseFloat(p[1]);
        if (isFinite(x) && isFinite(y)) c.push({ lux: x, nit: y });
      }
      return;
    }
    var i = line.indexOf('=');
    if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1);
  });
  return { kv: kv, curve: c };
}

/* ---------- 曲线插值（与设备端同一套线性插值） ---------- */
function curveNitAt(lux, pts) {
  if (!pts || !pts.length) return 0;
  if (lux <= pts[0].lux) return pts[0].nit;
  var n = pts.length;
  if (lux >= pts[n - 1].lux) return pts[n - 1].nit;
  for (var i = 1; i < n; i++) {
    if (lux <= pts[i].lux) {
      var t = (lux - pts[i - 1].lux) / (pts[i].lux - pts[i - 1].lux);
      return pts[i - 1].nit + t * (pts[i].nit - pts[i - 1].nit);
    }
  }
  return pts[n - 1].nit;
}

/* ---------- 渲染 ---------- */
function render(s) {
  var kv = s.kv;
  lastKv = kv;
  if (s.curve && s.curve.length) curve = s.curve;

  var lux = num(kv.lux), nit = num(kv.nit);
  cur = {
    lux: lux,
    nit: nit,
    goal: curveNitAt(lux, curve),
    th: num(kv.hbm_threshold, 800),
    peak: num(kv.peak_nit, 0)
  };

  setText('sub', kv.modver + ' · ' + (kv.model || '--') + ' · ' + (kv.sysver || kv.update)
                 + ' · ' + (kv.panel_name || kv.panel || '--'));

  setText('lux', lux.toFixed(1));
  setText('nit', nit.toFixed(0));
  setText('pct', num(kv.percent).toFixed(1) + '%');
  setText('hbm', kv.hbm === 'on' ? '已激发' : (kv.hbm === 'off' ? '未激发' : kv.hbm));
  setText('mode', kv.mode === '0' ? '手动' : (kv.mode === '1' ? '自动' : kv.mode));

  // 手动亮度最大值 = 激发阈值（同一口径）；亮度上限取运行时生效值
  setText('manual', cur.th.toFixed(0));
  setText('limit', (num(kv.global_limit) || cur.peak).toFixed(0));
  setText('th', cur.th.toFixed(0));

  setText('thTxt', cur.th.toFixed(0) + ' nit');
  setText('peakTxt', cur.peak.toFixed(0) + ' nit');

  var ok = kv.effective === '1';
  var off = kv.skip_mount === '1';    // skip_mount 存在 = 模块已被开关禁用
  var dt = $('dot');
  if (dt) dt.className = 'dot ' + (ok ? 'ok' : 'bad');
  setText('eff', off ? '模块已禁用' : (ok ? '配置已生效' : '配置未生效'));

  syncSwitch(kv);
  fillAbout(kv);
  draw();
}

function fillAbout(kv) {
  setText('aName', kv.modname);
  setText('aVer', kv.modver);
  setText('aModel', kv.model);
  setText('aUpdate', kv.sysver || kv.update);
  setText('aPanel', (kv.panel_name || '--') + '（' + (kv.panel || '--') + '）');
  setText('aApp', kv.appver);

  bindLink('aGh', GH_URL);
  bindLink('aGhPx', GH_PROXY);

  var qq = $('aQq');
  if (qq) {
    if (QQ_URL) {
      bindLink('aQq', QQ_URL);
      qq.textContent = 'QQ 群 ' + QQ_GROUP;
      qq.classList.remove('off');
    } else {
      qq.removeAttribute('href');
      qq.onclick = null;
      qq.textContent = 'QQ 群（暂未设置）';
      qq.classList.add('off');
    }
  }
}

/* ---------- 画图 ---------- */
var PAD = { l: 64, r: 20, t: 24, b: 40 };
var MINLUX = 1;

function draw() {
  var cv = $('chart');
  if (!cv || !cv.getContext) return;
  var ctx = cv.getContext('2d');
  var W = cv.width, H = cv.height;
  var css = getComputedStyle(document.documentElement);
  var C = {
    line: css.getPropertyValue('--line').trim() || '#2a2f3a',
    fg2:  css.getPropertyValue('--fg2').trim()  || '#9aa4b2',
    acc:  css.getPropertyValue('--acc').trim()  || '#4c8dff',
    warn: css.getPropertyValue('--warn').trim() || '#ffb020',
    bad:  css.getPropertyValue('--bad').trim()  || '#ff5c5c',
    ok:   css.getPropertyValue('--ok').trim()   || '#32d74b'
  };
  ctx.clearRect(0, 0, W, H);
  ctx.font = '17px sans-serif';

  if (!curve.length) {
    ctx.fillStyle = C.fg2;
    ctx.textAlign = 'left';
    ctx.fillText('暂无曲线数据', PAD.l, H / 2);
    return;
  }

  var curveMax = curve[curve.length - 1].nit;
  var peak = cur ? cur.peak : 0;
  var th = cur ? cur.th : 800;
  var ymax = Math.ceil(Math.max(curveMax, peak, 2200) * 1.08 / 100) * 100;
  var MAXLUX = Math.max(100000, curve[curve.length - 1].lux);
  var x0 = PAD.l, x1 = W - PAD.r, y0 = H - PAD.b, y1 = PAD.t;

  var X = function (lux) {
    var v = Math.max(MINLUX, Math.min(MAXLUX, lux));
    return x0 + (Math.log10(v) / Math.log10(MAXLUX)) * (x1 - x0);
  };
  var Y = function (nit) { return y0 - (Math.max(0, Math.min(ymax, nit)) / ymax) * (y0 - y1); };

  // 网格与坐标轴
  ctx.strokeStyle = C.line; ctx.lineWidth = 1; ctx.fillStyle = C.fg2;
  [1, 10, 100, 1000, 10000, 100000].forEach(function (L) {
    var x = X(L);
    ctx.beginPath(); ctx.moveTo(x, y0); ctx.lineTo(x, y1); ctx.stroke();
    ctx.textAlign = 'center';
    ctx.fillText(L >= 1000 ? (L / 1000) + 'k' : String(L), x, H - 14);
  });
  var step = ymax > 2000 ? 500 : 200;
  ctx.textAlign = 'right';
  for (var n = 0; n <= ymax; n += step) {
    var y = Y(n);
    ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke();
    ctx.fillText(String(n), x0 - 8, y + 5);
  }
  ctx.textAlign = 'left';
  ctx.fillText('lux', x1 - 30, H - 14);
  ctx.save(); ctx.translate(18, (y0 + y1) / 2); ctx.rotate(-Math.PI / 2);
  ctx.textAlign = 'center'; ctx.fillText('nit', 0, 0); ctx.restore();

  // 激发亮度阈值线（手动最高亮度，默认 800nit）
  if (th > 0 && th < ymax) {
    ctx.setLineDash([7, 6]); ctx.strokeStyle = C.warn; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x0, Y(th)); ctx.lineTo(x1, Y(th)); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = C.warn; ctx.textAlign = 'left';
    ctx.fillText('激发阈值 ' + th.toFixed(0) + ' nit', x0 + 6, Y(th) - 7);
  }

  // 面板峰值线
  if (peak > 0 && peak < ymax) {
    ctx.setLineDash([3, 5]); ctx.strokeStyle = C.ok; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x0, Y(peak)); ctx.lineTo(x1, Y(peak)); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = C.ok; ctx.textAlign = 'right';
    ctx.fillText('面板峰值 ' + peak.toFixed(0) + ' nit', x1 - 6, Y(peak) - 7);
  }

  // 曲线
  ctx.strokeStyle = C.acc; ctx.lineWidth = 3; ctx.beginPath();
  curve.forEach(function (p, i) {
    var x = X(p.lux), y = Y(p.nit);
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.stroke();

  // 工作点
  if (cur && cur.lux > 0) {
    var xc = X(cur.lux);
    ctx.setLineDash([4, 5]); ctx.strokeStyle = C.line; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(xc, y1); ctx.lineTo(xc, y0); ctx.stroke();
    ctx.setLineDash([]);

    ctx.fillStyle = C.ok;
    ctx.beginPath(); ctx.arc(xc, Y(cur.goal), 7, 0, Math.PI * 2); ctx.fill();

    ctx.fillStyle = C.bad;
    ctx.beginPath(); ctx.arc(xc, Y(cur.nit), 9, 0, Math.PI * 2); ctx.fill();
  }
}

/* ---------- 分页 ---------- */
function switchPage(name) {
  var tabs = document.querySelectorAll('.tab');
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].classList.toggle('on', tabs[i].getAttribute('data-page') === name);
  }
  var pages = document.querySelectorAll('.page');
  for (var j = 0; j < pages.length; j++) {
    pages[j].classList.toggle('on', pages[j].id === 'page-' + name);
  }
  if (name === 'home') draw();
}

/* ---------- 反馈页：采集任务 ---------- */
var busy = false;

function emptyText(id) { var e = $(id); if (e) e.textContent = ''; }

/* 提示行：空串要清空（setText 会把空值写成 '--'） */
function setTip(id, t, bad) {
  var e = $(id);
  if (!e) return;
  e.textContent = t || '';
  e.className = 'tip' + (bad ? ' bad' : '');
}

/* 取脚本最后一行 RESULT=OK|…|… 并按 | 切开；没有则返回 null */
function lastResult(r) {
  var line = '';
  ((r && r.stdout) || '').split('\n').forEach(function (l) {
    l = l.replace(/\r$/, '').trim();
    if (l.indexOf('RESULT=') === 0) line = l;
  });
  return line ? line.slice(7).split('|') : null;
}

/* 采集脚本要跑数秒。先让浏览器把遮罩画出来再调用 ksu.exec，
   否则阻塞式调用会把渲染一起卡住，用户看到的就是「点了没反应」。 */
function nextFrame(fn) {
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(function () { setTimeout(fn, 0); });
  } else {
    setTimeout(fn, 30);
  }
}

function showLoading(title, sub) {
  setText('loadTxt', title);
  setText('loadSub', sub);
  var el = $('loading');
  if (el) el.hidden = false;
}

function hideLoading() { var el = $('loading'); if (el) el.hidden = true; }

/* 结果弹窗：显示文件路径 + 「复制路径」+「完成」。
   不做系统分享 —— Android 不允许 root/shell 身份把公共目录里的非媒体文件授权给
   微信 / QQ（真机实测接收方 open failed: EACCES），自建 dex 借 documentsui 身份的路子
   在设备上也走不通（app_process 在受限 domain 下静默 abort）。详见
   .开发/skills/反馈页采集功能.md §4。 */
function showModal(title, path, note) {
  setText('mTitle', title);
  setText('mPath', path || '--');
  setText('mNote', note || '');
  var m = $('modal');
  if (m) m.hidden = false;
  var cb = $('mCopy');
  if (cb) {
    cb.disabled = !path;
    cb.onclick = path ? function () {
      copyText(path).then(function () {
        cb.textContent = '已复制';
        setTimeout(function () { cb.textContent = '复制路径'; }, 1600);
      }, function () {
        cb.textContent = '请长按路径复制';
      });
    } : null;
  }
}

function hideModal() { var m = $('modal'); if (m) m.hidden = true; }

/* 下载目录里的文件必须转成 content:// 才能分享：
   Android 7 起接收方读不到 file://（scoped storage），会直接提示「文件不存在」。
   借系统自带的 externalstorage DocumentsProvider 构造 content URI，无需 FileProvider。 */
/* 复制文本到剪贴板。
   真机没有 `cmd clipboard`（实测 "No shell command implementation."），所以只能走前端：
   优先 Clipboard API（需要安全上下文），失败退回 execCommand —— WebView 里一般都可用。 */
function copyText(text) {
  if (!text) return Promise.reject(new Error('empty'));
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text);
  }
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.top = '-1000px';
  ta.setAttribute('readonly', '');
  document.body.appendChild(ta);
  ta.select();
  ta.setSelectionRange(0, text.length);
  var ok = false;
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  document.body.removeChild(ta);
  return ok ? Promise.resolve() : Promise.reject(new Error('execCommand failed'));
}

/* 采集脚本约定最后一行输出：RESULT=OK|路径|字节|名称|文件数 */
var SCRIPT_TIP = {
  'log.sh': '正在收集日志并本地脱敏，请勿退出',
  'collect.sh': '正在提取系统显示配置，请勿退出'
};

function runTask(btnId, tipId, script, label) {
  if (busy) return;
  busy = true;
  var b = $(btnId);
  var settled = false;
  if (b) { b.disabled = true; b.textContent = label + '中…'; }
  emptyText(tipId);

  function fail(msg) {
    var e = $(tipId);
    if (e) e.textContent = '执行失败：' + msg;
  }

  function done(r) {
    if (settled) return;
    settled = true;
    busy = false;
    hideLoading();
    if (b) { b.disabled = false; b.textContent = label; }

    var p = lastResult(r);
    if (!p) {
      fail('脚本没有返回结果' + ((r && r.stderr) ? ('：' + r.stderr) : '') +
           '。若下载文件夹里已出现新压缩包，说明采集本身已成功，可直接取用。');
      return;
    }
    if (p[0] !== 'OK') { fail(p[1] || '未知错误'); return; }

    var path = p[1], size = parseInt(p[2] || '0', 10), name = p[3];
    var extra = p[4] ? ('，含 ' + p[4] + ' 个文件') : '';
    var t = $(tipId);
    if (t) t.textContent = '已完成：' + name;
    showModal('已完成', path,
      '大小 ' + (size / 1024).toFixed(1) + ' KB' + extra +
      '，已存入下载文件夹。发给微信 / QQ / TIM 请用它们的「+ → 文件」入口从下载目录选取' +
      '——这些应用没有「所有文件访问」权限，无法直接接收公共目录里的压缩包。');
  }

  showLoading(label + '中…', SCRIPT_TIP[script] || '请勿退出或重复点击');
  // 兜底：万一 exec 既不回调也不返回，遮罩也不能永久盖住界面
  var guard = setTimeout(function () { done({ stderr: '等待超时' }); }, 120000);
  nextFrame(function () {
    sh('sh ' + MODDIR + '/bin/' + script).then(function (r) { clearTimeout(guard); done(r); },
                                               function () { clearTimeout(guard); done({}); });
  });
}

/* ---------- 反馈页：模块开关 ----------
   开 = 启用（删除 skip_mount）／关 = 禁用（创建 skip_mount），两者都要重启才生效。
   开关状态来自 status.sh 的 skip_mount 字段，与轮询同一数据源，不额外起查状态的开销。 */
var modBusy = false;     // 设置/重启过程中不接受轮询覆盖开关外观
var modPending = false;  // 确认弹窗里待执行的目标状态

/* 机型未适配时只警告、不拦截 —— 这个开关本身就是给非适配机型用户自行测试用的 */
function notAdapted() { return !!(lastKv && lastKv.device_match === '0'); }

function syncSwitch(kv) {
  if (modBusy) return;
  var sw = $('swMod');
  if (!sw) return;
  var off = kv.skip_mount === '1';
  sw.checked = !off;
  sw.disabled = false;
  setTip('tipMod', off
    ? '已禁用：重启后不再挂载本模块的配置（本页仍可用）。打开开关并重启即可恢复。'
    : ('已启用：配置正常挂载。切换开关会重启设备。' +
       (notAdapted() ? ' 当前机型不在适配列表内，配置可能不生效。' : '')));
}

function askModToggle(target) {
  var sw = $('swMod');
  if (!sw || modBusy) return;
  modPending = target;
  sw.checked = !target;     // 先回到真实状态，确认后才真正改
  setText('cTitle', target ? '启用模块' : '禁用模块');
  var warn = notAdapted()
    ? '注意：当前机型不在适配列表（一加15）内，启用后配置可能不生效或显示异常，' +
      '可自行测试；有问题关掉此开关并重启即可恢复原机状态。'
    : '';
  setText('cNote', target
    ? ('将删除 skip_mount，随后重启生效（越狱/伪回锁设备走 KSU 软重启，保留 root）。' + warn)
    : ('将创建 skip_mount，随后重启生效：重启后本模块不再挂载任何配置，' +
       '亮度策略回到原机（本页仍可用）。需要恢复时再打开此开关并重启。'));
  var c = $('confirm');
  if (c) c.hidden = false;
}

function hideConfirm() { var c = $('confirm'); if (c) c.hidden = true; }

function doModToggle(target) {
  hideConfirm();
  if (modBusy) return;
  modBusy = true;
  var sw = $('swMod');
  if (sw) sw.disabled = true;
  setTip('tipMod', '');
  showLoading(target ? '正在启用…' : '正在禁用…', '正在写入模块开关');

  function restore(msg) {
    modBusy = false;
    if (sw) sw.disabled = false;
    hideLoading();
    setTip('tipMod', msg, true);
  }

  /* 无重启命令可执行时（如只提示、脚本报错）才解除等待 */
  nextFrame(function () {
    sh('sh ' + MODCTL + ' ' + (target ? 'on' : 'off')).then(function (r) {
      var p = lastResult(r);
      if (!p || p[0] !== 'OK') {
        restore('设置失败：' + ((p && p[1]) || (r && r.stderr) || '脚本没有返回结果') + '，可稍后重试。');
        return;
      }
      setText('loadTxt', '正在重启');
      setText('loadSub', '设备即将重启，请勿断电');
      // 设备重启会终止本次 WebView 会话，故不等待 reboot 分支的返回值
      sh('sh ' + MODCTL + ' reboot').then(function (r2) {
        var p2 = lastResult(r2);
        if (!p2) return;                       // 已进入重启流程，等页面销毁
        if (p2[0] === 'OK' && p2[1] === 'soft') {
          setText('loadSub', '软重启中（保留 root 与越狱状态），请勿断电');
          return;
        }
        if (p2[0] === 'PROMPT') {              // 判定不出重启方式：只提示，不执行
          restore('模块开关已写入。' + (p2[1] || '请手动重启手机') + '。重启后生效。');
          return;
        }
        if (p2[0] === 'ERR') {
          restore('模块开关已写入，但' + (p2[1] || '重启命令未生效') + '。');
        }
      });
      // 兜底：重启命令没生效时不能一直挡着界面
      setTimeout(function () {
        if (!modBusy) return;
        restore('模块开关已写入，但重启命令似乎未生效，请手动重启手机。');
      }, 45000);
    }, function () {
      restore('设置失败：执行环境异常，可稍后重试。');
    });
  });
}

/* ---------- 主循环 ---------- */
function refresh() {
  return sh('sh ' + STATUS).then(function (r) {
    if (r.errno === -1 && r.stderr === 'no-ksu') {
      setMsg('未检测到 KernelSU 环境，请在 KernelSU 管理器里打开本页');
      return;
    }
    if (!r.stdout) { setMsg('读取失败：' + (r.stderr || '无输出')); return; }
    setMsg('');
    render(parse(r.stdout));
  });
}

function boot() {
  var tabs = document.querySelectorAll('.tab');
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].addEventListener('click', function () {
      switchPage(this.getAttribute('data-page'));
    });
  }
  var bl = $('btnLog');
  if (bl) bl.onclick = function () { runTask('btnLog', 'tipLog', 'log.sh', '读取日志'); };
  var bc = $('btnCfg');
  if (bc) bc.onclick = function () { runTask('btnCfg', 'tipCfg', 'collect.sh', '提取配置文件'); };
  var md = $('mDone');
  if (md) md.onclick = hideModal;

  // 模块开关：勾选/取消都先弹确认，确认后才写 skip_mount + 重启
  var sw = $('swMod');
  if (sw) sw.onchange = function () { askModToggle(!!sw.checked); };
  var cno = $('cNo');
  if (cno) cno.onclick = hideConfirm;
  var cyes = $('cYes');
  if (cyes) cyes.onclick = function () { doModToggle(modPending); };

  refresh();
  setInterval(refresh, POLL_MS);
  window.addEventListener('resize', draw);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else { boot(); }
