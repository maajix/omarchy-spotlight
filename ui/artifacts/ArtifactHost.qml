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
  property var checklistCompleted: []
  signal checklistProgressRequested(var completed)
  property var galleryActions: ({})
  property bool galleryBusy: false
  signal imageActionRequested(string identity, string action)

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
      : host.artifact.type === "timeline" ? timelineCard
      : host.artifact.type === "diagram" ? diagramCard
      : host.artifact.type === "checklist" ? checklistCard
      : host.artifact.type === "dashboard" ? dashboardCard
      : host.artifact.type === "places" ? placesCard
      : host.artifact.type === "diff" ? diffCard
      : host.artifact.type === "gallery" ? galleryCard : null
  }

  Component {
    id: galleryCard
    GalleryArtifact {
      artifact: host.artifact
      actions: host.galleryActions
      actionBusy: host.galleryBusy
      onImageActionRequested: function(identity, action) { host.imageActionRequested(identity, action) }
      onOpenRequested: function(url) { host.openRequested(url) }
    }
  }

  Component {
    id: diffCard
    DiffArtifact {
      artifact: host.artifact
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: placesCard
    PlacesArtifact {
      artifact: host.artifact
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: dashboardCard
    DashboardArtifact {
      artifact: host.artifact
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: checklistCard
    ChecklistArtifact {
      artifact: host.artifact
      completed: host.checklistCompleted
      onProgressRequested: function(completed) { host.checklistProgressRequested(completed) }
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: diagramCard
    DiagramArtifact {
      artifact: host.artifact
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: timelineCard
    TimelineArtifact {
      artifact: host.artifact
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
      onOpenRequested: function(url) { host.openRequested(url) }
      onCopyRequested: function(value) { host.copyRequested(value) }
    }
  }

  Component {
    id: chartCard
    ChartArtifact {
      artifact: host.artifact
      onOpenRequested: function(url) { host.openRequested(url) }
    }
  }

  Component {
    id: paletteCard
    PaletteArtifact {
      artifact: host.artifact
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
