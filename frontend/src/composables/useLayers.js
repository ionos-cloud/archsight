// The ArchiMate layers in the order they are shown, top to bottom: why (motivation), what we want to become
// (strategy), how the change happens (implementation and migration), then the architecture it changes (business,
// application, technology). "other" holds the tool's own kinds (pages, views, imports, ...) and stays last.
// Sidebar and search facets both use this order.
export const LAYERS = [
  { id: 'motivation', title: 'Motivation' },
  { id: 'strategy', title: 'Strategy' },
  { id: 'implementation', title: 'Implementation' },
  { id: 'business', title: 'Business' },
  { id: 'application', title: 'Application' },
  { id: 'technology', title: 'Technology' },
  { id: 'other', title: 'Other' },
]

export const LAYER_IDS = LAYERS.map((layer) => layer.id)
