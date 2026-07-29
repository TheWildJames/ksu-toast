import { exec, toast } from 'kernelsu-alt';

const PERSISTENT_DIR = '/data/adb/ksu-toast';
const DAEMON_LOG = `${PERSISTENT_DIR}/daemon.log`;
const DENY_LIST = `${PERSISTENT_DIR}/deny.list`;
const ALLOW_CACHE = `${PERSISTENT_DIR}/allow.cache`;
const DAEMON_PID = `${PERSISTENT_DIR}/daemon.pid`;
const DAEMON_SOCK = `${PERSISTENT_DIR}/daemon.sock`;

let autoRefreshTimer = null;

// ── Tab switching ────────────────────────────────────────
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(tab.dataset.tab).classList.add('active');

        // Refresh content when switching to a tab
        if (tab.dataset.tab === 'dashboard') refreshDashboard();
        if (tab.dataset.tab === 'logs') refreshLogs();
        if (tab.dataset.tab === 'deny') refreshDeny();
    });
});

// ── Helpers ──────────────────────────────────────────────
async function readFile(path) {
    try {
        const result = await exec(`cat "${path}" 2>/dev/null || echo ""`);
        return result.stdout || result || '';
    } catch { return ''; }
}

async function fileExists(path) {
    const r = await exec(`test -f "${path}" && echo 1 || echo 0`);
    return (r.stdout || r || '').trim() === '1';
}

async function fileSize(path) {
    const r = await exec(`wc -c < "${path}" 2>/dev/null || echo 0`);
    return parseInt((r.stdout || r || '').trim()) || 0;
}

async function lineCount(path) {
    const r = await exec(`wc -l < "${path}" 2>/dev/null || echo 0`);
    return parseInt((r.stdout || r || '').trim()) || 0;
}

// ── Dashboard ────────────────────────────────────────────
async function refreshDashboard() {
    const pidExists = await fileExists(DAEMON_PID);
    let daemonRunning = false;
    if (pidExists) {
        const pid = (await readFile(DAEMON_PID)).trim();
        if (pid) {
            const r = await exec(`kill -0 ${pid} 2>/dev/null && echo 1 || echo 0`);
            daemonRunning = (r.stdout || r || '').trim() === '1';
        }
    }
    setText('daemon-status', daemonRunning ? 'Running' : 'Stopped', daemonRunning);

    const sockExists = await fileExists(DAEMON_SOCK);
    setText('socket-status', sockExists ? 'Ready' : 'Missing', sockExists);

    const denyCount = await lineCount(DENY_LIST);
    setText('deny-count', `${denyCount} entries`);

    const cacheCount = await lineCount(ALLOW_CACHE);
    setText('cache-count', `${cacheCount} entries`);

    const timeout = await exec(`getprop ksu.toast.timeout 2>/dev/null || echo 10`);
    setText('timeout-value', `${(timeout.stdout || timeout || '').trim()}s`);

    const apkCheck = await exec(`pm path com.wildkernels.ksutoast 2>/dev/null || echo ""`);
    setText('apk-status', (apkCheck.stdout || apkCheck || '').trim() ? 'Installed' : 'Missing', !!(apkCheck.stdout || apkCheck || '').trim());

    // Get version
    const ver = await exec(`grep "^version=" /data/adb/modules/ksu_toast/module.prop | cut -d= -f2`);
    document.getElementById('version').textContent = (ver.stdout || ver || '').trim();
}

function setText(id, text, isOk) {
    const el = document.getElementById(id);
    el.textContent = text;
    el.className = 'card-value' + (isOk !== undefined ? (isOk ? ' status-ok' : ' status-err') : '');
}

// ── Logs ─────────────────────────────────────────────────
async function refreshLogs() {
    const exists = await fileExists(DAEMON_LOG);
    if (!exists) {
        document.getElementById('log-content').textContent = '(no log file yet)';
        return;
    }
    // Get last 100 lines
    const r = await exec(`tail -100 "${DAEMON_LOG}" 2>/dev/null || echo '(empty)'`);
    const content = (r.stdout || r || '').trim() || '(empty)';
    document.getElementById('log-content').textContent = content;
}

