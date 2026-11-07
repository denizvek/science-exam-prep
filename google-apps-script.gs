/**
 * Results sheet for the science exam-prep app.
 * Each child's device sends its progress here (doPost); the app reads the table back (doGet).
 */
const SHEET = 'results';
const HEAD = ['id', 'name', 'cls', 'av', 'meter', 'lessons', 'best', 'attempts', 'updated'];

function sheet_() {
  const ss = SpreadsheetApp.getActive();
  let s = ss.getSheetByName(SHEET);
  if (!s) { s = ss.insertSheet(SHEET); s.appendRow(HEAD); s.setFrozenRows(1); }
  return s;
}
// text that starts like a formula is stored as plain text
const txt_ = (v, n) => { const t = String(v == null ? '' : v).slice(0, n); return /^[=+\-@]/.test(t) ? "'" + t : t; };
const num_ = (v, lo, hi) => { const x = Number(v); return isFinite(x) ? Math.max(lo, Math.min(hi, Math.round(x))) : lo; };
const out_ = o => ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);

function doPost(e) {
  let d;
  try { d = JSON.parse(e.postData.contents); } catch (err) { return out_({ ok: false }); }
  if (!d || !d.id || !d.name) return out_({ ok: false });
  const row = [
    txt_(d.id, 40), txt_(d.name, 40), txt_(d.cls, 10), txt_(d.av, 8),
    num_(d.meter, 0, 100), num_(d.lessons, 0, 50),
    d.best == null ? '' : num_(d.best, 0, 100), num_(d.attempts, 0, 999), new Date()
  ];
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const s = sheet_();
    const n = s.getLastRow() - 1;
    const ids = n > 0 ? s.getRange(2, 1, n, 1).getValues().map(r => String(r[0])) : [];
    const i = ids.indexOf(String(row[0]));
    if (i >= 0) s.getRange(i + 2, 1, 1, row.length).setValues([row]);
    else s.appendRow(row);
  } finally { lock.releaseLock(); }
  return out_({ ok: true });
}

function doGet() {
  const s = sheet_();
  const n = s.getLastRow() - 1;
  const v = n > 0 ? s.getRange(2, 1, n, HEAD.length).getValues() : [];
  const rows = v.map(r => ({ name: r[1], cls: r[2], av: r[3], meter: +r[4], best: r[6] === '' ? null : +r[6], attempts: +r[7], updated: new Date(r[8]).getTime() }));
  return out_({ ok: true, rows: rows });
}
