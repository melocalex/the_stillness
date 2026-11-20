# What turns the world into a game: priorities and missing systems

Defining sentence: **build a life worth protecting in a town that is
learning to live alongside something impossible.**

The game has plenty of ideas. What it still needs is prioritisation,
interconnected progression, and proof that the core loop is fun.

## Eight missing pieces, by impact

1. **A central purpose: the Quieting Project.** A long effort to restore the
   town's shelters, radios and protective gear while learning why the
   creatures are more active. Every project feeds it; monster research stays
   optional.
2. **Decisions with lasting consequences.** For example, materials for the
   grocery store or the residential shelter, not both. Choices open
   different opportunities; reasonable decisions are never irreversibly
   punished.
3. **One systemic event director.** Bad Nights, storms, creature incidents
   and Chaoscope anomalies are coordinated into believable events with
   build-up, pacing and variety, and the director knows when to do nothing.
   Otherwise five systems trigger horror at once.
4. **One psychology model.** The causal links between fear, comfort, noise,
   shelter, the coat and Caramelo's emotions are defined in one place. The
   player's fictional fear must not be an automatic monster power generator
   that lets one scare escalate without limit. (Current rule in code: fear
   feeds creature boldness only, with diminishing returns and decay; it
   never changes shelter, breach or capture rules. See
   `src/shared/Logic/FearEcology.luau`.)
5. **Mystery progression.** Planned revelations, evidence, false
   assumptions and choices at roughly 5, 15 and 30 hours, without
   explaining everything early.
6. **Exploration with real discoveries.** Hidden trails, abandoned
   shelters, environmental puzzles, rare supplies, unusual houses,
   landmarks with histories.
7. **A multiplayer identity.** Small co-op sessions in one town: separate or
   shared houses, rescues, observation teams, trading.
8. **A strict definition of finished.** A feature is done only when a player
   can use it, it survives a reload, it works with other systems, and it
   does not break the first night.

## Three distinguishing mechanics

- **The town's collective fear.** When many residents are frightened, the
  collective intensifies: creatures grow curious, strange events increase,
  routines change. Stronger shelters, forecasts and organised neighbours
  soften the consequences. Long goal: make Pinehaven feel safe again without
  removing its supernatural nature.
- **The house remembers.** Caramelo's favourite spot, Maya's notes, the
  window that held through last night's storm, a photograph from your first
  sighting on the wall: the home as a record of your adventures.
- **Nights have stories.** A night director picks unusual but coherent
  situations: a Watcher outside for minutes; Maya's radio silent; an
  impossible Chaoscope reading with no creatures; a perfectly peaceful
  night; rarely, something the whole town lives through. It understands
  suspense, danger, relief and recovery.

## Build order

| Priority | Deliverable | Why |
| --- | --- | --- |
| 1 | A complete first 20 minutes | Proves the game is enjoyable |
| 2 | Five replayable town missions | Reasons to leave home |
| 3 | One complete, intelligent Watcher | Proves the horror |
| 4 | Caramelo's emotional AI and animations | Attachment and tension |
| 5 | One fully working Chaoscope event | Proves invisible horror |
| 6 | Persistent home, relationship and town progress | Makes returning worthwhile |

Then a small playable seven-day campaign, not a giant world: check whether
players form routines and want to know what happens next.

## Player identity

Reputation grows from actions, without rigid classes: the **Protector**
(reinforce houses, rescue neighbours, organise shelters), the
**Homesteader** (build, garden, cook, a beautiful life), the **Observer**
(storms, creatures, mysteries) and the **Explorer** (lost places, supplies,
history). Players mix all four; the town sees them by what they do.
