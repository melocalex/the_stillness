# Game design

## The feeling

> "I am cozy. I am safe. I am home. Something terrible is outside, but here I
> am protected."

Comfort is the primary emotion. Horror exists to make comfort meaningful. The
game is not a chase game: most nights are peaceful, and the best moments are
quiet ones, sitting by the fire with Caramelo while rain hits the roof and
something stands at the edge of the trees.

Daytime is for exploring. Dusk is for heading home. Night is for being inside.

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
| Bad nights | Rare, warned in advance. Lights off, curtains closed, coat on, stay still. One creature scratches; a group breaks in. |
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

## Story arc

The prologue and first seven days follow docs/STORY (Chapter 0/33):
arrival, the grandfather's note, the first meal with Maya, the first Watcher
at dusk, three knocks at the bedroom window, the morning trip to Pinehaven,
then the coat, the storm, Maya's emergency, the sheriff's records and the
first Bad Night. Objectives are data-driven, stored on the server, and never
soft-lock a slow player.

## Design chapters

The full brief is split into chapters 1-33 (vision, environment, world,
day/night, shelter, creature AI, creature types, coat, dog, building,
comfort, weather, story, music 26, ecology and windows 27, bad nights 28,
storms 29, town 31, Maya 32, prologue 33). `STATUS.md` tracks which parts
are implemented.
