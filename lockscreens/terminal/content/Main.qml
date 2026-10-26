import QtQuick
import QtQuick.Window

// Mainframe - phosphor console lock, rebuilt as a native qylock skin.
// Vignette-only post effect (no CRT): flat phosphor console. Uses the qylock
// `sddm` API (login / powerOff / reboot / suspend, userModel, sessionModel,
// keyboard) plus live /proc system stats and MPRIS media.
Rectangle {
    id: root
    width: Screen.width; height: Screen.height; color: "#161616"

    // ── qylock / sddm plumbing ────────────────────────────────────────────
    property int sessionIndex: (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    // true once the operator picked a session from the chip; until then the index
    // follows sessionModel.lastIndex as the shim finishes enumerating sessions
    property bool sessionPicked: false
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    ListView { id: userHelper; model: userModel; currentIndex: root.userIndex; opacity: 0; width: 100; height: 100; z: -100; delegate: Item { property string uName: model.realName || model.name || ""; property string uLogin: model.name || "" } }

    // ── scale / fonts / colors ────────────────────────────────────────────
    readonly property real s: Math.max(0.7, Math.min(2, Math.min(width / 1920, height / 1080)))
    readonly property string mono: "Iosevka Nerd Font"
    readonly property real fontPx: 20 * s
    readonly property real lineH: Math.round(fontPx * 1.4)
    readonly property real margin: 64 * s
    readonly property int cols: Math.max(20, Math.floor((width - 2 * margin) / Math.max(1, glyph.advanceWidth)))
    // palette (huemint 161616-bb2626-fafafa): #161616 surface, #fafafa text,
    // #bb2626 accent. No orange left anywhere.
    readonly property color ph:    "#fafafa"
    readonly property color phHi:  "#bb2626"
    readonly property color phDim: Qt.rgba(ph.r * 0.5, ph.g * 0.5, ph.b * 0.5, 1)
    readonly property color err:   "#bb2626"
    readonly property string user: (userHelper.currentItem && userHelper.currentItem.uLogin) ? userHelper.currentItem.uLogin : (typeof userModel !== "undefined" ? userModel.lastUser : "user")
    property string host: "mainframe"
    // Portability (docs/02-engine.md § Portability): Quickshell.env is not available
    // in the lock context, so home is derived from this file's own URL.
    //   file:///home/<user>/.local/share/qylock/themes/<slug>/Main.qml
    //   terminal → themes → qylock → share → .local → HOME  (five ".." levels)
    readonly property string homeDir: Qt.resolvedUrl("../../../../..").toString().replace(/\/$/, "")
    readonly property string homePath: homeDir.replace(/^file:\/\//, "")

    // ── live system stats (read from /proc + /sys, no daemon) ─────────────
    // scheduler counters out of /proc/loadavg ("0.42 0.31 0.20 2/412 12345");
    // these drive the PROCESSES box
    property string procsRunning: "--"
    property string procsThreads: "--"
    property string lastPid: "--"
    // process table from ~/.cache/qylock-procs, written by qylock-procs-daemon
    // (same pattern as qylock-media-daemon: the lock cannot list /proc itself)
    property var procs: []
    property string load1: "--"; property string load5: "--"; property string load15: "--"
    property string cpuTemp: "--"
    property int memUsedPct: 0
    property real memUsed: 0; property real memTotal: 0
    property string lockedFor: "--"
    property real lockStartUptime: -1
    property bool capsOn: false; property bool numOn: false

    // ── media / system / keyboard (MPRIS via daemon status files read with
    // XMLHttpRequest; Quickshell.Io is blackholed in the lock context) ─────
    Timer {
        id: mediaTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: { readUptime(); readSystem(); readKeyboard(); readProcs(); }
    }
    function readUptime() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///proc/uptime", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var sec = Math.floor(parseFloat(xhr.responseText.split(' ')[0]));
                var d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60), ss = Math.floor(sec % 60);
                root.hostUptime = sec > 0 ? (d > 0 ? d + "d " : "") + h + "h " + m + "m " + ss + "s" : "?h ?m";
                if (root.lockStartUptime < 0) root.lockStartUptime = sec;
                var el = Math.floor(sec - root.lockStartUptime);
                var eh = Math.floor(el / 3600), em = Math.floor((el % 3600) / 60), es = Math.floor(el % 60);
                root.lockedFor = (eh > 0 ? eh + "h " : "") + (em > 0 || eh > 0 ? em + "m " : "") + es + "s";
            }
        } catch (e) { }
    }
    function readSystem() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///proc/loadavg", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var f = xhr.responseText.trim().split(/\s+/);
                root.load1 = f[0] || "--"; root.load5 = f[1] || "--"; root.load15 = f[2] || "--";
                // field 4 is "running/total" scheduler entities, field 5 is the
                // last pid the kernel allocated
                var rt = (f[3] || "").split("/");
                root.procsRunning = rt[0] || "--";
                root.procsThreads = rt[1] || "--";
                root.lastPid = f[4] || "--";
            }
        } catch (e) { }
        xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///sys/class/thermal/thermal_zone0/temp", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var t = parseInt(xhr.responseText.trim());
                root.cpuTemp = isNaN(t) ? "--" : Math.round(t / 1000) + "°C";
            }
        } catch (e) { }
        xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///proc/meminfo", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var mt = xhr.responseText.match(/MemTotal:\s+(\d+)/);
                var ma = xhr.responseText.match(/MemAvailable:\s+(\d+)/);
                if (mt && ma) {
                    var total = parseInt(mt[1]), avail = parseInt(ma[1]);
                    root.memUsed = (total - avail) / 1024;
                    root.memTotal = total / 1024;
                    root.memUsedPct = Math.round((total - avail) / total * 100);
                }
            }
        } catch (e) { }
    }
    // process table: eight rows, one atomic cache file, written every 2s by
    // qylock-procs-daemon. Lines are pid|comm|cpu%|rss_kb.
    function readProcs() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file://" + root.homePath + "/.cache/qylock-procs", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var out = [], lines = xhr.responseText.trim().split("\n");
                for (var i = 0; i < lines.length && i < 8; i++) {
                    var f = lines[i].split("|");
                    if (f.length >= 4) out.push({ pid: f[0], name: f[1], cpu: f[2], rss: f[3] });
                }
                root.procs = out;
            }
        } catch (e) { }
    }
    function memStr(kb) {
        var n = parseInt(kb) || 0;
        return n >= 1024 ? Math.round(n / 1024) + "M" : n + "K";
    }
    // right-align helper: padStart is not guaranteed in the lock's JS engine,
    // padEnd is (boxRow already relies on it)
    function ralign(s, n) {
        s = String(s);
        while (s.length < n) s = " " + s;
        return s;
    }
    // one table row in the RATZILLA-OPS style: [>]pid name cpu mem
    function procLine(sel, pid, name, cpu, mem) {
        var l = String(sel).charAt(0) + ralign(pid, 6) + " "
              + String(name).substring(0, 11).padEnd(11) + " "
              + ralign(cpu, 5) + " " + ralign(mem, 6);
        return "│ " + l.substring(0, boxW - 4).padEnd(boxW - 4) + " │";
    }
    function procTable() {
        if (root.procs.length === 0) {
            // no qylock-procs-daemon on this machine: never show an invented
            // process list, show the scheduler counters we can always read
            return [root.boxTop("PROCESSES", root.procsRunning + "/" + root.procsThreads),
                    root.boxRow("running", root.procsRunning),
                    root.boxRow("threads", root.procsThreads),
                    root.boxRow("last pid", root.lastPid),
                    root.boxRow("load", root.load1 + " " + root.load5),
                    root.boxBottom()].join("\n");
        }
        var lines = [root.boxTop("PROCESSES", root.procsRunning + "/" + root.procsThreads),
                     root.procLine(" ", "PID", "NAME", "CPU", "MEM")];
        for (var i = 0; i < root.procs.length; i++) {
            var p = root.procs[i];
            lines.push(root.procLine(i === 0 ? ">" : " ", p.pid, p.name, p.cpu, root.memStr(p.rss)));
        }
        lines.push(root.boxBottom());
        return lines.join("\n");
    }

    function readKeyboard() {
        if (typeof keyboard !== "undefined") {
            root.capsOn = keyboard.capsLock;
            root.numOn = keyboard.numLock;
        }
    }

    // ── clock ──────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.now = new Date() }

    // ── CRT choreography (termOn gate kept; squash/flash now feed nothing
    //    but remain declared and harmless) ──────────────────────────────────
    property real termOn: 0
    property real termSqX: 1
    property real termSqY: 0
    property real termFlash: 0
    property real glitch: 0
    property bool cursorOn: true
    property bool verifying: false
    property bool denied: false
    property string pwdText: ""
    property int attemptCount: 0
    property bool eqB: false
    property string hostUptime: "?h ?m"
    property real denyFlash: 0
    property int loaderStep: 0
    // CRT post-effect: time in SECONDS (the shader uses floor(time*30) for flicker
    // and floor(time*24) for glitch bands), plus the two tuning knobs.
    property real shaderTime: 0
    property real crtAmount: 0.40
    property real bloomAmount: 0.15

    // ── log queue ──────────────────────────────────────────────────────────
    property var _queue: []
    property int _typedChars: 0
    ListModel { id: log }

    function esc(s) { return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/ /g,"&nbsp;"); }
    readonly property color sw0: "#fafafa"
    readonly property color sw1: "#bb2626"
    readonly property color sw2: "#8f1d1d"
    readonly property color sw3: "#5c1414"
    readonly property color sw4: "#2a1111"
    function toneColor(t) { return t === "err" ? err : t === "dim" ? sw3 : t === "hi" ? sw0 : t === "logo" ? sw2 : sw1; }
    function styled(tag, text, tone) {
        var body = '<font color="' + toneColor(tone) + '">' + esc(text) + "</font>";
        if (!tag) return body;
        return '<font color="' + phHi + '"><b>' + esc("[" + tag + "]") + "</b></font>" + esc(" ") + body;
    }
    function say(tag, text, tone, typed) {
        var q = _queue.slice(); q.push({ tag: tag||"", text: text, tone: tone||"plain", typed: typed===true }); _queue = q;
        if (!pump.running) pump.start();
    }
    function pushLine(html) {
        log.append({ html: html });
        var max = Math.max(4, Math.floor(logArea.height / lineH) - 2);
        while (log.count > max) log.remove(0);
    }
    function pumpOnce(instant) {
        if (_queue.length === 0) return false;
        var item = _queue[0];
        if (item.typed && !instant) {
            if (_typedChars === 0) pushLine("");
            _typedChars += 1;
            log.setProperty(log.count - 1, "html", styled(item.tag, String(item.text).slice(0, _typedChars), item.tone) + '<font color="' + phHi + '">█</font>');
            if (_typedChars < item.text.length) return true;
            log.setProperty(log.count - 1, "html", styled(item.tag, item.text, item.tone));
            _typedChars = 0;
        } else {
            pushLine(styled(item.tag, item.text, item.tone));
        }
        _queue = _queue.slice(1);
        return true;
    }
    function post(label, value, ok) {
        var dots = ".".repeat(Math.max(2, 34 - label.length - String(value).length - 2));
        say("", label + " " + dots + " " + (ok || "OK"));
    }
    function boot() {
        say("", "> lockdown --user " + user + " --reason away", "hi", true);
        post("input devices", "", "sealed");
        post("session keyring", "", "sealed");
        post("faillock counter", "3", "armed");
        post("screen blank", "", "10s");
        say("", "lock  " + "█".repeat(24) + " done");
        say(" LOCK ", "Session locked at " + Qt.formatTime(now, "hh:mm:ss"), "hi");
        say("", " ");
        say("", host + " login: " + user);
    }

    Timer { id: pump; interval: root._typedChars > 0 || (root._queue.length > 0 && root._queue[0].typed) ? 14 : 75; repeat: true; onTriggered: { if (!root.pumpOnce(false)) stop(); } }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.cursorOn = !root.cursorOn }
    Timer { interval: 110; repeat: true; running: root.verifying; onTriggered: root.loaderStep = (root.loaderStep + 1) % 7 }
    Timer { interval: 100; repeat: true; running: true; onTriggered: root.shaderTime += 0.1 }
    Timer { interval: 260; repeat: true; running: true; onTriggered: root.eqB = !root.eqB }

    // ── tty-clock digits ───────────────────────────────────────────────────
    readonly property var digitRows: ({
        "0": ["111","101","101","101","111"], "1": ["010","110","010","010","111"],
        "2": ["111","001","111","100","111"], "3": ["111","001","111","001","111"],
        "4": ["101","101","111","001","001"], "5": ["111","100","111","001","111"],
        "6": ["111","100","111","101","111"], "7": ["111","001","001","001","001"],
        "8": ["111","101","111","101","111"], "9": ["111","101","111","001","111"],
        ":": ["0","1","0","1","0"]
    })

    // ── block banner letters (5x5) for the hostname ────────────────────────
    readonly property var letterRows: ({
        "M": ["10001","11011","10101","10001","10001"],
        "A": ["01110","10001","11111","10001","10001"],
        "I": ["11111","00100","00100","00100","11111"],
        "N": ["10001","11001","10101","10011","10001"],
        "F": ["11111","10000","11110","10000","10000"],
        "R": ["11110","10001","11110","10100","10010"],
        "E": ["11111","10000","11110","10000","11111"],
        " ": ["00000","00000","00000","00000","00000"]
    })

    // ── info boxes ─────────────────────────────────────────────────────────
    readonly property int boxW: 38
    function boxTop(t, v) {
        if (v === undefined || v === null || v === "") return "┌─ " + t + " " + "─".repeat(Math.max(0, boxW - t.length - 5)) + "┐";
        var val = " " + String(v) + " ─┐";
        return "┌─ " + t + " " + "─".repeat(Math.max(0, boxW - t.length - 4 - val.length)) + val;
    }
    function boxRow(l, v) { var inner = (l.padEnd(10) + v).slice(0, boxW - 4); return "│ " + inner.padEnd(boxW - 4) + " │"; }
    function boxBottom() { return "└" + "─".repeat(boxW - 2) + "┘"; }
    readonly property var eighths: ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
    function bar(pct, cells) {
        cells = cells || 10;
        var total = Math.max(0, Math.min(100, pct)) / 100 * cells * 8;
        var full = Math.floor(total / 8), part = Math.floor(total % 8);
        var s = "█".repeat(full) + eighths[part];
        var used = full + (part > 0 ? 1 : 0);
        return s + "░".repeat(Math.max(0, cells - used));
    }

    // ── scene ──────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "black" }
    TextMetrics { id: glyph; font.family: root.mono; font.pixelSize: root.fontPx; text: "M" }

    Item {
        id: tty
        anchors.fill: parent
        visible: root.termOn > 0
        layer.enabled: true
        layer.effect: ShaderEffect {
            property real itemWidth: width
            property real itemHeight: height
            // lock_crt.frag.qsb uniforms (names are fixed by the shader's buf block):
            //   crt   0..1  barrel curvature + chromatic fringe + scanlines + vignette + flicker
            //   bloom 0..1  phosphor glow
            //   squashY     power-on/off collapse - driven by the existing powerOn animation
            //   flash/glitch            spare effects, 0 when idle
            //   time       SECONDS (flicker/glitch quantise it)
            property real crt: root.crtAmount
            property real bloom: root.bloomAmount
            property real squashX: 1.0
            property real squashY: Math.max(0.12, root.termSqY)
            property real flash: 0.0
            property real glitch: root.glitch
            property real time: root.shaderTime
            fragmentShader: Qt.resolvedUrl("shaders/lock_crt.frag.qsb")
        }

        Rectangle { anchors.fill: parent; color: Qt.rgba(root.ph.r * 0.035, root.ph.g * 0.035, root.ph.b * 0.035, 1) }

        // hostname block banner
        Row {
            id: banner
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20 * root.s
            spacing: Math.round(7 * root.s * 1.4)
            Repeater {
                model: root.host.toUpperCase().split("")
                Grid {
                    id: letter
                    required property string modelData
                    readonly property var bitmap: root.letterRows[modelData] ?? root.letterRows[" "]
                    columns: 5
                    spacing: 1
                    Repeater {
                        model: letter.bitmap.length * letter.columns
                        Rectangle {
                            required property int index
                            readonly property bool lit: letter.bitmap[Math.floor(index / letter.columns)].charAt(index % letter.columns) === "1"
                            width: 7 * root.s; height: 7 * root.s
                            color: lit ? root.phHi : Qt.rgba(root.ph.r, root.ph.g, root.ph.b, 0.05)
                        }
                    }
                }
            }
        }

        // subheader: console id + caps/num + date
        Text {
            x: root.margin; y: 62 * root.s
            textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx * 0.8; color: root.phDim
            text: "SECURE CONSOLE · tty1 · b2"
                + (root.capsOn ? "  ·  CAPS" : "")
                + (root.numOn ? "  ·  NUM" : "")
                + "  │  " + Qt.formatDateTime(root.now, "ddd yyyy-MM-dd hh:mm:ss").toUpperCase()
        }
        Text {
            x: root.margin; y: 90 * root.s
            textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.phDim
            text: "═".repeat(root.cols)
        }

        // log area
        Item {
            id: logArea
            x: root.margin; y: 146 * root.s
            width: root.width - 2 * root.margin - (root.boxW + 4) * glyph.advanceWidth
            height: bigClockText.y - y - 2 * root.lineH
            Column {
                id: logColumn
                width: parent.width
                Repeater {
                    model: log
                    Text { required property string html; width: logColumn.width; height: root.lineH; elide: Text.ElideRight; textFormat: Text.StyledText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.ph; text: html }
                }
                Text {
                    width: logColumn.width; height: root.lineH
                    visible: root.verifying
                    textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.phDim
                    text: "Password:  [" + "█".repeat(root.loaderStep) + " ".repeat(6 - root.loaderStep) + "]  authenticating"
                }
                Text {
                    width: logColumn.width; height: root.lineH
                    visible: !root.verifying && root._queue.length === 0 && log.count > 0
                    textFormat: Text.StyledText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.ph
                    readonly property string stars: "*".repeat(Math.min(root.pwdText.length, 64))
                    readonly property string tail: root.cursorOn ? '<font color="' + root.phHi + '">█</font>' : ""
                    text: "Password:&nbsp;" + '<font color="' + (root.denied ? root.err : root.phHi) + '">' + stars + "</font>" + tail
                }
            }
        }

        // media state lives in the SYSTEM box (`audio` row) - no second line here

        // big tty-clock
        Row {
            id: bigClockText
            readonly property real px: 22 * root.s
            readonly property bool colonOn: root.now.getSeconds() % 2 === 0
            // centred on the SCREEN, not on logArea: logArea stops short of the
            // SYSTEM box (see its width binding), so centring inside it pushed the
            // clock left by half that box width. Explicit screen centred x.
            x: Math.round((root.width - width) / 2)
            y: root.height * 0.56
            spacing: px * 1.1
            Repeater {
                model: Qt.formatTime(root.now, "hh:mm").split("")
                Grid {
                    id: digit
                    required property string modelData
                    readonly property var bitmap: root.digitRows[modelData] ?? root.digitRows["0"]
                    columns: bitmap[0].length
                    spacing: bigClockText.px * 0.16
                    Repeater {
                        model: digit.bitmap.length * digit.columns
                        Rectangle {
                            required property int index
                            readonly property bool lit: digit.bitmap[Math.floor(index / digit.columns)].charAt(index % digit.columns) === "1" && (digit.modelData !== ":" || bigClockText.colonOn)
                            width: bigClockText.px; height: bigClockText.px
                            color: lit ? root.phHi : Qt.rgba(root.ph.r, root.ph.g, root.ph.b, 0.05)
                        }
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: bigClockText.horizontalCenter
            anchors.top: bigClockText.bottom; anchors.topMargin: root.lineH * 0.6
            textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; font.letterSpacing: 4 * root.s; color: root.phDim
            text: Qt.formatDate(root.now, "dddd d MMMM yyyy").toUpperCase()
        }

        // SYSTEM box + PROCESSES box: the right column used to end halfway down
        // the log column, so the second box also fills that gap.
        Column {
            anchors.right: parent.right; anchors.rightMargin: root.margin
            y: 146 * root.s
            spacing: root.lineH
            Text {
                textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; lineHeight: root.lineH; lineHeightMode: Text.FixedHeight; color: root.ph
                text: [
                    root.boxTop("SYSTEM", root.cpuTemp),
                    root.boxRow("host", root.host),
                    root.boxRow("uptime", root.hostUptime),
                    root.boxRow("locked", root.lockedFor),
                    root.boxRow("load", root.load1 + " " + root.load5),
                    root.boxRow("temp", root.cpuTemp),
                    root.boxRow("mem", root.memUsedPct + "% " + root.bar(root.memUsedPct, 16)),
                    root.boxBottom()
                ].join("\n")
            }
            // PROCESSES: the RATZILLA-OPS table (pid / name / cpu / mem, '>' on the
            // top row). Rows come from ~/.cache/qylock-procs, written by
            // qylock-procs-daemon; the lock cannot list /proc by itself.
            Text {
                textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; lineHeight: root.lineH; lineHeightMode: Text.FixedHeight; color: root.ph
                text: root.procTable()
            }
        }

        // power row
        Text {
            x: root.margin; anchors.bottom: powerRow.top; anchors.bottomMargin: root.lineH * 0.5
            textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.phDim
            text: "─".repeat(root.cols)
        }
        Row {
            id: powerRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * root.s
            spacing: 3 * glyph.advanceWidth

            // session switcher - shows the session that sddm.login will start
            // (root.sessionIndex is exactly the value handed to login)
            Text {
                id: sessionChip
                readonly property int n: (typeof sessionModel !== "undefined" && sessionModel.count > 0) ? sessionModel.count : 0
                readonly property string label: (n > 0 && root.sessionIndex >= 0 && root.sessionIndex < n) ? String(sessionModel.get(root.sessionIndex).name) : "SESSION"
                textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx
                color: (chipArea.containsMouse && n > 1) ? root.phHi : root.phDim
                text: "[ SESSION: " + label.toUpperCase() + (n > 1 ? "  ⇄" : "") + " ]"
                MouseArea {
                    id: chipArea
                    anchors.fill: parent; anchors.margins: -10 * root.s
                    hoverEnabled: true
                    // qualify with the id: inside a nested MouseArea the parent's
                    // properties are not in scope, so a bare `n` is a ReferenceError
                    cursorShape: sessionChip.n > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (sessionChip.n > 1) {
                            root.sessionPicked = true;
                            root.sessionIndex = (root.sessionIndex + 1) % sessionChip.n;
                        }
                    }
                }
            }

            Repeater {
                model: [
                    { label: "SLEEP", act: "suspend" },
                    { label: "REBOOT", act: "reboot" },
                    { label: "SHUTDOWN", act: "poweroff" }
                ]
                Text {
                    id: key
                    required property var modelData
                    textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx
                    color: keyArea.containsMouse ? root.phHi : root.phDim
                    text: "[ " + modelData.label + " ]"
                    MouseArea {
                        id: keyArea
                        anchors.fill: parent; anchors.margins: -10 * root.s
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (typeof sddm !== "undefined") sddm[modelData.act]() }
                    }
                }
            }
            Text { textFormat: Text.PlainText; font.family: root.mono; font.pixelSize: root.fontPx; color: root.phDim; text: "(click)" }
        }

        // deny flash overlay (stronger reject feedback)
        Rectangle {
            anchors.fill: parent
            color: root.err
            opacity: root.denyFlash
            visible: root.denyFlash > 0
            z: 999
        }
    }

    // ── password input (hidden, captures keys) ────────────────────────────
    TextInput {
        id: pwd
        anchors.fill: parent
        visible: false
        focus: true
        echoMode: TextInput.Password
        onTextChanged: { root.pwdText = text; if (text.length > 0 && root.denied) root.denied = false }
        Keys.onReturnPressed: if (!root.verifying) doLogin()
        Keys.onEnterPressed: if (!root.verifying) doLogin()
        Keys.onEscapePressed: { text = ""; root.pwdText = ""; }
    }

    // Auto-focus fix for Quickshell lock (Loader does not propagate focus: true
    // in time; force ActiveFocus after the surface settles, like pixel-rainyroom).
    Timer { id: focusFix; interval: 300; running: true; onTriggered: pwd.forceActiveFocus() }

    // deny flash animation (explicit target, avoids the cross-object
    // `on <prop>` pitfall that black-screens the lock)
    SequentialAnimation {
        id: denyAnim
        PropertyAction { target: root; property: "denyFlash"; value: 0.55 }
        NumberAnimation { target: root; property: "denyFlash"; to: 0; duration: 550; easing.type: Easing.OutCubic }
    }

    // the shim enumerates sessions asynchronously, so lastIndex is 0 at construction.
    // Adopt the matched index as soon as the model fills - but never override a
    // choice the operator made on the chip.
    Connections {
        target: typeof sessionModel !== "undefined" ? sessionModel : null
        ignoreUnknownSignals: true
        function syncFromSessionModel() {
            if (root.sessionPicked || typeof sessionModel === "undefined") return;
            var n = sessionModel.count, i = sessionModel.lastIndex;
            if (n > 0 && i >= 0 && i < n) root.sessionIndex = i;
        }
        function onCountChanged() { syncFromSessionModel(); }
        function onLastIndexChanged() { syncFromSessionModel(); }
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        function onLoginFailed() {
            root.verifying = false;
            root.attemptCount++;
            root.denied = true;
            denyAnim.restart();
            root.say("", root.host + " login: " + root.user + "   [attempt " + root.attemptCount + "]", "hi", true);
            root.say("AUTH-ERR", "Password verification failed for " + root.user, "err");
            root.say(" hint ", "3 failed attempts → faillock lockout", "dim");
            root.say("", " ");
            root.say("", root.host + " login: " + root.user);
            pwd.text = ""; root.pwdText = ""; pwd.focus = true;
        }
        function onLoginSucceeded() {
            root.verifying = false;
            root.say("  OK  ", "Access granted - session unsealed", "hi");
            root.say("  OK  ", "Resuming desktop session");
        }
    }

    function doLogin() {
        var u = (userHelper.currentItem && userHelper.currentItem.uLogin) ? userHelper.currentItem.uLogin : (typeof userModel !== "undefined" ? userModel.lastUser : "");
        root.verifying = true;
        if (typeof sddm !== "undefined") sddm.login(u, pwd.text, root.sessionIndex);
    }

    // ── boot choreography ──────────────────────────────────────────────────
    Component.onCompleted: {
        pwd.forceActiveFocus();
        if (typeof keyboard !== "undefined") keyboard.numLock = true;
        readUptime();
        readSystem();
        readKeyboard();
        powerOn.start();
    }

    SequentialAnimation {
        id: powerOn
        PropertyAction { target: root; property: "termSqY"; value: 0 }
        PropertyAction { target: root; property: "termFlash"; value: 0.7 }
        PropertyAction { target: root; property: "termOn"; value: 1 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "termSqY"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "termFlash"; to: 0; duration: 420; easing.type: Easing.OutQuad }
        }
        ScriptAction { script: root.boot() }
    }
}