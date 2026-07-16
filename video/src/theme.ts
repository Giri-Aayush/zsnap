// Visual system for the zsnap explainer. Engineering tone, not marketing:
// dark background, one warm accent, monospace for anything technical.

export const COLORS = {
  bg: '#0b0e13',
  bgPanel: '#141922',
  bgPanelHi: '#1c232f',
  line: '#2a3340',
  text: '#e8edf4',
  textDim: '#93a1b3',
  accent: '#f4b728', // Zcash gold
  accentDim: '#8a6a1f',
  green: '#4ade80',
  red: '#f87171',
  blue: '#60a5fa',
};

export const FONTS = {
  sans: '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif',
  mono: '"SF Mono", "JetBrains Mono", "Menlo", ui-monospace, monospace',
};

export const FPS = 30;

// Scene layout on the timeline (in seconds). Durations feed the Sequence lengths.
export const SCENES = {
  problem: {from: 0, dur: 14},
  what: {from: 14, dur: 12},
  how: {from: 26, dur: 38},
  trust: {from: 64, dur: 30},
  numbers: {from: 94, dur: 18},
  close: {from: 112, dur: 10},
};

export const TOTAL_SECONDS = 122;
