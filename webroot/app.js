import { exec, toast } from 'kernelsu-alt';

const DIR = '/data/adb/ksu-toast';
const LOG = `${DIR}/daemon.log`;
const DENY = `${DIR}/deny.list`;
const CACHE = `${DIR}/allow.cache`;
const PIDF = `${DIR}/daemon.pid`;
const SOCK = `${DIR}/daemon.sock`;

function sh(cmd) {
    return exec(cmd).then(r => ({ out: (r.stdout || '').trim(), err: r.errno || 0 }))
        .catch(() => ({ out: '', err: -1 }));
}

// ── Page routing (bottom nav) ───────────────────────────
document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => {
        document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
        document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
        item.classList.add('active');
        const page = document.getElementById('page-' + item.dataset.page);
        if (page) page.classList.add('active');
        // Refresh on switch
        const p = item.dataset.page;
        if (p === 'dashboard') refreshDashboard();
        if (p === 'logs') refreshLogs();
        if (p === 'deny') { refreshDeny(); refreshCache(); }
    });
});

const $ = id => document.getElementById(id);

// ── Dashboard ────────────────────────────────────────────
async function refreshDashboard() {
    // daemon
    const pidR = await sh(`cat "${PIDF}" 2>/dev/null`);
    const pid = pidR.out;
    let running = false;
    if (pid) {
        const ck = await sh(`kill -0 ${pid} 2>/dev/null && echo 1 || echo 0`);
        running = ck.out === '1';
    }
    setStatus('daemon-status', running ? 'Running' : (pid ? 'Stale' : 'Stopped'), running);

    // socket
    const skR = await sh(`test -S "${SOCK}" && echo 1 || echo 0`);
    setStatus('socket-status', skR.out === '1' ? 'Ready' : 'Missing', skR.out === '1');

    // deny count
    const dR = await sh(`wc -l < "${DENY}" 2>/dev/null || echo 0`);
    $('deny-count').textContent = (parseInt(dR.out) || 0) + ' entries';

    // cache count
    const cR = await sh(`wc -l < "${CACHE}" 2>/dev/null || echo 0`);
    $('cache-count').textContent = (parseInt(cR.out) || 0) + ' entries';

    // timeout
    const tR = await sh('getprop ksu.toast.timeout 2>/dev/null || echo 10');
    $('timeout-value').textContent = (parseInt(tR.out) || 10) + 's';

    // apk
    const aR = await sh('pm path com.wildkernels.ksutoast 2>/dev/null || echo ""');
    setStatus('apk-status', aR.out ? 'Installed' : 'Missing', !!aR.out);

    // version
    const vR = await sh('grep "^version=" /data/adb/modules/ksu_toast/module.prop | cut -d= -f2');
    $('version').textContent = vR.out || '';
}

function setStatus(id, text, ok) {
    const el = $(id);
    el.textContent = text;
    el.className = 'card-value' + (ok !== undefined ? (ok ? ' status-ok' : ' status-err') : '');
}

$('refresh-dashboard').addEventListener('click', refreshDashboard);

// ── Logs ─────────────────────────────────────────────────
let autoTimer = null;

async function refreshLogs() {
    const eR = await sh(`test -f "${LOG}" && echo 1 || echo 0`);
    if (eR.out !== '1') { $('log-content').textContent = '(no log file)'; return; }
    const lR = await sh(`tail -100 "${LOG}" 2>/dev/null`);
    $('log-content').textContent = lR.out || '(empty)';
    $('log-content').scrollTop = $('log-content').scrollHeight;
}

$('refresh-logs').addEventListener('click', refreshLogs);
$('clear-logs').addEventListener('click', async () => {
    await sh(`: > "${LOG}" 2>/dev/null`);
    toast('Logs cleared');
    refreshLogs();
});
$('auto-refresh').addEventListener('change', e => {
    if (autoTimer) clearInterval(autoTimer);
    autoTimer = e.target.checked ? setInterval(refreshLogs, 5000) : null;
});

// ── Deny List ────────────────────────────────────────────
async function refreshDeny() {
    const r = await sh(`cat "${DENY}" 2>/dev/null`);
    const items = r.out ? r.out.split('\n').filter(l => l.trim()) : [];
    $('deny-content').innerHTML = items.length
        ? items.map(u => `<div class="list-item">UID: ${u}</div>`).join('')
        : '<div class="empty-msg">Deny list is empty</div>';
}

async function refreshCache() {
    const r = await sh(`cat "${CACHE}" 2>/dev/null`);
    const items = r.out ? r.out.split('\n').filter(l => l.trim()) : [];
    $('cache-content').innerHTML = items.length
        ? items.map(u => `<div class="list-item">UID: ${u}</div>`).join('')
        : '<div class="empty-msg">Allow cache is empty</div>';
}

$('refresh-deny').addEventListener('click', () => { refreshDeny(); refreshCache(); });
$('clear-deny').addEventListener('click', async () => {
    await sh(`: > "${DENY}" 2>/dev/null`);
    toast('Deny list cleared');
    refreshDeny();
    refreshDashboard();
});
$('clear-cache').addEventListener('click', async () => {
    await sh(`: > "${CACHE}" 2>/dev/null`);
    toast('Allow cache cleared');
    refreshCache();
    refreshDashboard();
});

// ── Config ───────────────────────────────────────────────
const timeoutSlider = $('timeout-slider');
timeoutSlider.addEventListener('input', () => {
    $('timeout-display').textContent = timeoutSlider.value + 's';
});
// Load saved timeout
async function loadTimeout() {
    // Try config file first, then setprop, default 10
    const fR = await sh(`cat "${DIR}/config/timeout" 2>/dev/null || getprop ksu.toast.timeout 2>/dev/null || echo 10`);
    const val = parseInt(fR.out) || 10;
    timeoutSlider.value = val;
    $('timeout-display').textContent = val + 's';
}
loadTimeout();

$('save-timeout').addEventListener('click', async () => {
    const val = parseInt(timeoutSlider.value);
    await sh(`setprop ksu.toast.timeout ${val}`);
    await sh(`mkdir -p "${DIR}/config" && echo ${val} > "${DIR}/config/timeout"`);
    toast('Timeout set to ' + val + 's');
});

$('restart-daemon').addEventListener('click', async () => {
    const pR = await sh(`cat "${PIDF}" 2>/dev/null`);
    if (pR.out) await sh(`kill -9 "${pR.out}" 2>/dev/null; sleep 1`);
    // Clean up stale socket and pid file before starting
    await sh(`rm -f "${SOCK}" "${PIDF}"`);
    await new Promise(r => setTimeout(r, 500));
    await sh(`/system/bin/ksu-toastd \\
        --socket "${SOCK}" --apk-socket "/data/adb/ksu-toast/apk.sock" \\
        --deny-list "${DENY}" --cache "${CACHE}" \\
        --config "${DIR}/config" > "${LOG}" 2>&1 &
    `);
    // Give daemon time to start and write PID
    await new Promise(r => setTimeout(r, 2000));
    const pidR2 = await sh(`cat "${PIDF}" 2>/dev/null`);
    if (pidR2.out) {
        toast('Daemon restarted (pid ' + pidR2.out + ')');
    } else {
        toast('Daemon failed to start');
    }
    refreshDashboard();
});

// ── Init ─────────────────────────────────────────────────
refreshDashboard();
