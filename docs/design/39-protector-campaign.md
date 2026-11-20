# Chapter 39 — The Protector campaign: The Guardian of Pinehaven

Ten missions that make the player the person Pinehaven calls when something
goes wrong. You begin by repairing an elderly neighbour's window; by the end
you coordinate shelters, rescues and a town-wide blackout.

The twist: the more you protect Pinehaven, the more the collective becomes
interested in you. That is not an arbitrary difficulty raise. Your
fortified shelters, emergency signals and evacuation routines change how
the town works, and the creatures respond to that.

Central question: can you protect a town from something that grows stronger
when people are afraid?

Estimated 8 to 12 hours of directed play with exploration and optional
activities (a design estimate, not a measurement). Completing it permanently
improves Pinehaven and leaves the horror intact.

## Design rules

- Most nights stay peaceful; defence only; Maya lives independently across
  the lake; Caramelo is a persistent companion; monster research is optional.
- Player actions produce persistent world changes. No fetch-quest grind.
- No permanent death for Caramelo or Maya in the prototype.
- Main-story progress is never blocked behind optional research.
- Residents become more independent because of your help: more progress
  means quieter nights, not twice as many emergencies.

## The ten missions

| # | Mission | Giver, place | Play | Unlock | Story clue |
| --- | --- | --- | --- | --- | --- |
| 1 | The Broken Window (Act I) | Martha, residential street, daytime | Get a latch at Frank's, gather wood, repair her kitchen window before an afternoon storm; read the forecast | Basic window reinforcement blueprint; Martha shares food and news | Pinehaven's windows were reinforced against visitors, not weather; the first winter people slept with the lights off |
| 2 | The Road Home (Act I) | Frank, forest road | Find two stranded residents (Caramelo tracks), bring repair supplies, get them home before night: repair the truck or lead them to an emergency cabin; both work, with different consequences | Emergency route markers; Frank's discounts | They saw something move unnaturally fast between the trees |
| 3 | Three Houses, One Night (Act I) | Martha and Frank, eastern street | An odd Chaoscope reading; three houses with broken shutters, a dead radio, a bad circuit; not enough supplies for all, so prioritise or get neighbours to help each other; the night is uneasy, not certain disaster | Neighbourhood preparedness board | Some houses show chaotic energy with no creature in sight |
| 4 | The Silent Kennel (Act II) | Vet clinic, abandoned boarding kennel | Caramelo follows a scent to a kennel where a Dweller holds a room; find the animals, distract, lead them out quietly; calm Caramelo when he panics | Advanced recall and quiet-hiding training; vet supplies | Creatures seem interested in animal fear too |
| 5 | The House Across the Lake (Act II) | Maya by radio, her house | A storm breaks her bedroom latch while creatures investigate. Guide her by radio, watch from your window and report, go over if conditions allow, prepare a distraction or route, or wait for dawn. Maya keeps herself safe with her own survival logic | Linked home radio between both houses; joint routines | A creature at her house reacts to a radio transmission, not to her movement |
| 6 | The Last Supply Run (Act II) | Ellen, warehouse and main street | Reopen the route to a stranded shipment (food, batteries, medicine), decide what matters most, recruit neighbours who trust you | Community supply depot; Ellen's expedition meals | Warehouse records of odd deliveries to the textile mill before the collapse |
| 7 | The Shelter Under the School (Act III) | Dr. Hale and residents, old school | Repair ventilation, power and doors of a refuge beneath the school; test power; set routes from nearby streets | Community emergency shelter | The coats were only one part of a larger defence system |
| 8 | The Storm Without Rain (Act III) | Dr. Hale, weather station and lookout | Abnormal energy under clear skies; footsteps with no visible creature; install monitoring and keep residents from panicking | Neighbourhood anomaly warning network | Some events precede manifestations rather than follow them |
| 9 | No Lights in Pinehaven (Act IV) | Emergency network, several streets | A regional anomaly approaches: test radios, check vulnerable houses, deliver supplies, activate warning signals, confirm shelters, help isolated residents. Watch the town go dark house by house; no attack is guaranteed | Emergency broadcast authority; advanced warning gear | The Chaoscope repeats the pattern from the first Bad Night, seventeen years ago |
| 10 | The Long Quiet (Act IV) | The community, whole starting region | A powerful collective event. Open the shelter, coordinate residents, choose where to intervene; Maya helps remotely, Caramelo finds isolated people, Frank runs supplies, Ellen the shelter, Hale the readings. Earlier missions decide how prepared the town is. The goal is to keep Pinehaven alive until dawn, not to beat a boss | Guardian of Pinehaven status; shelter upgrades; next investigation | "The quiet is ending." The Chaoscope reaches an unrecorded reading, then every detector drops to zero, the creatures stop, and the mill transmits: "You have taught them where the safe places are." |

