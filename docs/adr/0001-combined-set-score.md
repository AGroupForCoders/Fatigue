# Sets get a combined score, compared only within the same shape

We want one number that says whether a set beat the last one when progress happens on more than weight and reps, for example going a notch deeper on the adductors at the same load. A set's score is its load (weight × reps for a rep set, weight × time for a hold, with unloaded sets counting as weight 1) multiplied by a factor for each tracked field. The factor runs from 1.0 at the worst end of the field's range to 2.0 at the best end, so "lower is better" and "higher is better" fields work the same way. Scores are only compared between sets of the same shape on the same exercise and brand, so a hold is never ranked against a rep set. The raw values and their own records stay visible next to the score.

This reverses the earlier requirement that "we do not combine fields into one score". The factor is a convention we made up, not a physical truth. We accepted that because seeing one number go up is what makes progressive overload on range of motion and time feel real.

## Consequences

- A tracked field needs a lowest and highest value when it is created, otherwise it has no factor.
- Changing a field's range or direction changes the scores of past sets, so scores are computed when needed and not stored.
