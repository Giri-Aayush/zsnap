import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {COLORS, FONTS} from './theme';

// Fade + rise in, hold, fade out near the end of the enclosing Sequence.
export const Appear: React.FC<{
  delay?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({delay = 0, children, style}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - delay, fps, config: {damping: 200}});
  const opacity = interpolate(s, [0, 1], [0, 1]);
  const y = interpolate(s, [0, 1], [24, 0]);
  return <div style={{opacity, transform: `translateY(${y}px)`, ...style}}>{children}</div>;
};

// Whole-scene wrapper that fades the scene in and out so cuts are not hard.
export const Scene: React.FC<{
  durationInFrames: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({durationInFrames, children, style}) => {
  const frame = useCurrentFrame();
  const fadeFrames = 12;
  const opacity = interpolate(
    frame,
    [0, fadeFrames, durationInFrames - fadeFrames, durationInFrames],
    [0, 1, 1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );
  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.bg,
        fontFamily: FONTS.sans,
        color: COLORS.text,
        justifyContent: 'center',
        alignItems: 'center',
        opacity,
        ...style,
      }}
    >
      {children}
    </AbsoluteFill>
  );
};

export const Kicker: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      fontFamily: FONTS.mono,
      fontSize: 26,
      letterSpacing: 4,
      textTransform: 'uppercase',
      color: COLORS.accent,
      marginBottom: 24,
    }}
  >
    {children}
  </div>
);

// A labelled placeholder where a real terminal capture is dropped in later.
// Renders now as a clearly-marked slot; swap for <Video> once the clip exists.
export const ClipSlot: React.FC<{
  label: string;
  note: string;
  width?: number;
  height?: number;
}> = ({label, note, width = 1180, height = 400}) => {
  const frame = useCurrentFrame();
  const pulse = 0.5 + 0.5 * Math.sin(frame / 8);
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 14,
        border: `3px dashed ${COLORS.accentDim}`,
        backgroundColor: COLORS.bgPanel,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        alignItems: 'center',
        gap: 16,
      }}
    >
      <div style={{fontSize: 40, opacity: 0.4 + 0.4 * pulse}}>{'▶'}</div>
      <div style={{fontFamily: FONTS.mono, fontSize: 30, color: COLORS.accent}}>{label}</div>
      <div style={{fontSize: 22, color: COLORS.textDim, maxWidth: width * 0.7, textAlign: 'center'}}>
        {note}
      </div>
    </div>
  );
};

// A small mock terminal used where a real capture is not required.
export const Terminal: React.FC<{
  title: string;
  lines: {text: string; color?: string; delay: number}[];
  width?: number;
}> = ({title, lines, width = 1120}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        width,
        borderRadius: 12,
        overflow: 'hidden',
        border: `1px solid ${COLORS.line}`,
        backgroundColor: '#0d1117',
        boxShadow: '0 24px 60px rgba(0,0,0,0.45)',
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          padding: '12px 16px',
          backgroundColor: COLORS.bgPanelHi,
          borderBottom: `1px solid ${COLORS.line}`,
        }}
      >
        <span style={{width: 12, height: 12, borderRadius: 6, background: '#ff5f56'}} />
        <span style={{width: 12, height: 12, borderRadius: 6, background: '#ffbd2e'}} />
        <span style={{width: 12, height: 12, borderRadius: 6, background: '#27c93f'}} />
        <span style={{marginLeft: 12, fontFamily: FONTS.mono, fontSize: 18, color: COLORS.textDim}}>
          {title}
        </span>
      </div>
      <div style={{padding: '22px 26px', fontFamily: FONTS.mono, fontSize: 24, lineHeight: 1.6}}>
        {lines.map((ln, i) => {
          const opacity = interpolate(frame, [ln.delay, ln.delay + 6], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          });
          return (
            <div key={i} style={{opacity, color: ln.color ?? COLORS.text, whiteSpace: 'pre-wrap'}}>
              {ln.text}
            </div>
          );
        })}
      </div>
    </div>
  );
};