function startAutoRefresh() {
    stopAutoRefresh();
    autoRefreshTimer = setInterval(refreshLogs, 5000);
}

function stopAutoRefresh() {
    if (autoRefreshTimer) { clearInterval(autoRefreshTimer); autoRefreshTimer = null; }
}

// ── Deny List ────────────────────────────────────────────
async function refreshDeny() {
    const exists = await fileExists(DENY_LIST);
    if (!exists) {
        document.getElementById('deny-content').innerHTML = '<div class="empty-msg">No deny list file</div>';
        return;
    }
    const r = await exec(`cat "${DENY_LIST}" 2>/dev/null`);
    const content = (r.stdout || r || '').trim();
    const container = document.getElementById('deny-content');
    if (!content) {
        container.innerHTML = '<div class="empty-msg">Deny list is empty</div>';
        return;
    }
    const lines = content.split('\n').filter(l => l.trim());
    container.innerHTML = lines.map(uid =>
        `<div class="list-item"><span>UID: ${uid}</span></div>`
    ).join('');
}

// ── Config ───────────────────────────────────────────────
const timeoutSlider = document.getElementById('timeout-slider');
const timeoutDisplay = document.getElementById('timeout-display');
timeoutSlider.addEventListener('input', () => {
    timeoutDisplay.textContent = `${timeoutSlider.value}s`;
});

// Load current timeout
(async () => {
    const r = await exec(`getprop ksu.toast.timeout 2>/dev/null || echo 10`);
    const val = parseInt((r.stdout || r || '').trim()) || 10;
    timeoutSlider.value = val;
    timeoutDisplay.textContent = `${val}s`;
})();

// ── Button handlers ──────────────────────────────────────
document.getElementById('refresh-dashboard').addEventListener('click', refreshDashboard);

document.getElementById('refresh-logs').addEventListener('click', refreshLogs);
document.getElementById('clear-logs').addEventListener('click', async () => {
    await exec(`echo "" > "${DAEMON_LOG}" 2>/dev/null`);
    toast('Logs cleared');
    refreshLogs();
});
document.getElementById('auto-refresh').addEventListener('change', (e) => {
    if (e.target.checked) startAutoRefresh();
    else stopAutoRefresh();
});

document.getElementById('refresh-deny').addEventListener('click', refreshDeny);
document.getElementById('clear-deny').addEventListener('click', async () => {
    await exec(`echo "" > "${DENY_LIST}" 2>/dev/null`);
    toast('Deny list cleared');
    refreshDeny();
    refreshDashboard();
});

document.getElementById('save-timeout').addEventListener('click', async () => {
    const val = timeoutSlider.value;
    await exec(`setprop ksu.toast.timeout ${val}`);
    toast(`Timeout set to ${val}s`);
    refreshDashboard();
});

document.getElementById('clear-cache').addEventListener('click', async () => {
    await exec(`echo "" > "${ALLOW_CACHE}" 2>/dev/null`);
    toast('Allow cache cleared');
    refreshDashboard();
});

document.getElementById('restart-daemon').addEventListener('click', async () => {
    await exec(`
        PID=$(cat "${DAEMON_PID}" 2>/dev/null)
        [ -n "$PID" ] && kill "$PID" 2>/dev/null
        sleep 1
        rm -f "${PERSISTENT_DIR}/daemon.sock" "${PERSISTENT_DIR}/daemon.pid"
        /system/bin/ksu-toastd \\
            --socket "${DAEMON_SOCK}" \\
            --apk-socket "@ksu-toast-apk" \\
            --deny-list "${DENY_LIST}" \\
            --cache "${ALLOW_CACHE}" \\
            --config "${PERSISTENT_DIR}/config" \\
            > "${DAEMON_LOG}" 2>&1 &
        echo $! > "${DAEMON_PID}"
    `);
    toast('Daemon restarted');
    setTimeout(refreshDashboard, 2000);
});

// ── Init ─────────────────────────────────────────────────
refreshDashboard();
