# Fatigue

A lifting tracker that keeps history per brand and lets you progress on more than weight and reps: time, range of motion and anything else you choose to log.

## Training

**Workout**:
One training session, made up of an ordered list of exercises and the sets done on each.
_Avoid_: Session, log

**Routine**:
A saved, named list of exercises with planned sets, used as a template to start a workout.
_Avoid_: Template, program, plan

**Exercise**:
What you do, such as "Chest Press", "Adductors" or "Dumbbell Flies", either built in or created by the user.
_Avoid_: Machine, movement, lift

**Brand**:
Who made the equipment an exercise is done on, such as Technogym or Hammer Strength, with an optional label such as the model or gym. A brand is optional. An exercise logged without one is on "no brand", which keeps its own history, settings and records like any other brand. Technogym chest press and Hammer Strength chest press are the same exercise on different brands, and keep separate history, settings and records.
_Avoid_: Machine, variant, manufacturer, equipment, station

## Sets

**Measure**:
One value every set of an exercise records: reps or time (exactly one, picked when the exercise is created and never changed), weight (or not, for an unloaded exercise), and any tracked number setting marked "every set", such as "Notch". An exercise has at most three.
_Avoid_: Field, variable, column, metric

**Set**:
One effort within an exercise in a workout, with a value for each of the exercise's measures. Every set of an exercise counted in reps is a rep set, and every set of one counted in time is a hold.

**Rep set**:
A set of an exercise whose measures include reps, with a weight if the exercise is weighted.

**Hold**:
A set of an exercise whose measures include time, with a weight if the exercise is weighted. A held version of an exercise is a separate exercise, such as "Shoulder Press Isometric".
_Avoid_: Timed hold, time set

**Unloaded**:
A set with no weight logged. Unloaded is not the same as 0 kg.
_Avoid_: Bodyweight, zero weight

**Setting**:
Something you set up on an exercise on one brand, such as "Seat 4", "Notch 7" or "Dead stop": a number, a yes/no or text. It has one value for the whole exercise in a workout, unless it's a tracked number marked "every set", which makes it a measure with a value on each set. Settings do not carry over between brands.
_Avoid_: Field, custom field, set field, variable, attribute

**Override**:
Retired. A setting value that a group of sets changed from the exercise's value. A setting that varies from set to set is now a measure, typed on every set. Older workouts keep their overrides as each set's value.

**Group**:
Retired. A run of sets that shared a kind and the same overrides, under a heading such as "Hold · Notch 8". Every set in an exercise now has the same measures, so there is nothing to group.

**Tracked setting**:
A number setting with a direction (higher or lower is better) and a range (lowest and highest value), so the app can detect records on it and factor it into the score.
_Avoid_: Tracked field, counted setting

**Range of motion**:
How deep a set went, almost always logged as a tracked setting such as "Notch".
_Avoid_: ROM (in UI copy)

## Progress

**Shape**:
Which values a set has: rep set or hold, loaded or unloaded, and which tracked settings it has a value for. It mostly follows from the exercise's measures, but an older set can lack a measure turned on later. Only sets with the same shape on the same exercise and brand are compared.

**Score**:
A single number for a set: its load (weight × reps, or weight × time, with unloaded counting as 1) multiplied by a factor of 1.0 to 2.0 for each tracked setting, depending on where in its range the value falls.
_Avoid_: Volume, rating

**Record**:
The best value of something (weight, reps, time, a tracked setting, or score) among sets of the same shape on the same exercise and brand.
_Avoid_: PR, PB, best
