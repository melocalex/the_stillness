# Game design

## The feeling

> "I am cozy. I am safe. I am home. Something terrible is outside, but here I
> am protected."

Comfort is the primary emotion. Horror exists to make comfort meaningful. The
game is not a chase game: most nights are peaceful, and the best moments are
quiet ones, sitting by the fire with Caramelo while rain hits the roof and
something stands at the edge of the trees.

Daytime is for exploring. Dusk is for heading home. Night is for being inside.

## Revision 2.0 decisions (2026-11-20)

These override any older chapter text that disagrees.

1. **Most nights are safe.** Night types roll Peaceful 65%, Uneasy 25%,
   Bad 9%, Black 1% (`GameConfig.Nights`, configurable). The story pins the
   first nights: 1 and 2 Peaceful, 3 Uneasy. No Black Night before day 14.
2. **Defensive play only.** No weapons and no killing monsters. The axe is a
   tool for wood. You survive with light, sound, curtains, latches,
   shutters, the coat, stillness and breath.
3. **Maya lives in her own house across the lake.** She may visit or stay
   over, but the player's cabin is not her home. She has her own routine,
   lights and radio.
4. **Monster research and storm chasing are optional paths.** A player who
   only wants the cozy home loop never has to take them.

## Setting

Pinehaven, an isolated mountain town of about 1,800 people that went quiet
seventeen years after a figure in an old coat first stood in a yard and never
moved. The player inherits their grandfather's cabin by the lake. Across the
water lives Maya. The town is a half-day walk away.

Rules the town learned (and the systems implement):

1. Creatures are drawn to light, noise and movement.
2. They share what they notice (the collective mind).
3. The old textile-mill coats interfere with how they find people.

## Core systems

| System | Design rule |
| --- | --- |
| Day/night | Day 12 min, dusk 3, night 8, dawn 2 (config). Server clock. |
| Shelter | A secure cabin (every door/window/roof installed, shut, unbroken) is safe from ordinary creatures on ordinary nights. Safety is predictable. |
| Perception | Three channels: sight (light, movement, distance, weather), hearing (noise events through walls and rain), presence (the unnatural sense the coat suppresses). Creatures remember a last known position, never the true one. |
| The coat | Not invisibility. Strongly suppresses presence, helps when still, never cancels sound. |
| Hold breath | A short stealth advantage with a capacity; running out causes an audible gasp. |
| Windows | Observation is gameplay: look out, zoom, record sightings in the journal. Curtains block sight both ways. Unlatched windows can be forced open by wind. |
| Bad nights | 9% Bad, 1% Black, warned in advance. Lights off, curtains closed, coat on, stay still. One creature scratches; a group breaks in. |
| Dog | A companion, not a decoration: follows, warns, hides with you, never dies. |
| Comfort | Physical, emotional, weather, observational, routine and achieved coziness. Improves recovery. |
| Exposure | A readout of the real perception inputs, never a dice roll of its own. |
| Weather | Continuous rain intensity 0-5; most rain is calm; storms are rare. Rain masks sound and hides shapes for both sides. |
| Music | Adaptive states (home, rain, dusk, night, nearby, hunting, lost, dawn). Silence is intentional; cues only after quiet gaps. |

## Creatures in this prototype

- **Watcher**: tall, still, watches lit windows, moves when unobserved, never
  chases for long. Psychological pressure.
- **Dweller**: lives in abandoned interiors, hunts by sound, leashed to its
  territory.
- **Crawler**: bad nights only, low and fast, part of the collective, can
  break entry points as a group.
- **The Old One**: a rare silhouette on the ridge. Watchers withdraw from it.

### The unnatural (Chapter 35)

Creatures are calm by default and sudden when they move; speed is
frightening only because it is rare.

- **Fear as food.** Each character's fear drifts toward a target built from
  fictional gameplay signals: creature threat, pursuit, a creature in view,
  exposure in the dark, creature noises nearby. A secure home, Caramelo,
  the fire and Maya calm it. Creatures within 90 studs feed on it: energy
  with diminishing returns, plus an appetite that grows while they feed.
  Both decay when people stay calm, so calm players starve them.
- **The bound.** Energy and hunger change boldness only: how long a
  creature stares, how often it dashes, displaces or makes noise, and
  whether hunger pulls it toward lit houses. They never change shelter,
  breach or capture rules, or the night odds.
