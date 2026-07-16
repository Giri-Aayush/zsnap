import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {COLORS, FONTS} from './theme';
import {Appear, ClipSlot, Kicker, Scene, Terminal} from './ui';

type SceneProps = {durationInFrames: number};

const Title: React.FC<{children: React.ReactNode; size?: number; max?: number}> = ({
  children,
  size = 68,
  max = 1500,
}) => (
  <div
    style={{
      fontSize: size,
      fontWeight: 700,
      lineHeight: 1.12,
      textAlign: 'center',
      maxWidth: max,
      letterSpacing: -1,
    }}
  >
    {children}
  </div>
);

const Sub: React.FC<{children: React.ReactNode; max?: number}> = ({children, max = 1200}) => (
  <div
    style={{
      fontSize: 34,
      lineHeight: 1.5,
      color: COLORS.textDim,
      textAlign: 'center',
      maxWidth: max,
      marginTop: 28,
    }}
  >
    {children}
  </div>
);

// 1. The problem
export const Problem: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Kicker>The problem</Kicker>
    </Appear>
    <Appear delay={10}>
      <Title>
        A fresh Zcash node replays the <span style={{color: COLORS.accent}}>entire chain</span> from
        genesis.
      </Title>
    </Appear>
    <Appear delay={28}>
      <Sub>
        Every block downloaded and re-verified to rebuild the state. Hours on testnet, and{' '}
        <span style={{color: COLORS.text}}>14 to 16 hours on mainnet.</span>
      </Sub>
    </Appear>
    <Appear delay={54}>
      <Sub max={1100}>
        The usual workaround is copying an <span style={{color: COLORS.red}}>unverified</span>{' '}
        database. Fast, but you trust whatever you downloaded.
      </Sub>
    </Appear>
  </Scene>
);

// 2. What zsnap is
export const WhatZsnap: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Kicker>What zsnap does</Kicker>
    </Appear>
    <Appear delay={10}>
      <Title>
        Bootstrap a fresh node from a{' '}
        <span style={{color: COLORS.accent}}>hash-verified</span> state snapshot.
      </Title>
    </Appear>
    <Appear delay={30}>
      <div
        style={{
          marginTop: 44,
          fontFamily: FONTS.mono,
          fontSize: 30,
          background: COLORS.bgPanel,
          border: `1px solid ${COLORS.line}`,
          borderRadius: 12,
          padding: '26px 34px',
          lineHeight: 1.9,
        }}
      >
        <div>
          <span style={{color: COLORS.textDim}}>$ </span>zebrad{' '}
          <span style={{color: COLORS.accent}}>export-snapshot</span> ./snap
        </div>
        <div>
          <span style={{color: COLORS.textDim}}>$ </span>zebrad{' '}
          <span style={{color: COLORS.accent}}>import-snapshot</span> ./snap --expect-hash{' '}
          <span style={{color: COLORS.textDim}}>{'<hash>'}</span>
        </div>
      </div>
    </Appear>
    <Appear delay={52}>
      <Sub>Fast and verified, with the same trust model Zebra already uses for checkpoints.</Sub>
    </Appear>
  </Scene>
);

// 3. How: the pipeline
const Step: React.FC<{n: number; title: string; body: string; delay: number}> = ({
  n,
  title,
  body,
  delay,
}) => (
  <Appear delay={delay} style={{width: '100%'}}>
    <div style={{display: 'flex', gap: 24, alignItems: 'flex-start', width: 1300}}>
      <div
        style={{
          minWidth: 56,
          height: 56,
          borderRadius: 28,
          background: COLORS.accent,
          color: COLORS.bg,
          fontFamily: FONTS.mono,
          fontWeight: 700,
          fontSize: 28,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {n}
      </div>
      <div>
        <div style={{fontSize: 34, fontWeight: 700}}>{title}</div>
        <div style={{fontSize: 26, color: COLORS.textDim, marginTop: 6, lineHeight: 1.45}}>
          {body}
        </div>
      </div>
    </div>
  </Appear>
);

export const HowPipeline: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames} style={{alignItems: 'center'}}>
    <div style={{position: 'absolute', top: 90}}>
      <Appear>
        <Kicker>How it works</Kicker>
      </Appear>
    </div>
    <div style={{display: 'flex', flexDirection: 'column', gap: 36, marginTop: 40}}>
      <Step
        n={1}
        delay={16}
        title="Export"
        body="A read-only secondary reads the live node's finalized state into a canonical, chunked, hashed archive. Zero downtime."
      />
      <Step
        n={2}
        delay={40}
        title="The .zsnap archive"
        body="One chunk per column family, plus a manifest. A BLAKE2b canonical hash covers the consensus state and is the snapshot's identity."
      />
      <Step
        n={3}
        delay={64}
        title="Import"
        body="A fresh node authenticates the hash before writing a single byte. Wrong or tampered data is refused."
      />
      <Step
        n={4}
        delay={88}
        title="Tail-sync"
        body="Normal consensus verifies the imported shielded trees against the block header the moment the first new block lands."
      />
    </div>
  </Scene>
);

