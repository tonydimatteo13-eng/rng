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
        onTriggered: sparklineCanvas.requestPaint()
    }

    Connections {
        target: viewModel
        function onGdiChanged(value) { root.gdiValue = value }
        function onStateChanged(value) {
            root.detectorState = value
            if (value === "event" && alertAudio.status === Audio.Ready) {
                alertAudio.play()
            } else if (value !== "event") {
                alertAudio.stop()
            }
        }
        function onSparklineChanged(value) { root.sparklineData = value; sparklineCanvas.requestPaint() }
        function onTestsChanged(value) { root.testsData = value }
        function onEventsChanged(value) { root.eventsData = value }
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
        title: "Exit kiosk?"
        standardButtons: DialogButtonBox.Ok | DialogButtonBox.Cancel
        onAccepted: Qt.quit()
    }

    StackLayout {
        id: stack
        anchors.fill: parent

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
            onClicked: stack.currentIndex = (stack.currentIndex - 1 + stack.count) % stack.count
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
            onClicked: stack.currentIndex = (stack.currentIndex + 1) % stack.count
        }
    }
}
