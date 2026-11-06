// Charts and the scripted hero. Every number here is made up: they are MRRadar's demo apps.
(function () {
  'use strict';
  var PH = window.PH;
  var calm = PH.calm;
  var SVG_DEFS = '<defs><linearGradient id="area-fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="var(--a)" stop-opacity=".35"/><stop offset="1" stop-color="var(--a)" stop-opacity="0"/></linearGradient></defs>';

  PH.addEn({
    'mock.alertText': 'MRR passed {v}.',
    'mock.i1': 'At this pace the month ends at {v}.',
    'mock.i2': 'Running trials should add about {v} of MRR.',
    'mock.i3': 'Friday is your best day, {v} against an average day.',
    'total.mrr': 'MRR',
    'total.arr': 'ARR',
    'total.subs': 'Subscribers',
    'total.trials': 'Active trials',
    'fc.now': 'Today {v}',
    'fc.then': 'In 90 days, about {v}',
    'pace.sofar': 'So far',
    'pace.pace': 'At this pace',
    'pace.last': 'Last month',
    'pace.day': 'Day {d} of {n}',
    'quick.won': 'Won',
    'quick.lost': 'Lost',
    'ltv.each': 'each',
    'ltv.months': '{v} months',
    'trial.trials': '{v} trials',
    'trial.convert': '{v} convert',
    'trial.each': '{v} each',
    'trial.result': 'should add about {v} of MRR',
    'unusual.note': '1 day marked in the last 28',
    'week.best': 'Friday is your best day, {v} against an average day.',
    'heat.size': '{v} new',
    'n.subs.t': 'New subscribers · Mint Budget',
    'n.subs.d': '4 new subscribers today.',
    'n.mile.t': 'MRR milestone · Lumen Notes',
    'n.mile.d': 'MRR passed {v}.',
    'n.churn.t': 'Churn is up · Orbit Weather',
    'n.churn.d': 'Monthly churn is {a}, up from {b}.',
    'n.refund.t': 'Refunds are high · Orbit Weather',
    'n.refund.d': '{v} of last month\'s transactions were refunded.'
  });

  // ---- The demo apps, the same ones as in the screenshots ------------------
  var apps = [
    { name: 'Pulse Habit', mrr: 4820, change: 4.8, quick: 1.3, churn: 5.6, ltv: 139.78, pace: 5378, seed: 3, slope: 1 },
    { name: 'Lumen Notes', mrr: 2150, change: 2.9, quick: 1.4, churn: 5.9, ltv: 120.41, pace: 2475, seed: 11, slope: .8 },
    { name: 'Orbit Weather', mrr: 860, change: -3.9, quick: 1.1, churn: 5.1, ltv: 114.37, pace: 963, seed: 23, slope: -1 },
    { name: 'Mint Budget', mrr: 390, change: 9.9, quick: 1.9, churn: 6.6, ltv: 83.33, pace: 438, seed: 41, slope: 1 }
  ];
  var TOTAL = 8220, SUBS = 1132, TRIALS = 93, DAYS28 = 8878;

  // Small repeatable noise, so the charts look the same on every visit.
  function noise(seed) {
    var s = seed * 9301 + 49297;
    return function () { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  }

  function sparkPath(app, w, h) {
    var r = noise(app.seed), pts = [], n = 24, y = 0, ys = [];
    for (var i = 0; i < n; i++) { y += app.slope * .5 + (r() - .5) * 1.05; ys.push(y); }
    var min = Math.min.apply(null, ys), max = Math.max.apply(null, ys);
    ys.forEach(function (v, k) {
      pts.push((k / (n - 1) * w).toFixed(1) + ' ' + (h - 2 - (v - min) / (max - min) * (h - 4)).toFixed(1));
    });
    return 'M' + pts.join('L');
  }

  function renderRows(id) {
    document.getElementById(id).innerHTML = apps.map(function (a, i) {
      return '<div class="row"><span class="row-icon">' + a.name[0] + '</span>' +
        '<div class="row-name"><b>' + a.name + '</b></div>' +
        '<svg class="spark' + (a.slope < 0 ? ' fall' : '') + '" viewBox="0 0 62 22" preserveAspectRatio="none" style="--n:' + i + '"><path pathLength="1" d="' + sparkPath(a, 62, 22) + '" style="--n:' + i + '"/></svg>' +
        '<div class="row-val"><span class="row-mrr" style="font-size:12.5px">' + PH.money(a.mrr) + '</span></div></div>';
    }).join('');
  }

  // ---- Least squares, as in the app: a straight line through 60 days -------
  var history = (function () {
    var r = noise(7), out = [];
    for (var i = 0; i < 90; i++) out.push(4235 + i * 6.5 + Math.sin(i / 4) * 12 + (r() - .5) * 16);
    // End on the demo app's MRR.
    var diff = 4820 - out[89];
    return out.map(function (v, i) { return Math.round(v + diff * i / 89); });
  })();

  function leastSquares(values) {
    var n = values.length, sx = 0, sy = 0, sxy = 0, sxx = 0;
    values.forEach(function (y, x) { sx += x; sy += y; sxy += x * y; sxx += x * x; });
    var b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
    return { a: (sy - b * sx) / n, b: b, n: n };
  }

  function forecastSvg(W, H, labels) {
    var fit = leastSquares(history.slice(-60));
    var ahead = 90, total = history.length + ahead;
    var end = fit.a + fit.b * (fit.n - 1 + ahead);
    var lo = 3900, hi = Math.max(end, 5000) + 60;
    var pad = labels ? 26 : 8;
    function x(i) { return i / (total - 1) * W; }
    function y(v) { return pad / 2 + (hi - v) / (hi - lo) * (H - pad - 4); }
    var line = history.map(function (v, i) { return x(i).toFixed(1) + ' ' + y(v).toFixed(1); }).join('L');
    var lastX = x(history.length - 1), lastY = y(history[history.length - 1]);
    var startY = y(fit.a + fit.b * (fit.n - 1));
    var grid = [4000, 4500, 5000].map(function (v) {
      return '<line class="chart-grid" x1="0" x2="' + W + '" y1="' + y(v).toFixed(1) + '" y2="' + y(v).toFixed(1) + '"/>' +
        (labels ? '<text class="chart-text" x="' + W + '" y="' + (y(v) - 5).toFixed(1) + '" text-anchor="end">' + PH.num(v) + '</text>' : '');
    }).join('');
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img">' + SVG_DEFS + grid +
      '<path class="chart-area fade-late" d="M' + line + 'L' + lastX.toFixed(1) + ' ' + H + 'L0 ' + H + 'Z"/>' +
      '<path class="chart-line line-draw" pathLength="1" d="M' + line + '"/>' +
      '<line class="fade-late" stroke="var(--d)" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="5 5" x1="' + lastX.toFixed(1) + '" y1="' + startY.toFixed(1) + '" x2="' + x(total - 1).toFixed(1) + '" y2="' + y(end).toFixed(1) + '"/>' +
      '<circle class="chart-dot fade-late" cx="' + x(total - 1).toFixed(1) + '" cy="' + y(end).toFixed(1) + '" r="4"/>' +
      '</svg>';
    return { svg: svg, end: end, now: lastY };
  }


  // ---- Everything that holds text, drawn again when the language changes ---
  function render() {
    var t = PH.t, money = PH.money;

    // Hero
    renderRows('hero-rows');
    renderRows('phone-rows');
    document.getElementById('hero-mrr').textContent = money(TOTAL);
    document.getElementById('phone-mrr').textContent = money(TOTAL);
    ['hero-change', 'phone-change'].forEach(function (id) { document.getElementById(id).textContent = PH.pct(3.5, true); });
    ['hero-subs', 'phone-subs'].forEach(function (id) { document.getElementById(id).textContent = PH.num(SUBS); });
    ['hero-28', 'phone-28'].forEach(function (id) { document.getElementById(id).textContent = money(DAYS28); });
    var milestone = t('mock.alertText').replace('{v}', money(2000));
    document.getElementById('hero-alert-text').textContent = milestone;
    document.getElementById('phone-alert-text').textContent = milestone;
    document.getElementById('hero-chart').innerHTML = forecastSvg(240, 90, false).svg;
    document.getElementById('phone-chart').innerHTML = forecastSvg(240, 80, false).svg;
    document.getElementById('hero-insights').innerHTML = [
      t('mock.i1').replace('{v}', money(5378)),
      t('mock.i2').replace('{v}', money(137)),
      t('mock.i3').replace('{v}', PH.pct(40.7, true))
    ].map(function (s, i) { return '<li style="--n:' + i + '">' + s + '</li>'; }).join('');

    // Totals and table
    document.getElementById('totals').innerHTML = [
      [t('total.mrr'), money(TOTAL)], [t('total.arr'), money(TOTAL * 12)],
      [t('total.subs'), PH.num(SUBS)], [t('total.trials'), PH.num(TRIALS)]
    ].map(function (c) { return '<div><span>' + c[0] + '</span><b>' + c[1] + '</b></div>'; }).join('');
    document.getElementById('ptable').innerHTML = apps.map(function (a, i) {
      return '<tr style="--n:' + i + '"><td><div class="app-cell"><i>' + a.name[0] + '</i>' + a.name + '</div></td>' +
        '<td>' + money(a.mrr) + '</td>' +
        '<td class="' + (a.change < 0 ? 'down' : 'up') + '">' + PH.pct(a.change, true) + '</td>' +
        '<td class="col-m">' + PH.num(a.quick, 1) + '×</td>' +
        '<td class="col-m">' + PH.pct(a.churn) + '</td>' +
        '<td class="col-m">' + money(a.ltv, 2) + '</td>' +
        '<td class="col-s">' + money(a.pace) + '</td></tr>';
    }).join('');

    // Forecast
    var fc = forecastSvg(640, 220, true);
    document.getElementById('viz-forecast').innerHTML = fc.svg +
      '<div class="viz-note"><span>' + t('fc.now').replace('{v}', '<b>' + money(4820) + '</b>') + '</span><span>' +
      t('fc.then').replace('{v}', '<b>' + money(Math.round(fc.end / 10) * 10) + '</b>') + '</span></div>';

    // Month-end pace: 20 days in, $3,585 so far, so $5,378 at this pace.
    document.getElementById('viz-pace').innerHTML =
      '<p class="big-num">' + money(5378) + '</p>' +
      '<p class="small muted" style="margin:2px 0 14px">' + t('pace.day').replace('{d}', PH.num(20)).replace('{n}', PH.num(30)) + '</p>' +
      '<div class="meter">' +
      meter(t('pace.sofar'), 65, money(3585)) +
      meter(t('pace.pace'), 97, money(5378), 'gold') +
      meter(t('pace.last'), 100, money(5527)) + '</div>';

    // Quick ratio
    document.getElementById('viz-quick').innerHTML =
      '<p class="big-num">' + PH.num(1.3, 1) + '×</p>' +
      '<div class="meter" style="margin-top:12px">' +
      meter(t('quick.won'), 100, money(1040)) + meter(t('quick.lost'), 77, money(800), 'bad') + '</div>';

    // Implied LTV
    document.getElementById('viz-ltv').innerHTML =
      '<p class="big-num">' + money(140) + '</p>' +
      '<p class="calc" style="margin-top:12px"><b>' + money(7.88, 2) + '</b> ' + t('ltv.each') + ' <i>×</i> <b>' + t('ltv.months').replace('{v}', PH.num(17.7, 1)) + '</b></p>';

    // Trials
    document.getElementById('viz-trial').innerHTML =
      '<p class="big-num">' + money(137) + '</p>' +
      '<p class="small muted" style="margin-top:2px">' + t('trial.result').replace('{v}', money(137)) + '</p>' +
      '<p class="calc" style="margin-top:12px"><b>' + t('trial.trials').replace('{v}', PH.num(48)) + '</b> <i>×</i> <b>' + t('trial.convert').replace('{v}', PH.pct(36.3)) + '</b> <i>×</i> <b>' + t('trial.each').replace('{v}', money(7.88, 2)) + '</b></p>';

    // Unusual days: the last 28 bars, each judged against the 28 before it.
    var r = noise(19), days = [];
    for (var d = 0; d < 56; d++) {
      var weekday = d % 7;
      days.push(150 + (weekday === 4 || weekday === 5 ? 90 : 0) + (r() - .5) * 46);
    }
    days[47] = 468;
    var W = 640, H = 170, shown = days.slice(28), max = Math.max.apply(null, shown) * 1.05, bw = W / 28;
    var bars = shown.map(function (v, i) {
      var before = days.slice(i, i + 28);
      var mean = before.reduce(function (a, b) { return a + b; }, 0) / 28;
      var sd = Math.sqrt(before.reduce(function (a, b) { return a + (b - mean) * (b - mean); }, 0) / 28);
      var odd = Math.abs(v - mean) > 3 * sd;
      var h = v / max * (H - 8);
      return '<rect class="bar-v ' + (odd ? 'bar-mark' : 'bar-b') + '" style="--n:' + i + '" x="' + (i * bw + 2).toFixed(1) + '" width="' + (bw - 4).toFixed(1) + '" y="' + (H - h).toFixed(1) + '" height="' + h.toFixed(1) + '" rx="3"/>' +
        (odd ? '<circle class="chart-dot fade-late" cx="' + (i * bw + bw / 2).toFixed(1) + '" cy="' + (H - h - 8).toFixed(1) + '" r="4"/>' : '');
    }).join('');
    document.getElementById('viz-unusual').innerHTML = '<svg viewBox="0 -14 ' + W + ' ' + (H + 14) + '" role="img">' + bars + '</svg>' +
      '<div class="viz-note"><span>' + t('unusual.note') + '</span></div>';

    // Weekdays: names from the browser, in the page's language.
    var wf = new Intl.DateTimeFormat(PH.lang(), { weekday: 'short' });
    var week = [.93, .85, .87, .82, 1.41, 1.24, .88];
    var names = week.map(function (_, i) { return wf.format(new Date(2026, 10, 2 + i)); });
    var wW = 300, wH = 150, step = wW / 7;
    document.getElementById('viz-week').innerHTML = '<svg viewBox="0 0 ' + wW + ' ' + (wH + 18) + '" role="img">' + week.map(function (v, i) {
      var h = v / 1.5 * wH;
      return '<rect class="bar-v ' + (v > 1 ? 'bar-a' : 'bar-b') + '" style="--n:' + i * 4 + '" x="' + (i * step + 4).toFixed(1) + '" width="' + (step - 8).toFixed(1) + '" y="' + (wH - h).toFixed(1) + '" height="' + h.toFixed(1) + '" rx="4"/>' +
        '<text class="chart-text" text-anchor="middle" x="' + (i * step + step / 2).toFixed(1) + '" y="' + (wH + 15) + '">' + names[i].replace(/\.$/, '').slice(0, 3) + '</text>';
    }).join('') + '<line class="chart-grid" x1="0" x2="' + wW + '" y1="' + (wH - 1 / 1.5 * wH).toFixed(1) + '" y2="' + (wH - 1 / 1.5 * wH).toFixed(1) + '"/></svg>' +
      '<div class="viz-note"><span>' + t('week.best').replace('{v}', '<b>' + PH.pct(40.7, true) + '</b>') + '</span></div>';

    // Retention heatmap
    var cohorts = [
      [4, [77, 60, 46, 35, 27, 21]], [5, [73, 54, 39, 29, 21]], [6, [73, 53, 38, 28]],
      [7, [75, 56, 42]], [8, [75, 56]], [9, [78]]
    ];
    var mf = new Intl.DateTimeFormat(PH.lang(), { month: 'short' });
    var n = 0;
    document.getElementById('viz-heat').innerHTML = cohorts.map(function (c) {
      var cells = '';
      for (var i = 0; i < 6; i++) {
        var v = c[1][i];
        cells += v == null ? '<i></i>' : '<i class="heat-cell" style="--o:' + (.2 + v / 100).toFixed(2) + ';--n:' + (n++) + '">' + PH.pct(v) + '</i>';
      }
      return '<div class="heat-row" style="--cols:6"><span>' + mf.format(new Date(2026, c[0], 1)) + '</span>' + cells + '</div>';
    }).join('');

    renderNotifs();
  }

  function meter(label, w, value, kind) {
    return '<div class="meter-row"><span>' + label + '</span><i class="meter-track"><u class="' + (kind || '') + '" style="--w:' + w + '%"></u></i><b>' + value + '</b></div>';
  }

  // ---- Notifications in the alerts section ---------------------------------
  var notifIndex = 0;
  function notifList() {
    var t = PH.t;
    return [
      [t('n.subs.t'), t('n.subs.d')],
      [t('n.mile.t'), t('n.mile.d').replace('{v}', PH.money(2000))],
      [t('n.churn.t'), t('n.churn.d').replace('{a}', PH.pct(7.4)).replace('{b}', PH.pct(5.1))],
      [t('n.refund.t'), t('n.refund.d').replace('{v}', PH.pct(6.2))]
    ];
  }
  var stage = document.getElementById('notifs');
  function notifHtml(n, pos, enter) {
    return '<div class="notif' + (enter ? ' enter' : '') + '" style="--pos:' + pos + '"><img src="assets/favicon.png" width="38" height="38" alt=""><div><b>' + n[0] + '</b><span>' + n[1] + '</span></div></div>';
  }
  function renderNotifs() {
    var list = notifList();
    stage.innerHTML = [0, 1, 2].map(function (i) { return notifHtml(list[(notifIndex - i + list.length * 4) % list.length], i); }).join('');
  }

  function pushNotif() {
    var list = notifList();
    notifIndex++;
    var cards = stage.querySelectorAll('.notif');
    cards.forEach(function (c) { c.style.setProperty('--pos', Number(c.style.getPropertyValue('--pos')) + 1); });
    stage.insertAdjacentHTML('afterbegin', notifHtml(list[notifIndex % list.length], 0, true));
    var fresh = stage.firstChild;
    fresh.getBoundingClientRect();
    fresh.classList.remove('enter');
    setTimeout(function () { var old = stage.querySelectorAll('.notif'); if (old.length > 3) old[old.length - 1].remove(); }, 650);
  }

  PH.onLang(render);

  // How far the tall screenshot pans, measured so it stops at its last row.
  var pan = document.getElementById('pan');
  function measurePan() { pan.style.setProperty('--pan-h', pan.clientHeight + 'px'); }
  window.addEventListener('resize', measurePan);
  measurePan();

  // ---- Scripted hero -------------------------------------------------------
  var desk = document.getElementById('desk');
  var panel = document.getElementById('panel');
  var banner = document.getElementById('phone-banner');
  var mrr = document.getElementById('hero-mrr');

  if (calm) {
    desk.classList.add('play');
    panel.classList.add('alerting');
    banner.classList.add('on');
    return;
  }

  function countUp() {
    var start = performance.now();
    (function frame(now) {
      var p = Math.min(1, (now - start) / 1200);
      var eased = 1 - Math.pow(1 - p, 3);
      mrr.textContent = PH.money(Math.round(TOTAL * .86 + TOTAL * .14 * eased));
      if (p < 1) requestAnimationFrame(frame);
    })(start);
  }

  function play() {
    if (!PH.inView(desk)) { setTimeout(play, 700); return; }
    desk.classList.remove('play');
    panel.classList.remove('alerting');
    desk.getBoundingClientRect();
    desk.classList.add('play');
    countUp();
    setTimeout(function () { panel.classList.add('alerting'); }, 3400);
    setTimeout(function () { panel.classList.remove('alerting'); }, 9000);
    setTimeout(play, 10400);
  }
  play();

  // The alerts section and the phone keep moving only while someone can see them.
  setInterval(function () { if (PH.inView(stage)) pushNotif(); }, 3200);
  setInterval(function () {
    if (!PH.inView(banner)) return;
    banner.classList.add('on');
    setTimeout(function () { banner.classList.remove('on'); }, 3400);
  }, 6000);
})();
