import QtQuick
import QtQuick.Window

// pdp11-panel - a PDP-11/70 style front panel lock for Ryoku (qylock engine).
// Scene only: the password plumbing below is the same one the proven terminal
// skin uses, and it is what actually authenticates. Palette measured against
// #121110 on 2026-10-26: cream 14.62:1, amber 8.39:1, label 5.03:1, red 3.35:1
// (red is used for lamps and large glyphs only, never for the password dots).
Rectangle {
    id: root
    width: Screen.width; height: Screen.height; color: "#121110"

    // ── qylock / sddm plumbing ────────────────────────────────────────────
    property int sessionIndex: (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    // true once the operator picked a session on the plate; until then the index
    // follows sessionModel.lastIndex as the shim finishes enumerating sessions
    property bool sessionPicked: false
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    ListView { id: userHelper; model: userModel; currentIndex: root.userIndex; opacity: 0; width: 100; height: 100; z: -100; delegate: Item { property string uLogin: model.name || "" } }

    // ── palette / metrics ─────────────────────────────────────────────────
    readonly property color ph:       "#E8E2D6"
    readonly property color phHi:     "#D9A441"
    readonly property color phDim:    "#8A8378"
    readonly property color err:      "#C62828"
    readonly property color lampOff:  "#2A2622"
    readonly property color edgeHi:   "#2A2724"
    readonly property color edgeLo:   "#080706"
    readonly property color panelTop: "#1C1A17"
    readonly property color panelBot: "#141312"
    readonly property color keyFace:  "#241F1B"
    readonly property color keyDown:  "#191714"
    readonly property color rule:     "#262320"
    readonly property string mono: "Iosevka Nerd Font"
    readonly property real s: Math.max(0.7, Math.min(2, Math.min(width / 1920, height / 1080)))
    readonly property real fontPx: 20 * s
    readonly property real lineH: Math.round(fontPx * 1.4)
    readonly property real panelW: 1120 * s

    // Portability: no Quickshell.env in the lock context, so home comes from
    // this file's own URL (five levels: slug, themes, qylock, share, .local).
    readonly property string homeDir: Qt.resolvedUrl("../../../../..").toString().replace(/\/$/, "")
    readonly property string homePath: homeDir.replace(/^file:\/\//, "")

    // ── identity ──────────────────────────────────────────────────────────
    readonly property string host: (typeof sddm !== "undefined" && sddm.hostName) ? String(sddm.hostName) : "ryoku"
    readonly property string user: (userHelper.currentItem && userHelper.currentItem.uLogin) ? userHelper.currentItem.uLogin : (typeof userModel !== "undefined" ? userModel.lastUser : "user")
    function esc(t) {
        return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    // CONSOLE column: labels on the dim tier, values on the cream tier. The
    // whole block is one StyledText so the column keeps a single line height.
    readonly property string consoleTrace:
        "<font color=\"#8A8378\">kernel</font>  <font color=\"#E8E2D6\">" + root.esc(root.kernel) + "</font>"
      + "<br/><font color=\"#8A8378\">uptime</font>  <font color=\"#E8E2D6\">" + root.esc(root.hostUptime) + "</font>"
      + "<br/><font color=\"#8A8378\">held</font>    <font color=\"#E8E2D6\">" + root.esc(root.lockedFor) + "</font>"
      + "<br/><font color=\"#8A8378\">load</font>    <font color=\"#E8E2D6\">" + root.esc(root.load1 + "  " + root.load5) + "</font>"
      + "<br/><font color=\"#8A8378\">mem</font>     <font color=\"#E8E2D6\">" + root.esc(root.memUsedPct + "% of " + root.memTotalG.toFixed(1) + "G") + "</font>"
      + "<br/><font color=\"#8A8378\">temp</font>    <font color=\"#E8E2D6\">" + root.esc(root.cpuTemp) + "</font>"
      + "<br/><font color=\"#8A8378\">pam</font>     <font color=\"#E8E2D6\">ryoku-lock-pw</font>"
    readonly property string sessionName: (typeof sessionModel !== "undefined" && sessionModel.count > 0 && root.sessionIndex >= 0 && root.sessionIndex < sessionModel.count) ? String(sessionModel.get(root.sessionIndex).name) : "session"

    // ── panel state ───────────────────────────────────────────────────────
    property int addrValue: 0
    property int dataReg: 0
    property bool verifying: false
    property bool denied: false
    // deny choreography: 0 idle, 1 sweep a single red lamp across DATA,
    // 2 all DATA lamps red, 3 blank frame. Driven by one SequentialAnimation.
    property int denyStep: 0
    property real denySweep: 15
    property string pwdText: ""
    property int attemptCount: 0
    property bool cursorOn: true
    property bool examOpen: false
    property bool lampFrozen: false
    property string powerArmed: ""
    property real intro: 1
    property real shaderTime: 0
    property date now: new Date()
    property string hostUptime: "?h ?m"
    property string load1: "--"
    property string load5: "--"
    property string cpuTemp: "--"
    property int memUsedPct: 0
    property string lockedFor: "--"
    property real lockStartUptime: -1
    property bool capsOn: false
    property bool numOn: false
    property string kernel: "linux"
    property real memTotalG: 0
    property var sessionNames: []

    // the side columns need real room beside the plate, so they fade out on
    // narrow screens instead of colliding with the rails
    readonly property bool showCols: ((root.width - root.panelW) / 2) >= (260 * root.s)

    // config values arrive from theme.conf as strings
    readonly property bool powerRow: typeof config !== "undefined" && String(config.powerRow) === "true"

    // ── helpers ───────────────────────────────────────────────────────────
    function bits(v, n) {
        var out = "";
        var x = Math.max(0, Math.floor(v));
        for (var i = n - 1; i >= 0; i--) out += ((x >> i) & 1) ? "1" : "0";
        return out;
    }
    function oct(v, w) {
        var o = Math.max(0, Math.floor(v)).toString(8);
        while (o.length < (w || 7)) o = "0" + o;
        return o;
    }
    readonly property string addrBits: root.bits(root.addrValue, 16)
    readonly property string dataBits: root.bits(root.dataReg, 16)
    readonly property string srBits: root.bits(((root.addrValue ^ (root.dataReg << 6)) & 0x3FFFFF), 22)
    function pushBit(code) { root.dataReg = ((root.dataReg << 1) | (code & 1)) & 0xFFFF }

    // ── live system reads (XHR on file://, no daemon) ──────────────────────
    function readUptime() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///proc/uptime", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var sec = Math.floor(parseFloat(xhr.responseText.split(" ")[0]));
                var d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600);
                var m = Math.floor((sec % 3600) / 60), ss = Math.floor(sec % 60);
                root.hostUptime = sec > 0 ? (d > 0 ? d + "d " : "") + h + "h " + m + "m " + ss + "s" : "?h ?m";
                if (root.lockStartUptime < 0) {
                    root.lockStartUptime = sec;
                    root.addrValue = sec & 0xFFFF;
                }
                var el = Math.max(0, Math.floor(sec - root.lockStartUptime));
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
                root.load1 = f[0] || "--";
                root.load5 = f[1] || "--";
            }
        } catch (e) { }
        xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///sys/class/thermal/thermal_zone0/temp", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var t = parseInt(xhr.responseText.trim());
                root.cpuTemp = isNaN(t) ? "--" : Math.round(t / 1000) + "C";
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
                    root.memUsedPct = Math.round((total - avail) / total * 100);
                    root.memTotalG = Math.round(total / 1048576 * 10) / 10;
                }
            }
        } catch (e) { }
    }
    function readKeyboard() {
        if (typeof keyboard !== "undefined") {
            root.capsOn = keyboard.capsLock;
            root.numOn = keyboard.numLock;
        }
    }
    // /proc/version line: "Linux version 7.3.0-4-cachyos (build@...) ..."; third
    // field is the kernel release. Read once at boot, it cannot change here.
    function readKernel() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file:///proc/version", false);
            xhr.send(null);
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                var f = xhr.responseText.trim().split(/\s+/);
                if (f.length > 2) root.kernel = String(f[2]);
            }
        } catch (e) { }
    }
    // the shim fills sessionModel asynchronously; a plain array of names keeps
    // the SYSTEM MAP delegate free of ListModel role quirks
    function syncSessions() {
        if (typeof sessionModel === "undefined") return;
        var out = [];
        for (var i = 0; i < sessionModel.count; i++) out.push(String(sessionModel.get(i).name));
        root.sessionNames = out;
    }

    // ── panel actions ─────────────────────────────────────────────────────
    function panelAction(act) {
        if (act === "session") {
            var n = (typeof sessionModel !== "undefined" && sessionModel.count > 0) ? sessionModel.count : 0;
            if (n > 1) {
                root.sessionPicked = true;
                root.sessionIndex = (root.sessionIndex + 1) % n;
            }
        } else if (act === "exam") {
            root.examOpen = !root.examOpen;
        } else if (act === "clear") {
            pwd.text = "";
            root.pwdText = "";
            root.dataReg = 0;
            denyAnim.stop(); root.denyStep = 0; root.denySweep = 15;
            pwd.forceActiveFocus();
        } else if (act === "login") {
            if (!root.verifying && root.pwdText.length > 0) doLogin();
        }
    }
    // power keys: first press arms for 3 s, second press executes. The whole
    // row is inert unless theme.conf carries powerRow=true.
    function powerKey(act) {
        if (!root.powerRow) return;
        if (root.powerArmed !== act) {
            root.powerArmed = act;
            powerTimer.restart();
            return;
        }
        root.powerArmed = "";
        if (typeof sddm !== "undefined") {
            if (act === "suspend") sddm.suspend();
            else if (act === "reboot") sddm.reboot();
            else if (act === "poweroff") sddm.powerOff();
        }
    }
    function doLogin() {
        var u = (userHelper.currentItem && userHelper.currentItem.uLogin) ? userHelper.currentItem.uLogin : (typeof userModel !== "undefined" ? userModel.lastUser : "");
        root.verifying = true;
        if (typeof sddm !== "undefined") sddm.login(u, pwd.text, root.sessionIndex);
    }

    // ── timers ────────────────────────────────────────────────────────────
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { root.now = new Date(); root.cursorOn = !root.cursorOn; } }
    Timer { interval: 2000; repeat: true; running: true; onTriggered: { if (!root.lampFrozen) { readUptime(); readSystem(); readKeyboard(); } } }
    Timer { interval: 100; repeat: true; running: true; onTriggered: root.shaderTime += 0.1 }
    Timer { id: powerTimer; interval: 3000; repeat: false; onTriggered: root.powerArmed = "" }

    // ── scene ─────────────────────────────────────────────────────────────
    Item {
        id: scr
        anchors.fill: parent
        layer.enabled: true
        layer.effect: ShaderEffect {
            // itemWidth/itemHeight come from the shader's uniform block; P7
            // fails if any uniform it declares is not bound here.
            property real itemWidth: width
            property real itemHeight: height
            property real strength: 0.55
            fragmentShader: Qt.resolvedUrl("shaders/lock_vignette.frag.qsb")
        }

        Rectangle { anchors.fill: parent; color: root.color }

        // ── cabinet: top and bottom rails, corner brackets, no side bands ──
        // The vertical rails were removed on request: a full height band on
        // each edge read as a block, not as part of the machine. What carries
        // the cabinet now is the two horizontal rails plus the corner brackets.
        Rectangle { x: 0; y: 0; width: parent.width; height: 46 * root.s; color: "#141210" }
        Rectangle { x: 0; y: 46 * root.s; width: parent.width; height: 1 * root.s; color: root.rule }
        Rectangle { x: 0; y: parent.height - 46 * root.s; width: parent.width; height: 46 * root.s; color: "#141210" }
        Rectangle { x: 0; y: parent.height - 47 * root.s; width: parent.width; height: 1 * root.s; color: root.rule }

        Repeater {
            model: [[12, 60, 0, 0], [0, 60, 12, 0], [12, 0, 0, 12], [0, 0, 12, 12]]
            Rectangle {
                required property var modelData
                width: 16 * root.s; height: 16 * root.s
                x: modelData[0] > 0 ? 12 * root.s : root.width - 28 * root.s
                y: modelData[1] > 0 ? 60 * root.s : root.height - 76 * root.s
                color: "transparent"; border.width: 1; border.color: "#35302A"
            }
        }

        // rail lettering
        Text {
            x: 26 * root.s; height: 46 * root.s; verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText; font.family: root.mono
            font.pixelSize: 11 * root.s; font.letterSpacing: 2.4 * root.s
            color: root.ph; text: "DIGITAL  ·  PDP-11/70  ·  PROGRAMMER'S CONSOLE"
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 26 * root.s
            height: 46 * root.s; verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText; font.family: root.mono
            font.pixelSize: 11 * root.s; font.letterSpacing: 2.4 * root.s
            color: root.phDim; text: "SN 11-70-RYOKU  ·  QYLOCK 1.0.0"
        }
        Row {
            x: 26 * root.s; y: parent.height - 46 * root.s; height: 46 * root.s
            spacing: 18 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText; font.family: root.mono
                font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
                color: root.phHi; text: "● POWER"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText; font.family: root.mono
                font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
                color: root.phDim; text: "RUN    PANEL LOCK"
            }
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 26 * root.s
            y: parent.height - 46 * root.s; height: 46 * root.s
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText; font.family: root.mono
            font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
            color: root.phDim; text: "LOCAL SESSION ONLY"
        }

        // ── left column: live console trace (/proc, no daemon) ────────────
        Item {
            id: consoleCol
            x: stack.x - 24 * root.s - width
            y: stack.y + panel.y + 4 * root.s
            width: 200 * root.s
            height: consoleBody.implicitHeight + 30 * root.s
            opacity: root.showCols ? 1 : 0

            Text {
                width: parent.width
                textFormat: Text.PlainText; font.family: root.mono
                font.pixelSize: 10.5 * root.s; font.letterSpacing: 2.2 * root.s
                color: root.ph; text: "CONSOLE"
            }
            Rectangle { y: 20 * root.s; width: parent.width; height: 1 * root.s; color: root.rule }
            Text {
                id: consoleBody
                y: 34 * root.s; width: parent.width
                textFormat: Text.StyledText; font.family: root.mono
                font.pixelSize: 10.5 * root.s; font.letterSpacing: 0.6 * root.s
                color: root.ph
                lineHeight: 1.75; lineHeightMode: Text.ProportionalHeight
                text: root.consoleTrace
            }
        }

        // ── right column: SYSTEM MAP, the real sessionModel ───────────────
        Item {
            id: mapCol
            x: stack.x + stack.width + 24 * root.s
            y: consoleCol.y
            width: 200 * root.s
            height: mapList.implicitHeight + 66 * root.s
            opacity: root.showCols ? 1 : 0

            Text {
                width: parent.width
                textFormat: Text.PlainText; font.family: root.mono
                font.pixelSize: 10.5 * root.s; font.letterSpacing: 2.2 * root.s
                color: root.ph; text: "SYSTEM MAP"
            }
            Rectangle { y: 20 * root.s; width: parent.width; height: 1 * root.s; color: root.rule }
            Column {
                id: mapList
                y: 34 * root.s; width: parent.width; spacing: 7 * root.s
                Repeater {
                    model: root.sessionNames
                    Text {
                        required property var modelData
                        required property int index
                        width: mapList.width
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText; font.family: root.mono
                        font.pixelSize: 10 * root.s; font.letterSpacing: 1.4 * root.s
                        color: index === root.sessionIndex ? root.phHi : root.phDim
                        text: (index === root.sessionIndex ? "▸ " : "") + String(modelData).toUpperCase()
                    }
                }
            }
            Row {
                anchors.right: parent.right
                y: mapList.y + mapList.implicitHeight + 12 * root.s
                spacing: 2 * root.s
                Repeater {
                    model: 16
                    Rectangle {
                        required property int index
                        width: 7 * root.s; height: 9 * root.s
                        color: index < Math.round(root.memUsedPct / 100 * 16) ? root.phHi : root.lampOff
                    }
                }
            }
            Text {
                width: parent.width
                y: mapList.y + mapList.implicitHeight + 30 * root.s
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText; font.family: root.mono
                font.pixelSize: 9 * root.s; font.letterSpacing: 1.6 * root.s
                color: "#6C675E"; text: "LOAD ADRS CYCLES THIS LIST"
            }
        }

        Column {
            id: stack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 26 * root.s

            // identity line
            Item {
                width: root.panelW; height: 18 * root.s
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 13 * root.s; font.letterSpacing: 1.8 * root.s
                    color: root.phDim
                    text: root.user.toUpperCase() + "@" + root.host.toUpperCase() + "  /  RYOKU SYSTEM LOCK"
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 13 * root.s; font.letterSpacing: 1.8 * root.s
                    color: root.phDim
                    text: "PANEL CONSOLE  ·  " + Qt.formatTime(root.now, "hh:mm:ss")
                }
            }

            // the front panel
            Rectangle {
                id: panel
                width: root.panelW
                height: plate.implicitHeight + 52 * root.s
                radius: 6 * root.s
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.panelTop }
                    GradientStop { position: 0.46; color: "#181613" }
                    GradientStop { position: 1.0; color: root.panelBot }
                }
                border.width: 1
                border.color: root.edgeHi
                opacity: 0.35 + 0.65 * root.intro

                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1 * root.s; color: root.edgeLo
                }
                Repeater {
                    model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                    Rectangle {
                        required property var modelData
                        width: 7 * root.s; height: 7 * root.s; radius: width / 2
                        color: "#1A1815"; border.width: 1; border.color: "#0C0B0A"
                        x: modelData[0] === 0 ? 8 * root.s : panel.width - width - 8 * root.s
                        y: modelData[1] === 0 ? 8 * root.s : panel.height - height - 8 * root.s
                    }
                }

                Column {
                    id: plate
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 26 * root.s
                    spacing: 20 * root.s

                    // nameplate, with the ENABLE/HALT lever and the LOCK knob
                    Item {
                        width: parent.width; height: 34 * root.s
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 15 * root.s; font.letterSpacing: 4.5 * root.s
                            font.weight: Font.Bold; color: root.ph; text: "DIGITAL"
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 138 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 11 * root.s; font.letterSpacing: 2.8 * root.s
                            color: root.phDim; text: "PDP-11  FRONT PANEL"
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 18 * root.s
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText; font.family: root.mono
                                font.pixelSize: 10 * root.s; font.letterSpacing: 1.8 * root.s
                                color: "#6C675E"; text: "SN 11-70-RYOKU  ·  QYLOCK"
                            }
                            Item {
                                width: 40 * root.s; height: 34 * root.s
                                Rectangle {
                                    id: lever
                                    anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                    width: 34 * root.s; height: 16 * root.s; radius: 8 * root.s
                                    color: "#0C0B0A"; border.width: 1; border.color: "#2C2825"
                                    Rectangle {
                                        width: 13 * root.s; height: 12 * root.s; radius: 6 * root.s
                                        y: 2 * root.s
                                        x: (lever.width - width - 2 * root.s) * root.intro
                                        color: "#D8D2C4"
                                    }
                                    MouseArea {
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.lampFrozen = !root.lampFrozen
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    textFormat: Text.PlainText; font.family: root.mono
                                    font.pixelSize: 8 * root.s; font.letterSpacing: 1.4 * root.s
                                    color: root.lampFrozen ? root.phHi : root.phDim
                                    text: root.lampFrozen ? "HALT" : "ENABLE"
                                }
                            }
                            Item {
                                width: 34 * root.s; height: 34 * root.s
                                Rectangle {
                                    anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                    width: 28 * root.s; height: 28 * root.s; radius: 14 * root.s
                                    color: "#221F1B"; border.width: 1; border.color: "#0B0A09"
                                    Rectangle {
                                        width: 2 * root.s; height: 9 * root.s
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 3 * root.s; color: root.err
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    textFormat: Text.PlainText; font.family: root.mono
                                    font.pixelSize: 8 * root.s; font.letterSpacing: 1.4 * root.s
                                    color: root.phDim; text: "LOCK"
                                }
                            }
                        }
                    }

                    // ADDRESS row
                    Item {
                        width: parent.width; height: 18 * root.s
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 96 * root.s
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
                            color: root.phDim; text: "ADDRESS"
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 96 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * root.s
                            Repeater {
                                model: 16
                                Item {
                                    required property int index
                                    width: 20 * root.s; height: 13 * root.s
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 4 * root.s; height: parent.height + 4 * root.s
                                        radius: 2 * root.s; z: -1
                                        color: root.denyStep === 2 ? root.err : root.phHi
                                        opacity: (root.addrBits.charAt(index) === "1") ? 0.16 : 0
                                    }
                                    Rectangle {
                                        anchors.fill: parent; radius: 1 * root.s
                                        color: root.addrBits.charAt(index) === "1"
                                             ? (root.denyStep === 2 ? root.err : root.phHi) : root.lampOff
                                        Behavior on color { ColorAnimation { duration: 60 } }
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 13 * root.s; font.letterSpacing: 1.2 * root.s
                            color: root.denyStep === 2 ? root.err : root.ph
                            text: root.oct(root.addrValue, 7)
                        }
                    }

                    // DATA row
                    Item {
                        width: parent.width; height: 18 * root.s
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 96 * root.s
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
                            color: root.phDim; text: "DATA"
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 96 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * root.s
                            Repeater {
                                model: 16
                                Item {
                                    required property int index
                                    width: 20 * root.s; height: 13 * root.s
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 4 * root.s; height: parent.height + 4 * root.s
                                        radius: 2 * root.s; z: -1
                                        color: root.denyStep > 0 ? root.err : root.phHi
                                        opacity: root.denyStep === 1
                                                 ? (Math.abs(index - root.denySweep) < 0.6 ? 0.22 : 0)
                                                 : root.denyStep === 2
                                                   ? 0.22
                                                   : (root.dataBits.charAt(index) === "1") ? 0.16 : 0
                                    }
                                    Rectangle {
                                        anchors.fill: parent; radius: 1 * root.s
                                        color: root.denyStep === 1
                                               ? (Math.abs(index - root.denySweep) < 0.6 ? root.err : root.lampOff)
                                               : root.denyStep === 2 ? root.err
                                               : root.denyStep === 3 ? root.lampOff
                                               : (root.dataBits.charAt(index) === "1" ? root.phHi : root.lampOff)
                                        Behavior on color { ColorAnimation { duration: 60 } }
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 13 * root.s; font.letterSpacing: 1.2 * root.s
                            color: root.denyStep > 0 ? root.err : root.ph
                            text: root.oct(root.dataReg, 7)
                        }
                    }

                    // switch register, 22 paddles
                    Item {
                        width: parent.width; height: 20 * root.s
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 96 * root.s
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 10 * root.s; font.letterSpacing: 2.2 * root.s
                            color: root.phDim; text: "SR 21..0"
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 96 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5 * root.s
                            Repeater {
                                model: 22
                                Rectangle {
                                    required property int index
                                    width: 7 * root.s; height: 16 * root.s; radius: 1 * root.s
                                    border.width: 1; border.color: "#0A0908"
                                    opacity: 0.92
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: root.srBits.charAt(index) === "1" ? "#8E887C" : "#D8D2C4"
                                        }
                                        GradientStop {
                                            position: 0.52
                                            color: root.srBits.charAt(index) === "1" ? "#D8D2C4" : "#8E887C"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // console keys, then the divider and the power keys
                    Row {
                        id: controls
                        width: parent.width; height: 34 * root.s
                        spacing: 10 * root.s
                        Repeater {
                            model: [
                                { label: "LOAD ADRS", act: "session" },
                                { label: "EXAM",      act: "exam" },
                                { label: "DEP",       act: "noop" },
                                { label: "CONT",      act: "clear" },
                                { label: "START",     act: "login" }
                            ]
                            Rectangle {
                                id: pad
                                required property var modelData
                                readonly property bool down: (pad.modelData.act === "login" && root.verifying)
                                                              || (pad.modelData.act === "exam" && root.examOpen)
                                width: 104 * root.s; height: 34 * root.s; radius: 2 * root.s
                                color: pad.down ? root.keyDown : root.keyFace
                                border.width: 1
                                border.color: pad.down ? "#141210" : "#3A352E"
                                opacity: 0.35 + 0.65 * root.intro
                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText; font.family: root.mono
                                    font.pixelSize: 9.5 * root.s; font.letterSpacing: 1.3 * root.s
                                    color: pad.modelData.act === "noop" ? "#6C675E"
                                           : (pad.down ? root.phHi : root.ph)
                                    text: pad.modelData.label
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.panelAction(pad.modelData.act)
                                }
                            }
                        }
                        Rectangle { width: 1 * root.s; height: 26 * root.s; color: root.rule }
                        Repeater {
                            model: [
                                { label: "SLEEP",    act: "suspend"  },
                                { label: "REBOOT",   act: "reboot"   },
                                { label: "SHUTDOWN", act: "poweroff" }
                            ]
                            Rectangle {
                                id: pwr
                                required property var modelData
                                readonly property bool armed: root.powerArmed === pwr.modelData.act
                                width: 104 * root.s; height: 34 * root.s; radius: 2 * root.s
                                color: pwr.armed ? "#2A1010" : root.keyFace
                                border.width: 1
                                border.color: pwr.armed ? root.err : "#3A352E"
                                opacity: 0.35 + 0.65 * root.intro
                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText; font.family: root.mono
                                    font.pixelSize: 9.5 * root.s; font.letterSpacing: 1.3 * root.s
                                    color: pwr.armed ? root.err : root.phDim
                                    text: pwr.modelData.label
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.powerKey(pwr.modelData.act)
                                }
                            }
                        }
                    }

                    // plate footer
                    Item {
                        width: parent.width; height: 14 * root.s
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 8.5 * root.s; font.letterSpacing: 1.6 * root.s
                            color: "#5B564E"
                            text: "DEP: no-op  ·  POWER KEYS: PRESS TWICE TO ARM"
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText; font.family: root.mono
                            font.pixelSize: 8.5 * root.s; font.letterSpacing: 1.6 * root.s
                            color: "#5B564E"; text: "RYOKU / QYLOCK  ·  IOSEVKA"
                        }
                    }
                }
            }

            // prompt line: the caret is anchored to the text it follows, so the
            // glyph pitch (10.5 px at 21 px plus 5 px letter spacing) never has
            // to be guessed. The old fixed 12 px step drifted under the dots.
            Item {
                width: root.panelW; height: 30 * root.s
                Text {
                    id: promptLabel
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 21 * root.s; font.letterSpacing: 0.8 * root.s
                    color: root.phHi; text: "PASSWORD>"
                }
                Text {
                    id: dotText
                    anchors.left: promptLabel.right; anchors.leftMargin: 20 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 21 * root.s; font.letterSpacing: 5 * root.s
                    color: root.denied ? root.err : root.ph
                    text: "*".repeat(Math.min(root.pwdText.length, 32))
                }
                Text {
                    anchors.left: dotText.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 21 * root.s
                    color: root.denied ? root.err : root.ph
                    opacity: root.cursorOn ? 1 : 0
                    text: "█"
                }
                Text {
                    anchors.right: parent.right; anchors.baseline: parent.bottom
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 9 * root.s; font.letterSpacing: 2 * root.s
                    color: "#6C675E"
                    text: root.pwdText.length > 0 ? root.pwdText.length + " CHARS" : ""
                }
            }

            // state line
            Item {
                width: root.panelW; height: 20 * root.s
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 10 * root.s; font.letterSpacing: 2 * root.s
                    color: root.denied ? root.phHi : root.phDim
                    text: root.denied
                          ? "LOGIN FAILED  -  RETRY   [attempt " + root.attemptCount + "]"
                          : root.verifying
                            ? "AUTHENTICATING  ·  START LATCHED"
                            : root.examOpen
                              ? "EXAM: HOST " + root.host + "  UPTIME " + root.hostUptime
                                + "  LOAD " + root.load1 + "  TEMP " + root.cpuTemp
                                + "  MEM " + root.memUsedPct + "%"
                              : "READY  ·  ENTER START  ·  CONT CLEARS  ·  LOAD ADRS SESSION"
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText; font.family: root.mono
                    font.pixelSize: 10 * root.s; font.letterSpacing: 2 * root.s
                    color: "#6C675E"
                    text: "CAPS " + (root.capsOn ? "ON" : "OFF")
                          + "  ·  NUM " + (root.numOn ? "ON" : "OFF")
                          + "  ·  " + root.sessionName.toUpperCase()
                          + "  ·  LOCKED " + root.lockedFor
                }
            }
        }
    }

    // ── password input (hidden, captures keys) ────────────────────────────
    TextInput {
        id: pwd
        anchors.fill: parent
        visible: false
        focus: true
        echoMode: TextInput.Password
        onTextChanged: {
            root.pwdText = text;
            if (text.length > 0 && root.denied) root.denied = false;
            if (text.length > 0 && root.denyStep !== 0) { denyAnim.stop(); root.denyStep = 0; root.denySweep = 15; }
            if (text.length > 0) root.pushBit(text.charCodeAt(text.length - 1));
        }
        Keys.onReturnPressed: if (!root.verifying) doLogin()
        Keys.onEnterPressed: if (!root.verifying) doLogin()
        Keys.onEscapePressed: {
            text = ""; root.pwdText = ""; root.dataReg = 0;
            denyAnim.stop(); root.denyStep = 0; root.denySweep = 15;
        }
    }

    // Auto-focus fix: the Loader does not propagate focus: true in time, so
    // force ActiveFocus after the surface settles.
    Timer { id: focusFix; interval: 300; running: true; onTriggered: pwd.forceActiveFocus() }

    // the shim enumerates sessions asynchronously, so lastIndex is 0 at build
    // time; adopt it as soon as the model fills, but never override the plate
    Connections {
        target: typeof sessionModel !== "undefined" ? sessionModel : null
        ignoreUnknownSignals: true
        function syncFromSessionModel() {
            if (root.sessionPicked || typeof sessionModel === "undefined") return;
            root.syncSessions();
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
            root.dataReg = 0;
            if (!root.verifying) denyAnim.restart();
            pwd.text = "";
            root.pwdText = "";
            pwd.focus = true;
        }
        function onLoginSucceeded() {
            root.verifying = false;
            root.dataReg = 0;
        }
    }

    // ── boot choreography ─────────────────────────────────────────────────
    Component.onCompleted: {
        pwd.forceActiveFocus();
        if (typeof keyboard !== "undefined") keyboard.numLock = true;
        readUptime();
        readSystem();
        readKeyboard();
        readKernel();
        syncSessions();
        powerOn.start();
    }

    // wrong password: the machine faults instead of turning red at once.
    // 560 ms sweep, then two red frames with a blank between, then release.
    SequentialAnimation {
        id: denyAnim
        ScriptAction { script: { root.denyStep = 1; root.denySweep = 15; } }
        NumberAnimation { target: root; property: "denySweep"; from: 15; to: 0; duration: 560; easing.type: Easing.Linear }
        PauseAnimation { duration: 40 }
        ScriptAction { script: root.denyStep = 2 }
        PauseAnimation { duration: 120 }
        ScriptAction { script: root.denyStep = 3 }
        PauseAnimation { duration: 90 }
        ScriptAction { script: root.denyStep = 2 }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { root.denyStep = 0; root.denySweep = 15; } }
    }

    SequentialAnimation {
        id: powerOn
        PropertyAction { target: root; property: "intro"; value: 0 }
        NumberAnimation { target: root; property: "intro"; to: 1; duration: 420; easing.type: Easing.OutCubic }
    }
}
