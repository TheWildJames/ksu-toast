import { exec, toast } from 'kernelsu-alt';

const PERSISTENT_DIR = '/data/adb/ksu-toast';
const DAEMON_LOG = `${PERSISTENT_DIR}/daemon.log`;
const DENY_LIST = `${PERSISTENT_DIR}/deny.list`;
const ALLOW_CACHE = `${PERSISTENT_DIR}/allow.cache`;
const DAEMON_PID = `${PERSISTENT_DIR}/daemon.pid`;
const DAEMON_SOCK = `${PERSISTENT_DIR}/daemon.sock`;

function run(cmd) {
    return exec(cmd).then(r => r).catch(() => ({ stdout: '', errno: -1 }));
}

function get$(id) { return document.getElementById(id); }

// ── Tab switching ────────────────────────────────────────
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        get$(tab.dataset.tab).classList.add('active');
        if (tab.dataset.tab === 'dashboard') refreshDashboard();
        if (tab.dataset.tab === 'logs') refreshLogs();
        if (tab.dataset.tab === 'deny') refreshDeny();
    });
});

// ── Dashboard ────────────────────────────────────────────
async function refreshDashboard() {
    const pidR = await run(`cat "${DAEMON_PID}" 2>/dev/null`);
    const pid = pidR.stdout ? pidR.stdout.trim() : '';
    let running = false;
    if (pid) {
        const check = await run(`kill -0 ${pid} 2>/dev/null && echo 1 || echo 0`);
        running = check.stdout.trim() === '1';
    }
    get$('daemon-status').textContent = running ? 'Running' : (pid ? 'Stale' : 'Stopped');
    get$('daemon-status').className = running ? 'status-ok' : 'status-err';

    const sockR = await run(`test -S "${DAEMON_SOCK}" && echo 1 || echo 0`);
    const sockOk = sockR.stdout.trim() === '1';
    get$('socket-status').textContent = sockOk ? 'Ready' : 'Missing';
    get$('socket-status').className = sockOk ? 'status-ok' : 'status-err';

    const denyR = await run(`wc -l < "${DENY_LIST}" 2>/dev/null || echo 0`);
    get$('deny-count').textContent = (parseInt(denyR.stdout) || 0) + ' entries';

    const cacheR = await run(`wc -l < "${ALLOW_CACHE}" 2>/dev/null || echo 0`);
    get$('cache-count').textContent = (parseInt(cacheR.stdout) || 0) + ' entries';

    const timeR = await run('getprop ksu.toast.timeout 2>/dev/null || echo 10');
    get$('timeout-value').textContent = (parseInt(timeR.stdout) || 10) + 's';

    const apkR = await run('pm path com.wildkernels.ksutoast 2>/dev/null || echo ""');
    const apkOk = !!apkR.stdout.trim();
    get$('apk-status').textContent = apkOk ? 'Installed' : 'Missing';
    get$('apk-status').className = apkOk ? 'status-ok' : 'status-err';

    const verR = await run('grep "^version=" /data/adb/modules/ksu_toast/module.prop | cut -d= -f2');
    get$('version').textContent = verR.stdout ? verR.stdout.trim() : '';
}

// ── Logs ─────────────────────────────────────────────────
let autoTimer = null;

async function refreshLogs() {
    const r = await run(`test -f "${DAEMON_LOG}" && echo 1 || echo 0`);
    if (r.stdout.trim() !== '1') {
        get$('log-content').textContent = '(no log file)';
        return;
    }
    const logR = await run(`tail -100 "${DAEMON_LOG}" 2>/dev/null || echo '(empty)'`);
    get$('log-content').textContent = logR.stdout || '(empty)';
    get$('log-content').scrollTop = get$('log-content').scrollHeight;
}

get$('refresh-logs').addEventListener('click', refreshLogs);
get$('clear-logs').addEventListener('click', async () => {
    await run(`: > "${DAEMON_LOG}" 2>/dev/null`);  // truncate
    toast('Logs cleared');
    refreshLogs();
});
get$('auto-refresh').addEventListener('change', e => {
    if (e.target.checked) {
        if (autoTimer) clearInterval(autoTimer);
        autoTimer = setInterval(refreshLogs, 5000);
    } else {
        if (autoTimer) { clearInterval(autoTimer); autoTimer = null; }
    }
});

// ── Deny List ────────────────────────────────────────────
async function refreshDeny() {
    const r = await run(`cat "${DENY_LIST}" 2>/dev/null`);
    const items = r.stdout ? r.stdout.trim().split('\n').filter(l => l.trim()) : [];
    const container = get$('deny-content');
    if (items.length === 0) {
        container.innerHTML = '<div class="empty-msg">Deny list is empty</div>';
        return;
    }
    container.innerHTML = items.map(uid =>
        `<div class="list-item"><span>UID: ${uid}</span></div>`
    ).join('');
}

get$('refresh-deny').addEventListener('click', refreshDeny);
get$('clear-deny').addEventListener('click', async () => {
    await run(`: > "${DENY_LIST}" 2>/dev/null`);
    toast('Deny list cleared');
    refreshDeny();
    refreshDashboard();
});

// ── Config ───────────────────────────────────────────────
const timeoutSlider = get$('timeout-slider');
get$('timeout-display').textContent = timeoutSlider.value + 's';
timeoutSlider.addEventListener('input', () => {
    get$('timeout-display').textContent = timeoutSlider.value + 's';
});

run('getprop ksu.toast.timeout 2>/dev/null || echo 10').then(r => {
    const val = parseInt(r.stdout) || 10;
    timeoutSlider.value = val;
    get$('timeout-display').textContent = val + 's';
});

get$('save-timeout').addEventListener('click', async () => {
    const val = timeoutSlider.value;
    await run(`setprop ksu.toast.timeout ${val}`);
    // Persist to config file (survives reboot)
    await run(`mkdir -p "${PERSISTENT_DIR}/config" && echo ${val} > "${PERSISTENT_DIR}/config/timeout"`);
    toast('Timeout saved to ' + val + 's');
    refreshDashboard();
});

get$('clear-cache').addEventListener('click', async () => {
    await run(`: > "${ALLOW_CACHE}" 2>/dev/null`);
    toast('Allow cache cleared');
    refreshDashboard();
});

get$('restart-daemon').addEventListener('click', async () => {
    const r = await run(`cat "${DAEMON_PID}" 2>/dev/null`);
    const pid = r.stdout ? r.stdout.trim() : '';
    if (pid) await run(`kill "${pid}" 2>/dev/null; sleep 1`);
    await run(`rm -f "${PERSISTENT_DIR}/daemon.sock" "${DAEMON_PID}"`);
    await run(`
        /system/bin/ksu-toastd \\
            --socket "${PERSISTENT_DIR}/daemon.sock" \\
            --apk-socket "@ksu-toast-apk" \\
            --deny-list "${DENY_LIST}" \\
            --cache "${ALLOW_CACHE}" \\
            --config "${PERSISTENT_DIR}/config" \\
            > "${DAEMON_LOG}" 2>&1 &
    `);
    // Write PID
    await run(`echo $! > "${DAEMON_PID}" 2>/dev/null`);
    toast('Daemon restarted');
    setTimeout(refreshDashboard, 2000);
});

// ── Init ─────────────────────────────────────────────────
refreshDashboard();
