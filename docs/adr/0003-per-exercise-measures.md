# Each exercise has fixed measures, a held version is its own exercise, and there are at most three

Until now every set chose what it was. A set was a rep set or a hold, and a group of sets could override any setting from a heading such as "Hold · Notch 8". It worked, but the workout screen had to explain itself: headings between sets, a setup sheet behind each heading, and an Add set menu to pick which setup the next set used. It also made history hard to read. A hold and a rep set on the same exercise and brand are never compared (ADR 0001 only ranks sets of the same shape), so mixing them in one exercise bought nothing but one shared name.

So an exercise now has fixed **measures**, the values every one of its sets records:

- Reps or time, exactly one, picked when the exercise is created and never changed. Changing it would leave every old set measured in the other unit.
- Weight, or not. Off is unloaded, which the score already counts as weight 1. It can be turned on and off; older sets keep what they had.
- Any tracked number setting marked "every set", such as Notch, stored per set where overrides used to be. It can be turned on and off too, and older sets just lack the value.

Every set in an exercise has the same boxes under one header row. Other settings (seat height, dead stop, text) stay one value per exercise, shown under the name.

A rep exercise and its held version are separate exercises, such as "Shoulder Press" and "Shoulder Press Isometric", each with its own brands, settings, history and records. They already never shared a record or a line on the graph, so the split only makes visible what the scores were doing. The phone migration moves the holds out of any exercise that mixed both into "<Name> Isometric", with IDs built from the rows they came from so two phones that migrate the same history agree after sync. The Hevy import does the same for duration sets.

There are at most three measures. On a phone the set row also holds the set number, Previous, RPE and the tick, and three boxes is what fits at a readable size. Three also covers what we've seen people track: weight, reps and one range-of-motion setting, or time and two settings. A fourth that varies on every set usually means the exercise is really two exercises.

## Consequences

- `exercise.measures` and `setting.every_set` are new synced columns, so the sync schema goes to 2 and older builds can't overwrite them (see the Sync page).
- A built-in exercise only syncs once its measures differ from its defaults, and is still built in by name when it arrives.
- Groups, headings, the setup sheet and the Add set menu are gone. `workout_set_override` stays as the table for every-set values, and overrides from older workouts still count for the score.
- Two exercises where there was one means a user who did both will see both in the picker. The isometric one is named after the original so it sorts next to it.
