/* =========================================================================
 * Brightness_Enhance_PLK110 —— WebUI 前端
 * 首页：实时显示环境光传感器值、屏幕亮度，并把当前工作点画在自动亮度曲线上。
 * 数据全部来自模块内 bin/status.sh（只读）。
 * ========================================================================= */

'use strict';

var MODID = 'Brightness_Enhance_PLK110';
var STATUS = '/data/adb/modules/' + MODID + '/bin/status.sh';
var POLL_MS = 2000;

/* ---------- 执行 shell：兼容 KernelSU 注入的 ksu.exec 各种形态 ---------- */
function sh(cmd) {
  return new Promise(function (resolve) {
    var k = window.ksu || (window.$ksu || null);
    if (!k || typeof k.exec !== 'function') {
      resolve({ errno: -1, stdout: '', stderr: 'no-ksu' });
      return;
    }
    // 形态 1：直接返回 Promise
    try {
      var r = k.exec(cmd, JSON.stringify({}));
      if (r && typeof r.then === 'function') {
        r.then(function (x) { resolve(x || {}); }, function () { resolve({ errno: -1, stdout: '' }); });
        return;
      }
    } catch (e) { /* 继续尝试回调形态 */ }
    // 形态 2：ksu.exec(cmd, opts, callbackName)
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

var $ = function (id) { return document.getElementById(id); };
function setText(id, v) { var e = $(id); if (e) e.textContent = (v === undefined || v === null || v === '') ? '--' : v; }

/* ---------- 状态 ---------- */
var curve = [];        // [{lux, nit}]
var last = null;       // 最近一次读数

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
        if (!isNaN(x) && !isNaN(y)) c.push({ lux: x, nit: y });
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

/* ---------- 刷新 ---------- */
function render(s) {
  var kv = s.kv;
  if (s.curve && s.curve.length) curve = s.curve;

  last = {
    lux: parseFloat(kv.lux || 0),
    nit: parseFloat(kv.nit || 0),
    raw: parseFloat(kv.raw || 0),
    goal: curveNitAt(parseFloat(kv.lux || 0), curve)
  };

  setText('modver', kv.modver);
  setText('panel', kv.panel);
  setText('update', kv.update);
  setText('appver', kv.appver);
  setText('lux', isFinite(last.lux) ? last.lux.toFixed(1) : '--');
  setText('nit', isFinite(last.nit) ? last.nit.toFixed(0) : '--');
  setText('raw', kv.raw);
  setText('bmax', kv.bmax);
  setText('pct', kv.percent);
  setText('hbm', kv.hbm === 'off' ? '未激发' : (kv.hbm || '--'));
  setText('screen', kv.screen);
  setText('mode', kv.mode === '0' ? '手动' : (kv.mode === '1' ? '自动' : kv.mode));
  setText('pmaxnit', kv.pmax_nit);

  // 环境光条：以 log 刻度映射到 0-100%（1 ~ 100000 lux）
  var lb = $('luxBar');
  if (lb) {
    var v = Math.max(1, Math.min(100000, last.lux || 1));
    var p = (Math.log10(v) / 5) * 100;
    lb.style.width = Math.max(2, Math.min(100, p)) + '%';
  }

  var b = $('badge');
  if (b) {
    var ok = kv.effective === '1';
    b.className = 'badge ' + (ok ? 'ok' : 'bad');
    b.textContent = ok ? '配置已生效' : '配置未生效';
  }

  setText('wp',
    '环境光 ' + (isFinite(last.lux) ? last.lux.toFixed(1) : '--') + ' lux → 曲线目标 '
    + last.goal.toFixed(0) + ' nit，实际 ' + last.nit.toFixed(0) + ' nit'
    + '（差 ' + (last.nit - last.goal >= 0 ? '+' : '') + (last.nit - last.goal).toFixed(0) + '）');

  setText('tick', new Date().toLocaleTimeString());
  draw();
}

/* ---------- 画图 ---------- */
var PAD = { l: 62, r: 18, t: 20, b: 38 };

function niceMax(v, step) { return Math.ceil(v / step) * step; }

function draw() {
  var cv = $('chart'); if (!cv || !cv.getContext) return;
  var ctx = cv.getContext('2d');
  var W = cv.width, H = cv.height;
  var css = getComputedStyle(document.body);
  var C = {
    line: css.getPropertyValue('--line').trim() || '#2a2f3a',
    fg2: css.getPropertyValue('--fg2').trim() || '#9aa4b2',
    acc: css.getPropertyValue('--acc').trim() || '#4c8dff',
    warn: css.getPropertyValue('--warn').trim() || '#ffb020',
    bad: css.getPropertyValue('--bad').trim() || '#ff5c5c',
    ok: css.getPropertyValue('--ok').trim() || '#32d74b'
  };
  ctx.clearRect(0, 0, W, H);

  if (!curve.length) {
    ctx.fillStyle = C.fg2; ctx.font = '20px sans-serif';
    ctx.fillText('暂无曲线数据', PAD.l, H / 2);
    return;
  }

  // 坐标范围
  var MINLUX = 1, MAXLUX = Math.max(100000, curve[curve.length - 1].lux);
  var ymax = niceMax(Math.max(2200, curve[curve.length - 1].nit), 500);
  var x0 = PAD.l, x1 = W - PAD.r, y0 = H - PAD.b, y1 = PAD.t;
  var X = function (lux) {
    var v = Math.max(MINLUX, Math.min(MAXLUX, lux));
    return x0 + (Math.log10(v) - Math.log10(MINLUX)) /
           (Math.log10(MAXLUX) - Math.log10(MINLUX)) * (x1 - x0);
  };
  var Y = function (nit) { return y0 - (Math.max(0, Math.min(ymax, nit)) / ymax) * (y0 - y1); };

  // 网格 + 轴
  ctx.strokeStyle = C.line; ctx.lineWidth = 1; ctx.font = '16px sans-serif';
  ctx.fillStyle = C.fg2;
  var luxTicks = [1, 10, 100, 1000, 10000, 100000];
  luxTicks.forEach(function (L) {
    var x = X(L);
    ctx.beginPath(); ctx.moveTo(x, y0); ctx.lineTo(x, y1); ctx.stroke();
    var s = L >= 1000 ? (L / 1000) + 'k' : String(L);
    ctx.textAlign = 'center'; ctx.fillText(s, x, H - 14);
  });
  ctx.textAlign = 'right';
  for (var n = 0; n <= ymax; n += 500) {
    var y = Y(n);
    ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke();
    ctx.fillText(String(n), x0 - 8, y + 5);
  }
  ctx.textAlign = 'left';
  ctx.save(); ctx.translate(16, (y0 + y1) / 2); ctx.rotate(-Math.PI / 2);
  ctx.textAlign = 'center'; ctx.fillText('nit', 0, 0); ctx.restore();

  // 800nit 激发门槛
  if (ymax >= 800) {
    ctx.setLineDash([6, 6]); ctx.strokeStyle = C.warn; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x0, Y(800)); ctx.lineTo(x1, Y(800)); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = C.warn; ctx.textAlign = 'left';
    ctx.fillText('800nit 激发门槛', x0 + 6, Y(800) - 6);
  }

  // 曲线
  ctx.strokeStyle = C.acc; ctx.lineWidth = 3; ctx.beginPath();
  curve.forEach(function (p, i) {
    var x = X(p.lux), y = Y(p.nit);
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.stroke();

  // 当前工作点
  if (last && isFinite(last.lux)) {
    var xc = X(last.lux);
    ctx.setLineDash([4, 5]); ctx.strokeStyle = C.line; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(xc, y0); ctx.lineTo(xc, y1); ctx.stroke();
    ctx.setLineDash([]);

    // 曲线目标
    var yg = Y(last.goal);
    ctx.fillStyle = C.ok;
    ctx.beginPath(); ctx.arc(xc, yg, 7, 0, Math.PI * 2); ctx.fill();

    // 实际亮度
    var ya = Y(last.nit);
    ctx.fillStyle = C.bad;
    ctx.beginPath(); ctx.arc(xc, ya, 9, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = C.fg2; ctx.font = '16px sans-serif';
  }
  ctx.restore && ctx.restore();
}

/* ---------- 主循环 ---------- */
function refresh() {
  return sh('sh ' + STATUS).then(function (r) {
    if (r.errno === -1 && r.stderr === 'no-ksu') {
      setText('msg', '未检测到 KernelSU 环境（请在 KernelSU 管理器里打开本页）');
      return;
    }
    if (!r.stdout) { setText('msg', '读取失败：' + (r.stderr || '')); return; }
    setText('msg', '');
    render(parse(r.stdout));
  });
}

function boot() {
  var b = $('btn');
  if (b) b.addEventListener('click', refresh);
  refresh();
  setInterval(refresh, POLL_MS);
  window.addEventListener('resize', draw);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else { boot(); }
