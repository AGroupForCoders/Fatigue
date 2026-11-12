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
Who made the equipment an exercise is done on, such as Technogym or Hammer Strength, with an optional label such as the model or gym. A brand is optional. An exercise logged without one is on "no brand", which keeps its own history, fields and records like any other brand. Technogym chest press and Hammer Strength chest press are the same exercise on different brands, and keep separate history, fields and records.
_Avoid_: Machine, variant, manufacturer, equipment, station

## Sets

**Set**:
One effort within an exercise in a workout. Every set is either a rep set or a hold.

**Rep set**:
A set measured in reps, with an optional weight.

**Hold**:
A set measured in time, with an optional weight.
_Avoid_: Timed hold, isometric, time set

**Unloaded**:
A set with no weight logged. Unloaded is not the same as 0 kg.
_Avoid_: Bodyweight, zero weight

**Field**:
A user-defined value logged on every set of an exercise on one brand, either a number (such as "Notch") or a yes/no (such as "Dead stop"). Fields do not carry over between brands.
_Avoid_: Custom field, set field, variable, attribute

**Tracked field**:
A number field with a direction (higher or lower is better) and a range (lowest and highest value), so the app can detect records on it and factor it into the score.

**Range of motion**:
How deep a set went, almost always logged as a tracked field such as "Notch".
_Avoid_: ROM (in UI copy)

## Progress

**Shape**:
Which values a set has: rep set or hold, loaded or unloaded, and which tracked fields. Only sets with the same shape on the same exercise and brand are compared.

**Score**:
A single number for a set: its load (weight × reps, or weight × time, with unloaded counting as 1) multiplied by a factor of 1.0 to 2.0 for each tracked field, depending on where in its range the value falls.
_Avoid_: Volume, rating

**Record**:
The best value of something (weight, reps, time, a tracked field, or score) among sets of the same shape on the same exercise and brand.
_Avoid_: PR, PB, best
