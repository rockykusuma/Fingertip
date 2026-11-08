import { Check, ChevronDown, Globe, Link } from 'lucide-react'
// Only the kit modules this scene uses, so the site loads just these
import { Stage } from './kit/stage'
import type { Act } from './kit/act'
import type { Point, Rect } from './kit/measure'
import { Bar, Window } from './kit/window'
import { Button } from './kit/controls/Button'
import { Roll } from './kit/motion/Roll'
import { Row } from './kit/parts/Row'
import { Avatar } from './kit/parts/Avatar'
import { Divider } from './kit/parts/Divider'
import './kit/keys.css'
import hand from './hand.png'
import './fingertip-hero.css'

// Fingertip's hero: the hand presents a Share window. It snaps to the access
// pop-up and taps (stamp 1, nothing pressed), highlights the sentence with
// ⌥ held, draws an arrow to Copy link with ⇧ held, then ⌘-clicks Copy link,
// which really reaches the app: the button turns to Copied and stamp 2 drops.
// The button reverts on its own, ⌃⌥X clears the ink and stamps, and the hand
// goes back where it started.
//
// Fingertip hides the system cursor and draws its hand, so the kit cursor is
// hidden and the hand follows every move from onMove. Annotation positions
// are stored against named targets (progress along the sentence, along the
// arrow, stamps by target), so the poster and both layouts measure them.

type Mod = '' | '⌥' | '⇧' | '⌘'
type S = {
  hand: Point | string | null // null: the rest point; a name: where the hand presses that target
  pressed: boolean
  snap: string | null
  hi: number // 0..1 across the sentence
  arrow: number // 0..1 from its start to Copy link
  stamps: string[]
  ripple: number
  copied: boolean
  mods: Mod
  key: Mod // the last key shown, kept while its keycap fades out
  cleared: boolean
}

const initial: S = { hand: null, pressed: false, snap: null, hi: 0, arrow: 0, stamps: [], ripple: 0, copied: false, mods: '', key: '⌥', cleared: false }
// The payoff: everything the presenter added is on screen and the click got through
const POSTER: S = { ...initial, hand: 'copy', snap: 'copy', hi: 1, arrow: 1, stamps: ['access', 'copy'], copied: true }

const SIZE = { wide: { w: 560, h: 360 }, compact: { w: 358, h: 340 } }
const REST = { wide: { x: 470, y: 176 }, compact: { x: 286, y: 226 } }
// Presses land on the control but off its words (Fingertip's snap ring and
// label still say what it is on)
const AIM = { x: 0.86, y: 0.62 }
const TIP = { x: 17, y: 11 } // the fingertip inside hand.png
const LABEL: Record<string, (s: S) => string> = {
  access: () => 'Pop-up button · Anyone with the link',
  copy: (s) => `Button · ${s.copied ? 'Copied' : 'Copy link'}`,
}

const aim = (r: Rect): Point => ({ x: r.x + r.width * AIM.x, y: r.y + r.height * AIM.y })
const straight = (p: number, from: Point, to: Point): Point => ({ x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p })

/** The arrow runs from empty space at the lower right up to Copy link's edge. */
function arrowEnds(copy: Rect, layout: 'wide' | 'compact') {
  const end = { x: copy.x + copy.width + 10, y: copy.y + copy.height * 0.62 }
  const start = layout === 'wide' ? { x: end.x + 108, y: end.y + 70 } : { x: end.x + 54, y: end.y + 78 }
  return { start, end }
}

function sentenceLine(r: Rect) {
  const y = r.y + r.height * 0.56
  return { from: { x: r.x - 3, y }, to: { x: r.x + r.width + 3, y } }
}