## Relationships after the campaign

| Character | Start | After |
| --- | --- | --- |
| Maya | Independent girlfriend, trusted companion | Cooperative partner with shared emergency plans and a deeper story |
| Caramelo | Loyal, sometimes frightened | Better trained, recognises danger, hides reliably |
| Martha | Friendly neighbour | Treats the player like family, shares local history |
| Frank | Practical shopkeeper | Trusted ally organising repairs and defence |
| Ellen | Diner owner | Community ally for meals and shelter logistics |
| Dr. Hale | Cautious researcher | Shares predictions, relies on the player's judgement |
| Noah Reed | Mysterious Observer | Respects the player's practical knowledge; his goal (understand) and yours (protect) sometimes conflict |

## Protector capabilities (not stat boosts)

Handyman → Safe Passage → Neighbourhood Coordinator → Animal Rescuer →
Emergency Communicator → Supply Organiser → Shelter Engineer → Anomaly
Coordinator → Emergency Dispatcher → Guardian of Pinehaven. Each adds a new
gameplay option.

## Town preparedness

Every completed mission raises the town's real ability to survive:
Martha's reinforced window is stronger in later storms, a repaired bridge
changes which routes residents can use, a restored shelter gives displaced
families somewhere to go. Survival depends on individual buildings, routes
and NPC states, not only an aggregate score (a readiness percentage is just
a summary).

## How it reveals the mystery

- Act I: why homes have reinforced windows, blackout routines, supplies.
- Act II: fear, noise, animals, radios and rescues influence the creatures.
- Act III: an older defensive network lies beneath the town.
- Act IV: the creatures may respond to the town's organised resistance, not
  just individual fear.

Homesteader and Explorer paths must reach the same major revelations through
different missions.

## Architecture

QuestService, QuestObjectiveRegistry, QuestPersistenceService,
TownReputationService, TownPreparednessService, CommunityProjectService,
NPCRelationshipService, EmergencyRouteService, ProtectorProgressionService,
TownEventDirector. Quest definitions are data. Reusable objectives: Gather,
Deliver, Repair, Inspect, Escort, Track, Communicate, Observe, Survive,
Activate, Coordinate.

Persistence: reinforced windows, repaired buildings, restored radios,
unlocked routes, relationship flags and preparedness all persist. Define
which changes are per player and which belong to the shared town; per-player
DataStores do not make a shared persistent town by themselves.

Integrate with existing inventory and food, building and shelter, creature
AI, weather, dog AI, Maya, the Chaoscope, the journal and audio. Reuse, do
not duplicate.

## Milestones

1. Missions 1-3: repairs, gathering, dialogue, escort-or-shelter
   alternatives, resource allocation, persistent changes.
2. Missions 4-6: Caramelo tracking, quiet rescue, Maya emergency
   coordination, supply logistics, relationship changes.
3. Missions 7-8: community shelter, Chaoscope anomalies, warning network,
   nonvisual horror.
4. Missions 9-10: town-wide preparation, emergency communication,
   collective events, large state changes, several town outcomes.

Start by inspecting the existing quest, NPC, inventory, building and
persistence systems, build the shared campaign framework, then Mission 1
from conversation to persistent repair.

## Mission quality bar

Each mission has an NPC or narrative trigger, a clear objective, at least
one meaningful interaction, a real challenge or decision, a useful reward, a
persistent consequence, acknowledgement in dialogue or the world, and a link
to the wider story. Test starting conditions, every objective state,
alternate solutions, success and recoverable failure, rejoining,
multiplayer consistency, NPC availability, and consequences in later events.
A mission is not complete until its playable flow is verified. Update
`STATUS.md` after every milestone.