- **Watcher movement.** It holds dead still under a gaze, its head turning
  slowly toward you. After a long stare it either withdraws or, fed on
  fear, dashes sideways to a spot by a tree and freezes again. While nobody
  can see it (wide cone and line of sight, checked at both ends) it can
  displace 10-22 studs toward what it wants. It never lands in a shelter or
  within 20 studs of a player, and it never catches anyone mid-dash. It
  walks slowly and pauses to watch lit houses.
- **The window encounter.** Shut out of one window (curtains, shutters, or
  it simply loses sight), a Watcher may soon be at another window of the
  same house, tapping, and the tap comes again a few seconds later. At most
  two hops per visit; it walks, or appears only where nobody can see it,
  outside the walls.
- **The false departure.** A Deceiver, or any well-fed Watcher, walks away
  and returns silently to the window it left, once.
- **Maya sees it too.** From night 2, when something is near your cabin at
  night, her lamps go out across the lake; she radios once and lights her
  lamp again after it has gone.
- **Crawler and Dweller** move in bursts with dead stops, jumpier but slower
  on average.
- **Noises are behaviour.** Distant calls, close breathing, and at a wall a
  tap or scratch that repeats a few seconds later, as if testing for an
  answer. Silence is the default.
- **Temperaments** (Patient, Impulsive, Curious, Deceiver, Hungry) are small
  multipliers on those choices; species rules still apply.

### Caramelo (Chapter 38)

He senses creatures with his own ears, eyes and a nose for presence, before
you do and imperfectly. Heavy rain hides distant steps, deer and gusts can
make him look up, and a perfectly still Watcher can slip past his eyes. His
agitation rises fast and settles slowly across five warning levels:

| Level | What you see and hear |
| --- | --- |
| 0 Relaxed | Sleeping, resting by the fire |
| 1 Attentive | Head up, looking toward something |
| 2 Suspicious | Watching a window, a quiet growl |
| 3 Frightened | Whimpering, coming to you (or to his bed if you are far) |
| 4 Panicked | Barking |

Barks are real noise events creatures hear. A panic bark is two or three;
a single defensive bark can startle a Crawler right on top of him. One bark
is rarely a disaster; repeated barking adds up. Calm him (T when he is
agitated) one moment at a time, never instantly. Hide together (E): crouch
in the coat and he tucks under its hem, which calms and quiets him while you
stay crouched. A bark under the coat is still a bark. He learns: calming
him out of real fear trains quietness, long hiding trains shared hiding,
and a creature that came and went without harm frightens him less next
time. He is never fearless.

## Story arc

**Day 1, the opening (Revision 2.0, implemented in `OpeningService`):**

1. You wake alone in your furnished cabin with Caramelo. The fire is lit,
   the door is hung, the windows are latched.
2. Maya radios from across the lake: "Morning. I can see smoke coming from
   your chimney. Are you awake yet? Come over later—I made something for
   you." If nobody answers, the speaker carries her voice after a while.
3. Gather firewood with the visible axe (key 1), then feed the fire.
4. Walk around the lake and visit Maya in daylight. Lunch: she gives you a
   warm stew.
5. At sunset she radios a warning; you head home before dark.
6. The first Watcher appears at the north treeline. Maya coaches you by
   radio: look through the north window, put on your grandfather's coat,
   cut the lights at the fuse box, close the curtains, crouch, stay still,
   hold your breath if it is at the glass. The real creature AI runs the
   visit. During this lesson a hunt is always broken off, so it cannot end
   in a capture.
7. It leaves. Calm rain starts. Maya's upstairs lamp comes on: "You okay
   over there? I can still see your house."
8. Rest by the fire with Caramelo, then sleep to wake at dawn.

Every day-1 step has a fallback (a timed nudge or an automatic fact), so a
slow or lost player is delayed, never stuck.

**Days 2-7** keep the older arc where it does not contradict Revision 2.0:
stone and repairs, the abandoned house, the radio signal on the west hill,
strengthening the cabin, the coat's secret, the storm, the sheriff's
records, the first Bad Night. Maya's emergencies wait for the rescue system
(Chapter 32). The night mystery that used to live in the lake house now
plays out at the hill house. Objectives are data-driven, stored on the
server, and never soft-lock a slow player.

## Design chapters

The full brief is split into chapters 1-33 (vision, environment, world,
day/night, shelter, creature AI, creature types, coat, dog, building,
comfort, weather, story, music 26, ecology and windows 27, bad nights 28,
storms 29, town 31, Maya 32, prologue 33). `STATUS.md` tracks which parts
are implemented.