async function script(a: Act<S>) {
  const follow = (at: Point) => a.put({ hand: at })
  const go = (to: Parameters<Act<S>['move']>[0], duration?: number) => a.move(to, { onMove: follow, duration })
  const tap = async () => {
    await a.set({ pressed: true })
    await a.wait(110)
    await a.set({ pressed: false })
  }

  await a.wait(700)

  // Snap to the pop-up and tap: a stamp, and nothing is pressed
  a.mark('snap')
  await go({ at: 'access', ...AIM })
  await a.set({ snap: 'access' })
  await a.wait(450)
  await tap()
  await a.set((s) => ({ stamps: [...s.stamps, 'access'] }))
  await a.wait(700)

  // ⌥ held: highlight the sentence
  a.mark('highlight')
  await a.set({ snap: null })
  const line = sentenceLine(a.rect('sentence'))
  await go(line.from)
  await a.set({ mods: '⌥', key: '⌥', pressed: true })
  await a.wait(180)
  await a.drag(line.to, (at, _from, t) => a.put({ hand: at, hi: t }), { duration: 1000, cursor: 'preserve', path: straight })
  await a.set({ pressed: false })
  await a.wait(150)
  await a.set({ mods: '' })
  await a.wait(450)

  // ⇧ held: an arrow from empty space to Copy link
  a.mark('arrow')
  const { start, end } = arrowEnds(a.rect('copy'), a.layout)
  await go(start)
  await a.set({ mods: '⇧', key: '⇧', pressed: true })
  await a.wait(180)
  await a.drag(end, (at, _from, t) => a.put({ hand: at, arrow: t }), { duration: 820, cursor: 'preserve', path: straight })
  await a.set({ pressed: false })
  await a.wait(150)
  await a.set({ mods: '' })
  await a.wait(350)

  // ⌘-click Copy link: it reaches the app
  a.mark('click')
  await go({ at: 'copy', ...AIM }, 520)
  await a.set({ snap: 'copy' })
  await a.wait(380)
  await a.set({ mods: '⌘', key: '⌘' })
  await a.wait(260)
  await a.set((s) => ({ pressed: true, ripple: s.ripple + 1 }))
  await a.click()
  await a.set((s) => ({ pressed: false, copied: true, stamps: [...s.stamps, 'copy'] }))
  await a.wait(320)
  await a.set({ mods: '' })
  a.mark('payoff')
  await a.wait(2100)

  // The button reverts on its own, then ⌃⌥X clears what the presenter drew
  await a.set({ copied: false })
  await a.wait(700)
  a.mark('clear')
  await a.set({ snap: null })
  await a.key('ctrl+alt+x')
  await a.set({ cleared: true })
  const back = go(REST[a.layout], 900)
  await a.wait(320)
  await a.snap({ hi: 0, arrow: 0, stamps: [] })
  await a.set({ cleared: false })
  await back
  await a.snap({ hand: null, ripple: 0, key: '⌥' })
  await a.wait(500)
}

