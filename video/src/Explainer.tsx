import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {COLORS, FPS} from './theme';
import {
  Close,
  HowPipeline,
  ImportClip,
  Numbers,
  Problem,
  TamperClip,
  TrustPoints,
  WhatZsnap,
} from './scenes';

// from/dur in seconds; the last one's end defines the composition length.
const TIMELINE: {comp: React.FC<{durationInFrames: number}>; from: number; dur: number}[] = [
  {comp: Problem, from: 0, dur: 14},
  {comp: WhatZsnap, from: 14, dur: 12},
  {comp: HowPipeline, from: 26, dur: 24},
  {comp: ImportClip, from: 50, dur: 14},
  {comp: TrustPoints, from: 64, dur: 18},
  {comp: TamperClip, from: 82, dur: 12},
  {comp: Numbers, from: 94, dur: 18},
  {comp: Close, from: 112, dur: 10},
];

export const TOTAL_FRAMES = Math.round((112 + 10) * FPS);

export const Explainer: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: COLORS.bg}}>
      {TIMELINE.map(({comp: Comp, from, dur}, i) => (
        <Sequence key={i} from={Math.round(from * FPS)} durationInFrames={Math.round(dur * FPS)}>
          <Comp durationInFrames={Math.round(dur * FPS)} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
