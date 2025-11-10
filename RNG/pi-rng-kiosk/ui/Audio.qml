import QtQuick
import QtMultimedia

Item {
  id: root

  // Legacy-compatible API
  property url  source: ""
  property real volume: 1.0
  property int  loops: 1        // 1 = once, -1 = infinite, n>1 = play n times
  property bool autoPlay: false

  // internal loop counter
  property int _remaining: 0

  signal error(string message)

  AudioOutput {
    id: out
    volume: root.volume
  }

  MediaPlayer {
    id: player
    audioOutput: out
    source: root.source
    onErrorOccurred: root.error(errorString)
    onPlaybackStateChanged: {
      if (playbackState === MediaPlayer.StoppedState) {
        if (root._remaining === -1) {
          player.play()
        } else if (root._remaining > 1) {
          root._remaining--
          player.play()
        }
      }
    }
  }

  function play() {
    if (!root.source || String(root.source) === "") return
    root._remaining = root.loops
    player.stop()
    player.play()
  }

  Component.onCompleted: {
    if (autoPlay) play()
  }
}