export function FingertipHero() {
  return (
    <Stage<S>
      width={SIZE.wide.w}
      height={SIZE.wide.h}
      compact={{ below: 520, width: SIZE.compact.w, height: SIZE.compact.h }}
      initial={initial}
      poster={POSTER}
      script={script}
      greys="cool"
      keys={{ wide: 'bottom-left', compact: 'bottom-left' }}
      cursor={{ at: REST, idle: false }}
      className="ft"
    >
      {(s, rect, layout) => {
        const size = SIZE[layout]
        const handAt: Point = s.hand === null ? REST[layout] : typeof s.hand === 'string' ? aim(rect(s.hand)) : s.hand
        const copy = rect('copy')
        const arrow = arrowEnds(copy, layout)
        const tipOfArrow = straight(s.arrow, arrow.start, arrow.end)
        const line = sentenceLine(rect('sentence'))
        const hiEnd = straight(s.hi, line.from, line.to)
        return (
          <>
            <Window title="Share" className="ft-win">
              <div className="ft-body">
                <div className="ft-access">
                  <Button
                    size="large"
                    className="ft-popup"
                    data-target="access"
                    icon={<Globe size={16} strokeWidth={2} />}
                    trailingIcon={<ChevronDown size={16} strokeWidth={2.2} />}
                  >
                    Anyone with the link
                  </Button>
                  <Button
                    size="large"
                    variant="primary"
                    className="ft-copy"
                    data-target="copy"
                    icon={
                      // One slot holding both glyphs, crossfaded, so the slot never opens or closes
                      <span className="ft-swap" data-copied={s.copied || undefined}>
                        <Link size={16} strokeWidth={2.2} />
                        <Check size={16} strokeWidth={2.6} />
                      </span>
                    }
                  >
                    {s.copied ? 'Copied' : 'Copy link'}
                  </Button>
                </div>
                <div className="ft-sentence">
                  <span data-target="sentence">Anyone with the link can view this plan.</span>
                </div>
                <Divider />
                <div className="ft-people">
                  <Bar w={118} h={7} tone={3} />
                  {[92, 70, 104, 80].map((w, i) => (
                    <Row key={i} pad={8} lead={<Avatar size={28} />} title={<Bar w={w} h={7} tone={2} />} subtitle={<Bar w={w + 40} h={6} tone={1} />}>
                      <Bar w={46} h={6} tone={1} />
                    </Row>
                  ))}
                </div>
              </div>
            </Window>

            {/* Fingertip's own layers, above every window, as the app's overlay is */}
            <div className="ft-overlay" data-cleared={s.cleared || undefined}>
              <svg className="ft-ink" width={size.w} height={size.h} viewBox={`0 0 ${size.w} ${size.h}`} aria-hidden>
                {s.hi > 0 && <path className="ft-hi" d={`M${line.from.x} ${line.from.y} L${hiEnd.x} ${hiEnd.y}`} />}
                {s.arrow > 0 && <path className="ft-arrow" d={arrowPath(arrow.start, tipOfArrow)} />}
              </svg>
              {s.stamps.map((name, i) => {
                const r = rect(name)
                return (
                  <span key={name} className="ft-stamp" style={{ left: r.x, top: r.y }}>
                    {i + 1}
                  </span>
                )
              })}
            </div>

            {Object.keys(LABEL).map((name) => {
              const r = rect(name)
              const on = s.snap === name || undefined
              return (
                <div key={name}>
                  <div className="ft-ring" data-show={on} style={{ left: r.x - 4, top: r.y - 4, width: r.width + 8, height: r.height + 8 }} />
                  {/* Pinned by its left edge, so a changing name grows to the right and nothing else moves */}
                  <div className="ft-label" data-show={on} style={{ left: r.x - 4, top: r.y - 10 }}>
                    <Roll>{LABEL[name]!(s)}</Roll>
                  </div>
                </div>
              )
            })}

            {s.ripple > 0 && <span key={s.ripple} className="ft-ripple" style={{ left: aim(copy).x, top: aim(copy).y }} />}

            <img
              className="ft-hand"
              src={hand}
              alt=""
              data-pressed={s.pressed || undefined}
              style={{ transform: `translate(${handAt.x - TIP.x}px, ${handAt.y - TIP.y}px)` }}
            />

            {/* A held modifier, the kit's own keycap row kept down while it is */}
            <div className="ss-keys ft-mods" data-show={!!s.mods} data-at="bottom-left" aria-hidden>
              <kbd className="ss-key" data-down={!!s.mods}>
                {s.key}
              </kbd>
            </div>
          </>
        )
      }}
    </Stage>
  )
}

/** Shaft plus an open head sized to the line, as Fingertip draws it. */
function arrowPath(a: Point, b: Point) {
  const len = Math.hypot(b.x - a.x, b.y - a.y)
  let d = `M${a.x} ${a.y} L${b.x} ${b.y}`
  if (len > 0.5) {
    const head = Math.min(Math.max(12, 5 * 4.5), len * 0.5)
    const ang = Math.atan2(b.y - a.y, b.x - a.x)
    for (const side of [-1, 1]) {
      const t = ang + Math.PI - (side * Math.PI) / 7
      d += ` M${b.x} ${b.y} L${b.x + head * Math.cos(t)} ${b.y + head * Math.sin(t)}`
    }
  }
  return d
}
