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
  signal copyRequested(string value)

  implicitHeight: card.item ? card.item.implicitHeight : 0

  Loader {
    id: card
    anchors.fill: parent
    focus: true
    sourceComponent: host.artifact.type === "map" ? mapCard
      : host.artifact.type === "weather" ? weatherCard
      : host.artifact.type === "palette" ? paletteCard
      : host.artifact.type === "chart" ? chartCard
      : host.artifact.type === "comparison" ? comparisonCard
      : host.artifact.type === "timeline" ? timelineCard : null
  }

  Component {
    id: timelineCard
    TimelineArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
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
    id: comparisonCard
    ComparisonArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: chartCard
    ChartArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onOpenRequested: function(url) { host.openRequested(url) }
    }
  }

  Component {
    id: paletteCard
    PaletteArtifact {
      artifact: host.artifact
      chrome: host.chrome
      onCopyRequested: function(value) { host.copyRequested(value) }
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
