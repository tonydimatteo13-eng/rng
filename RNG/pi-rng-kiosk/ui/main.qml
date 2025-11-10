import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import QtMultimedia 6.5

Window {
    id: root
    visible: true
    color: detectorState === "event" ? theme.eventBackground : theme.calmBackground
    title: "pi-rng-kiosk"
    visibility: Window.FullScreen

    property real gdiValue: 0
    property string detectorState: "calm"
    property var sparklineData: []
    property var testsData: []
    property var eventsData: []
    property var histogramData: [
        {"label": "0", "value": 0},
        {"label": "1", "value": 0}
    ]
    property var serialMatrixData: [
        {"label": "00", "value": 0},
        {"label": "01", "value": 0},
        {"label": "10", "value": 0},
        {"label": "11", "value": 0}
    ]
    property string exportMessage: ""
    property bool exportSuccess: true
    property var viewTitles: ["Overview", "Events", "Distributions", "Timeline", "Settings"]
    property string currentViewTitle: viewTitles[0]
    property int pendingIndex: -1
    property bool alarmSilenced: false
    property var settingsSource: initialSettings ? initialSettings : ({
        "windows": [1024, 10000, 100000],
        "alert": {
            "gdi_z": 3.0,
            "sustained_z": 2.5,
            "sustained_ticks": 5,
            "fdr_q": 0.01
        }
    })
    property string settingsWindowsText: settingsSource.windows.join(", ")
    property string settingsGdiText: settingsSource.alert.gdi_z
    property string settingsSustainedText: settingsSource.alert.sustained_z
    property string settingsTicksText: settingsSource.alert.sustained_ticks
    property string settingsFdrText: settingsSource.alert.fdr_q
    property string settingsError: ""

    Themes {
        id: theme
    }

    Timer {
        id: pulseTimer
        running: detectorState === "event"
        repeat: true
        interval: 800
    }

    Audio {
        id: alertAudio
        source: Qt.resolvedUrl("assets/alert_tone.wav")
        loops: Audio.Infinite
        volume: 0.6
    }

    Timer {
        id: sparklineTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            sparklineCanvas.requestPaint()
            if (timelineCanvas) timelineCanvas.requestPaint()
        }
    }

    Timer {
        id: exportMessageTimer
        interval: 5000
        repeat: false
        onTriggered: root.exportMessage = ""
    }

    Connections {
        target: viewModel
        function onGdiChanged(value) { root.gdiValue = value }
        function onStateChanged(value) {
            root.detectorState = value
            if (value === "event" && alertAudio.status === Audio.Ready && !root.alarmSilenced) {
                alertAudio.play()
            } else if (value !== "event" || root.alarmSilenced) {
                alertAudio.stop()
            }
        }
        function onSparklineChanged(value) {
            root.sparklineData = value
            sparklineCanvas.requestPaint()
            if (timelineCanvas) timelineCanvas.requestPaint()
        }
        function onTestsChanged(value) { root.testsData = value }
        function onEventsChanged(value) { root.eventsData = value }
        function onExportCompleted(success, message) {
            root.exportSuccess = success
            root.exportMessage = message
            exportMessageTimer.restart()
        }
        function onHistogramChanged(value) { root.histogramData = value }
        function onSerialMatrixChanged(value) { root.serialMatrixData = value }
        function onSettingsApplied(payload) {
            if (payload.windows && payload.windows.length) {
                root.settingsWindowsText = payload.windows.join(", ")
            }
            if (payload.alert) {
                if (payload.alert.gdi_z !== undefined) root.settingsGdiText = payload.alert.gdi_z
                if (payload.alert.sustained_z !== undefined) root.settingsSustainedText = payload.alert.sustained_z
                if (payload.alert.sustained_ticks !== undefined) root.settingsTicksText = payload.alert.sustained_ticks
                if (payload.alert.fdr_q !== undefined) root.settingsFdrText = payload.alert.fdr_q
            }
        }
    }

    Button {
        id: exportButton
        text: "Export Logs"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 24
        padding: 12
        background: Rectangle {
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.5)
            border.color: Qt.rgba(1, 1, 1, 0.2)
            border.width: 1
        }
        contentItem: Text {
            text: exportButton.text
            color: theme.calmText
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: viewModel.exportToUsb()
    }

    Text {
        id: exportStatus
        anchors.top: exportButton.bottom
        anchors.left: exportButton.left
        anchors.topMargin: 8
        text: root.exportMessage
        color: root.exportSuccess ? theme.calmText : theme.warning
        font.pixelSize: 14
        visible: root.exportMessage.length > 0
    }

    Button {
        id: settingsButton
        text: "Settings"
        anchors.top: parent.top
        anchors.right: exitButton.left
        anchors.margins: 24
        padding: 12
        background: Rectangle {
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.5)
            border.color: Qt.rgba(1, 1, 1, 0.2)
            border.width: 1
        }
        contentItem: Text {
            text: settingsButton.text
            color: theme.calmText
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: {
            root.settingsError = ""
            settingsDialog.open()
        }
    }

    Button {
        id: exitButton
        text: "Exit"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        padding: 12
        background: Rectangle {
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.5)
            border.color: Qt.rgba(1, 1, 1, 0.2)
            border.width: 1
        }
        contentItem: Text {
            text: exitButton.text
            color: theme.calmText
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: exitDialog.open()
    }

    Dialog {
        id: exitDialog
        modal: true
        width: 420
        background: Rectangle {
            color: Qt.rgba(4/255, 11/255, 22/255, 0.95)
            radius: 20
            border.color: Qt.rgba(255, 255, 255, 0.08)
            border.width: 1
        }
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20
            Label {
                text: "Exit kiosk?"
                color: theme.calmText
                font.pixelSize: 28
                font.bold: true
            }
            Label {
                text: "This will stop data collection and close the display."
                wrapMode: Text.Wrap
                color: Qt.rgba(1, 1, 1, 0.8)
                font.pixelSize: 18
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 18
                        color: Qt.rgba(0, 0, 0, 0.4)
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                    }
                    onClicked: exitDialog.close()
                }
                Button {
                    text: "Exit"
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 18
                        color: theme.eventAccent
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#0b0f1c"
                        font.pixelSize: 18
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: Qt.quit()
                }
            }
        }
    }

    Dialog {
        id: settingsDialog
        modal: true
        width: 520
        background: Rectangle {
            color: Qt.rgba(4/255, 11/255, 22/255, 0.95)
            radius: 24
            border.color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 1
        }
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18
            Label {
                text: "Live Settings"
                color: theme.calmText
                font.pixelSize: 28
                font.bold: true
            }
            Text { text: "Window sizes (bits)"; color: theme.calmText; font.pixelSize: 18 }
            TextField {
                id: dialogWindowsField
                text: root.settingsWindowsText
                placeholderText: "1024, 10000, 100000"
                font.pixelSize: 18
                onTextChanged: root.settingsWindowsText = text
            }
            Text { text: "GDI threshold"; color: theme.calmText; font.pixelSize: 18 }
            TextField {
                id: dialogGdiField
                text: root.settingsGdiText
                font.pixelSize: 18
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onTextChanged: root.settingsGdiText = text
            }
            Text { text: "Sustained threshold"; color: theme.calmText; font.pixelSize: 18 }
            TextField {
                id: dialogSustainedField
                text: root.settingsSustainedText
                font.pixelSize: 18
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onTextChanged: root.settingsSustainedText = text
            }
            Text { text: "Sustained ticks"; color: theme.calmText; font.pixelSize: 18 }
            TextField {
                id: dialogTicksField
                text: root.settingsTicksText
                font.pixelSize: 18
                inputMethodHints: Qt.ImhDigitsOnly
                onTextChanged: root.settingsTicksText = text
            }
            Text { text: "FDR q"; color: theme.calmText; font.pixelSize: 18 }
            TextField {
                id: dialogFdrField
                text: root.settingsFdrText
                font.pixelSize: 18
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onTextChanged: root.settingsFdrText = text
            }
            Text {
                text: root.settingsError
                color: theme.warning
                visible: root.settingsError.length > 0
                font.pixelSize: 16
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    onClicked: settingsDialog.close()
                }
                Button {
                    text: "Apply"
                    Layout.fillWidth: true
                    onClicked: root.submitSettings(false, dialogWindowsField.text, dialogGdiField.text, dialogSustainedField.text, dialogTicksField.text, dialogFdrField.text, true)
                }
                Button {
                    text: "Apply & Save"
                    Layout.fillWidth: true
                    onClicked: root.submitSettings(true, dialogWindowsField.text, dialogGdiField.text, dialogSustainedField.text, dialogTicksField.text, dialogFdrField.text, true)
                }
            }
        }
    }

    Text {
        id: viewTitle
        text: root.currentViewTitle
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 24
        color: theme.calmText
        font.pixelSize: 22
        font.bold: true
    }

    SequentialAnimation {
        id: viewFade
        PropertyAnimation { target: stack; property: "opacity"; to: 0; duration: 150 }
        ScriptAction {
            script: {
                if (root.pendingIndex >= 0) {
                    stack.currentIndex = root.pendingIndex
                    var idx = Math.min(root.pendingIndex, root.viewTitles.length - 1)
                    root.currentViewTitle = root.viewTitles[idx]
                }
            }
        }
        PropertyAnimation { target: stack; property: "opacity"; to: 1; duration: 150 }
        onFinished: root.pendingIndex = -1
    }

    function scheduleViewChange(index) {
        if (index === stack.currentIndex || index < 0 || index >= stack.count) {
            return
        }
        root.pendingIndex = index
        viewFade.restart()
    }

    function parseWindowString(text) {
        var parts = text.split(/[,\s]+/)
        var result = []
        for (var i = 0; i < parts.length; i++) {
            var value = parseInt(parts[i])
            if (!isNaN(value) && value > 0) {
                result.push(value)
            }
        }
        return result
    }

    function submitSettings(persist, windowsText, gdiText, sustainedText, ticksText, fdrText, closeDialog) {
        var windows = parseWindowString(windowsText)
        if (windows.length === 0) {
            root.settingsError = "Enter at least one window size"
            return
        }
        var gdi = parseFloat(gdiText)
        var sustained = parseFloat(sustainedText)
        var ticks = parseInt(ticksText)
        var fdr = parseFloat(fdrText)
        if (isNaN(gdi) || isNaN(sustained) || isNaN(ticks) || isNaN(fdr)) {
            root.settingsError = "Enter valid numeric thresholds"
            return
        }
        var payload = {
            windows: windows,
            alert: {
                gdi_z: gdi,
                sustained_z: sustained,
                sustained_ticks: ticks,
                fdr_q: fdr
            },
            persist: persist
        }
        root.settingsError = ""
        viewModel.applySettings(payload)
        if (closeDialog) settingsDialog.close()
    }

    Component.onCompleted: root.currentViewTitle = root.viewTitles[stack.currentIndex]

    Connections {
        target: stack
        function onCurrentIndexChanged() {
            root.currentViewTitle = root.viewTitles[Math.min(stack.currentIndex, root.viewTitles.length - 1)]
        }
    }

    onAlarmSilencedChanged: {
        if (alarmSilenced) {
            alertAudio.stop()
        } else if (detectorState === "event" && alertAudio.status === Audio.Ready) {
            alertAudio.play()
        }
    }

    StackLayout {
        id: stack
        anchors.fill: parent
        opacity: 1

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 24

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 360
                    spacing: 32

                    Loader {
                        id: gaugeLoader
                        Layout.preferredWidth: 360
                        Layout.preferredHeight: 360
                        source: "gauges.qml"
                        onLoaded: {
                            item.value = root.gdiValue
                            item.accent = root.detectorState === "event" ? theme.eventAccent : theme.calmAccent
                        }
                        Connections {
                            target: root
                            function onGdiValueChanged() {
                                if (gaugeLoader.item) gaugeLoader.item.value = root.gdiValue
                            }
                            function onDetectorStateChanged() {
                                if (gaugeLoader.item) gaugeLoader.item.accent = root.detectorState === "event" ? theme.eventAccent : theme.calmAccent
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Qt.rgba(1, 1, 1, 0.03)
                        radius: 12

                        Canvas {
                            id: sparklineCanvas
                            anchors.fill: parent
                            anchors.margins: 16
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.strokeStyle = theme.calmAccent
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                if (root.sparklineData.length > 1) {
                                    var max = -999
                                    var min = 999
                                    for (var i = 0; i < root.sparklineData.length; i++) {
                                        var val = root.sparklineData[i].gdi
                                        max = Math.max(max, val)
                                        min = Math.min(min, val)
                                    }
                                    var range = Math.max(1, max - min)
                                    for (var j = 0; j < root.sparklineData.length; j++) {
                                        var point = root.sparklineData[j]
                                        var normX = j / (root.sparklineData.length - 1)
                                        var normY = (point.gdi - min) / range
                                        var px = normX * width
                                        var py = height - normY * height
                                        if (j === 0) ctx.moveTo(px, py)
                                        else ctx.lineTo(px, py)
                                    }
                                }
                                ctx.stroke()
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16
                    Repeater {
                        model: root.testsData
                        delegate: Rectangle {
                            width: 140
                            height: 100
                            radius: 10
                            color: modelData.q <= 0.01 ? theme.eventAccent : Qt.rgba(1, 1, 1, 0.04)
                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4
                                Label {
                                    text: modelData.name + "@" + modelData.window
                                    color: theme.calmText
                                    font.pixelSize: 14
                                }
                                Label {
                                    text: "z " + modelData.z.toFixed(2)
                                    color: modelData.z >= 0 ? theme.positive : theme.negative
                                    font.pixelSize: 18
                                }
                                Label {
                                    text: "q " + modelData.q.toFixed(3)
                                    color: theme.warning
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anchors.margins: 32
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                Label {
                    text: "Events"
                    color: theme.calmText
                    font.pixelSize: 24
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.eventsData
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 64
                        radius: 8
                        color: modelData.state === "event" ? Qt.rgba(1, 0, 0, 0.15) : Qt.rgba(1, 1, 1, 0.03)
                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 24
                            Label {
                                text: Qt.formatDateTime(new Date(modelData.t), "hh:mm:ss")
                                color: theme.calmText
                                font.pixelSize: 18
                            }
                            Label {
                                text: "GDI " + modelData.gdi.toFixed(2)
                                color: theme.calmAccent
                                font.pixelSize: 18
                            }
                            Label {
                                text: modelData.reason
                                color: theme.warning
                                font.pixelSize: 16
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anchors.margins: 32
            ColumnLayout {
                anchors.fill: parent
                spacing: 24
                Label {
                    text: "Bit Distributions"
                    color: theme.calmText
                    font.pixelSize: 24
                }
                Rectangle {
                    id: histogramCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Row {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 32
                        Repeater {
                            model: root.histogramData
                            delegate: Column {
                                width: (histogramCard.width - 48) / Math.max(1, root.histogramData.length)
                                anchors.bottom: parent.bottom
                                spacing: 8
                                Rectangle {
                                    width: parent.width * 0.6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: {
                                        var maxVal = 1
                                        for (var i = 0; i < root.histogramData.length; i++) {
                                            maxVal = Math.max(maxVal, root.histogramData[i].value)
                                        }
                                        if (maxVal === 0) {
                                            return 0
                                        }
                                        return (modelData.value / maxVal) * (histogramCard.height - 100)
                                    }
                                    radius: 6
                                    color: theme.calmAccent
                                }
                                Text {
                                    text: modelData.value
                                    color: theme.calmText
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: modelData.label
                                    color: theme.calmText
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
                Label {
                    text: "Serial Matrix"
                    color: theme.calmText
                    font.pixelSize: 22
                }
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 220
                    rowSpacing: 12
                    columnSpacing: 12
                    Repeater {
                        model: root.serialMatrixData
                        delegate: Rectangle {
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.03)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            implicitHeight: 100
                            implicitWidth: (parent.width - 12) / 2
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: modelData.label
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: theme.calmText
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    text: modelData.value
                                    font.pixelSize: 16
                                    color: theme.calmAccent
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anchors.margins: 32
            ColumnLayout {
                anchors.fill: parent
                spacing: 24
                Label {
                    text: "Timeline & Source Mixer"
                    color: theme.calmText
                    font.pixelSize: 24
                }
                Rectangle {
                    id: timelineCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Canvas {
                        id: timelineCanvas
                        anchors.fill: parent
                        anchors.margins: 16
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = theme.eventAccent
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            if (root.sparklineData.length > 1) {
                                var max = -999
                                var min = 999
                                for (var i = 0; i < root.sparklineData.length; i++) {
                                    var val = root.sparklineData[i].gdi
                                    max = Math.max(max, val)
                                    min = Math.min(min, val)
                                }
                                var range = Math.max(1, max - min)
                                for (var j = 0; j < root.sparklineData.length; j++) {
                                    var point = root.sparklineData[j]
                                    var normX = j / (root.sparklineData.length - 1)
                                    var normY = (point.gdi - min) / range
                                    var px = normX * width
                                    var py = height - normY * height
                                    if (j === 0) ctx.moveTo(px, py)
                                    else ctx.lineTo(px, py)
                                }
                            }
                            ctx.stroke()
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 24
                    GroupBox {
                        title: "Source Mixer"
                        Layout.fillWidth: true
                        RowLayout {
                            anchors.fill: parent
                            spacing: 16
                            Switch {
                                id: hwSwitch
                                text: "Hardware RNG"
                                checked: true
                            }
                            Switch {
                                id: fallbackSwitch
                                text: "Fallback RNG"
                                checked: true
                            }
                        }
                    }
                    Button {
                        id: silenceButton
                        text: root.alarmSilenced ? "Alarm Silenced" : "Silence Alarm"
                        checkable: true
                        checked: root.alarmSilenced
                        onToggled: root.alarmSilenced = checked
                        Layout.preferredWidth: 180
                        background: Rectangle {
                            radius: 16
                            color: silenceButton.checked ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.4)
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                            border.width: 1
                        }
                        contentItem: Text {
                            text: silenceButton.text
                            color: theme.calmText
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            anchors.margins: 32
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                Label {
                    text: "Settings"
                    color: theme.calmText
                    font.pixelSize: 24
                }
                Text {
                    text: "Window sizes (bits)"
                    color: theme.calmText
                    font.pixelSize: 20
                }
                TextField {
                    id: inlineWindowsField
                    text: root.settingsWindowsText
                    placeholderText: "1024, 10000, 100000"
                    onTextChanged: root.settingsWindowsText = text
                    font.pixelSize: 20
                }
                Text { text: "GDI threshold"; color: theme.calmText; font.pixelSize: 20 }
                TextField {
                    id: inlineGdiField
                    text: root.settingsGdiText
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextChanged: root.settingsGdiText = text
                    font.pixelSize: 20
                }
                Text { text: "Sustained threshold"; color: theme.calmText; font.pixelSize: 20 }
                TextField {
                    id: inlineSustainedField
                    text: root.settingsSustainedText
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextChanged: root.settingsSustainedText = text
                    font.pixelSize: 20
                }
                Text { text: "Sustained ticks"; color: theme.calmText; font.pixelSize: 20 }
                TextField {
                    id: inlineTicksField
                    text: root.settingsTicksText
                    inputMethodHints: Qt.ImhDigitsOnly
                    onTextChanged: root.settingsTicksText = text
                    font.pixelSize: 20
                }
                Text { text: "FDR q"; color: theme.calmText; font.pixelSize: 20 }
                TextField {
                    id: inlineFdrField
                    text: root.settingsFdrText
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextChanged: root.settingsFdrText = text
                    font.pixelSize: 20
                }
                Text {
                    text: root.settingsError
                    color: theme.warning
                    visible: root.settingsError.length > 0
                    font.pixelSize: 18
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Button {
                        text: "Apply"
                        Layout.fillWidth: true
                        onClicked: root.submitSettings(false, inlineWindowsField.text, inlineGdiField.text, inlineSustainedField.text, inlineTicksField.text, inlineFdrField.text, false)
                        font.pixelSize: 18
                    }
                    Button {
                        text: "Apply & Save"
                        Layout.fillWidth: true
                        onClicked: root.submitSettings(true, inlineWindowsField.text, inlineGdiField.text, inlineSustainedField.text, inlineTicksField.text, inlineFdrField.text, false)
                        font.pixelSize: 18
                    }
                }
            }
        }
    }

    Row {
        id: navigationControls
        spacing: 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24

        Button {
            id: prevButton
            implicitWidth: 72
            implicitHeight: 72
            background: Rectangle {
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.2)
                border.width: 1
            }
            contentItem: Text {
                text: "‹"
                font.pixelSize: 28
                color: theme.calmText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: {
                var idx = (stack.currentIndex - 1 + stack.count) % stack.count
                root.scheduleViewChange(idx)
            }
        }

        Button {
            id: homeButton
            text: "Home"
            implicitHeight: 72
            implicitWidth: 120
            background: Rectangle {
                radius: 36
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.2)
                border.width: 1
            }
            contentItem: Text {
                text: homeButton.text
                font.pixelSize: 18
                color: theme.calmText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: root.scheduleViewChange(0)
        }

        Button {
            id: nextButton
            implicitWidth: 72
            implicitHeight: 72
            background: Rectangle {
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.2)
                border.width: 1
            }
            contentItem: Text {
                text: "›"
                font.pixelSize: 28
                color: theme.calmText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: {
                var idx = (stack.currentIndex + 1) % stack.count
                root.scheduleViewChange(idx)
            }
        }
    }
}
