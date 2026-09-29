import QtQuick
import QtQuick.Layouts
import "../components"

// Only validated artifact types have a component here. Add one mapping for a
// new card; AiPanel and the rest of the answer layout stay unchanged.
Item {
  id: host
  required property var artifact
  required property SpotlightPalette chrome
  signal openRequested(string url)

  implicitHeight: card.item ? card.item.implicitHeight : 0

  Loader {
    id: card
    anchors.fill: parent
    sourceComponent: host.artifact.type === "map" ? mapCard
      : host.artifact.type === "weather" ? weatherCard : null
  }

  Component {
    id: mapCard
    MapArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onOpenRequested: function(url) { host.openRequested(url) }
    }
  }

  Component {
    id: weatherCard
    WeatherArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onOpenRequested: function(url) { host.openRequested(url) }
    }
  }
}
