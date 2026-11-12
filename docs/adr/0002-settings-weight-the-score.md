# Settings weight the score, multiply together, and are the user's call

ADR 0001 gave number fields a factor from 1.0 to 2.0 across their range. Two things have changed since. Fields became settings: a setting has a value for the whole exercise, and a group of sets can override it, such as a hold at notch 8 while the rest use notch 7. And a yes/no setting can make a set harder too. Dead stopping at the bottom of an adductor rep is harder than bouncing, and the score had no way to say so.

So every setting that counts is a multiplier on weight × reps (or weight × time for a hold):

- A number setting keeps ADR 0001's factor: 1.0 at the worst end of its range, 2.0 at the best.
- A yes/no setting gets a factor the user picks for when it's on, from 1.0 up to 2.0. Off is 1.0. There's no factor below 1.0, because the settings people track make a set harder, not easier.
- The factors multiply together, and the total is capped at 3.0. Notch 8 (×1.78) with dead stop (×1.5) is ×2.67. Anything that would stack past ×3 stops at ×3, so one exercise can't run away from the rest.
- A setting counts only when the user says so. A new setting starts at "doesn't count", and the score is plain weight × reps until then.

We chose to let users set the weighting instead of predetermining it. Settings are free text per machine, so "Notch" can mean range of motion on one machine and seat position on another, and any default we pick will be confidently wrong for someone. A wrong default also bends the graph without anyone noticing. Starting at "doesn't count" means the graph matches what people expect from Hevy until they choose otherwise.

## Consequences

- A setting needs a factor (yes/no) or a direction and range (number) before it counts. The data model's `field` table needs a factor column for yes/no settings.
- Changing a factor re-scores all of history, which is why scores stay computed when shown and never stored (ADR 0001).
- Because combinations are weighted, the graph can show one line across them. Splitting by a setting is how someone checks that their factor is right.
- The app may suggest a name-based factor ("Most people use ×1.25 for a dead stop") and, later, one worked out from the user's own RPE. A suggestion is only applied when the user confirms it.
