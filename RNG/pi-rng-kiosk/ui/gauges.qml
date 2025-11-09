import QtQuick 6.5
import QtQuick.Controls 6.5

Item {
    id: gauge
    property real value: 0
    property real maxValue: 5
    property color accent: "#1dd1a1"
    property color backgroundColor: "#091422"

    implicitWidth: 320
    implicitHeight: 320

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: backgroundColor
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.min(centerX, centerY) - 12
            ctx.lineWidth = 18
            ctx.strokeStyle = "#202b3a"
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, Math.PI, 2 * Math.PI)
            ctx.stroke()

            var clamped = Math.max(-maxValue, Math.min(maxValue, gauge.value))
            var sweep = (clamped + maxValue) / (2 * maxValue)
            ctx.strokeStyle = accent
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, Math.PI, Math.PI + sweep * Math.PI)
            ctx.stroke()
        }

        Connections {
            target: gauge
            function onValueChanged() { canvas.requestPaint() }
            function onAccentChanged() { canvas.requestPaint() }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 6
        Label {
            text: "GDI"
            font.pixelSize: 22
            color: "#b0c7dd"
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Label {
            text: gauge.value.toFixed(2)
            font.bold: true
            font.pixelSize: 54
            color: accent
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}

