// cropShapes.ts — the crop shapes CropDialog offers.
//
// Split out of CropDialog.tsx because a file that exports a component may not
// also export constants or types: Vite's fast refresh can only swap a module
// whose exports are all components, so mixing the two downgrades every edit of
// that file to a full page reload (react-refresh/only-export-components).

/** The same shapes the app offers, so a photo means one thing across both. */
export const SHAPES = [
  { key: 'free', label: 'crop.free', ratio: null },
  { key: 'square', label: 'crop.square', ratio: 1 },
  { key: 'standard', label: 'crop.standard', ratio: 4 / 3 },
  { key: 'wide', label: 'crop.wide', ratio: 16 / 9 },
] as const

export type ShapeKey = (typeof SHAPES)[number]['key']