// 3b. Real import capture (slot)
export const ImportClip: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Kicker>See it run</Kicker>
    </Appear>
    <Appear delay={10} style={{marginTop: 20}}>
      <ClipSlot
        label="[ real terminal capture: import ]"
        note="Drop in the screen recording of `zebrad import-snapshot ... --expect-hash <hash>`: the hash check, the per-column-family import, then `tip height` reached in seconds."
      />
    </Appear>
  </Scene>
);

// 4. Why it's safe
const Point: React.FC<{title: string; body: string; delay: number}> = ({title, body, delay}) => (
  <Appear delay={delay}>
    <div
      style={{
        width: 640,
        background: COLORS.bgPanel,
        border: `1px solid ${COLORS.line}`,
        borderRadius: 12,
        padding: '24px 26px',
      }}
    >
      <div style={{fontSize: 28, fontWeight: 700, color: COLORS.accent}}>{title}</div>
      <div style={{fontSize: 23, color: COLORS.textDim, marginTop: 8, lineHeight: 1.45}}>{body}</div>
    </div>
  </Appear>
);

export const TrustPoints: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <div style={{position: 'absolute', top: 90}}>
      <Appear>
        <Kicker>Why it is safe</Kicker>
      </Appear>
    </div>
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '1fr 1fr',
        gap: 28,
        marginTop: 60,
      }}
    >
      <Point
        delay={14}
        title="No new trust"
        body="The manifest hash is trusted exactly like Zebra's hardcoded block checkpoints."
      />
      <Point
        delay={30}
        title="Every chunk hashed"
        body="Per-chunk hashes catch a single flipped byte before the database is written."
      />
      <Point
        delay={46}
        title="Consensus checks it"
        body="The shielded trees are verified against block-header commitments during tail-sync. Forged state cannot survive."
      />
      <Point
        delay={62}
        title="N-of-M attestations"
        body="Independent operators reproduce and co-sign the same hash, so no single publisher is trusted."
      />
    </div>
  </Scene>
);

// 4b. Real tamper-rejection capture (slot)
export const TamperClip: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Kicker>It refuses bad data</Kicker>
    </Appear>
    <Appear delay={10} style={{marginTop: 20}}>
      <ClipSlot
        label="[ real terminal capture: tamper rejection ]"
        note="Drop in the recording of flipping one byte in a chunk, then a failed import: the per-chunk hash no longer matches and nothing is written."
        height={360}
      />
    </Appear>
  </Scene>
);

// 5. Measured numbers
const Row: React.FC<{cells: string[]; delay: number; head?: boolean}> = ({cells, delay, head}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [delay, delay + 8], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '1fr 1fr 1.4fr',
        opacity,
        fontFamily: FONTS.mono,
        fontSize: 30,
        padding: '14px 0',
        borderBottom: `1px solid ${COLORS.line}`,
        color: head ? COLORS.textDim : COLORS.text,
      }}
    >
      {cells.map((c, i) => (
        <div key={i} style={{textAlign: i === 0 ? 'left' : 'right', paddingRight: 24}}>
          {c}
        </div>
      ))}
    </div>
  );
};

export const Numbers: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Kicker>Measured on testnet, release build</Kicker>
    </Appear>
    <Appear delay={10} style={{marginTop: 24}}>
      <div style={{width: 1180}}>
        <Row head cells={['Testnet height', 'Import', 'Sync from genesis']} delay={12} />
        <Row cells={['100,000', '0.7 s', '14 min']} delay={22} />
        <Row cells={['500,000', '4.6 s', '68 min']} delay={34} />
        <Row cells={['1,000,000', '11.7 s', '133 min']} delay={46} />
      </div>
    </Appear>
    <Appear delay={64}>
      <Sub max={1180}>
        Warm best-case. Mainnet is estimated at{' '}
        <span style={{color: COLORS.text}}>15 to 40 min</span> to import versus a{' '}
        <span style={{color: COLORS.text}}>14 to 16 hour</span> sync. The bytes moved are the same
        either way; what disappears is the replay.
      </Sub>
    </Appear>
  </Scene>
);

// 6. Close
export const Close: React.FC<SceneProps> = ({durationInFrames}) => (
  <Scene durationInFrames={durationInFrames}>
    <Appear>
      <Title size={80}>
        Fast <span style={{color: COLORS.textDim}}>and</span>{' '}
        <span style={{color: COLORS.accent}}>verified.</span>
      </Title>
    </Appear>
    <Appear delay={16}>
      <div style={{fontFamily: FONTS.mono, fontSize: 30, marginTop: 34, color: COLORS.textDim}}>
        github.com/Giri-Aayush/zsnap
      </div>
    </Appear>
    <Appear delay={30}>
      <Sub max={900}>A testnet-validated snapshot sync prototype, built on a Zebra fork.</Sub>
    </Appear>
  </Scene>
);
