# Fuzzlet look mechanics

Fuzzlet is a single soft plush body with a stable lower-body/base anchor. When looking around, the upper body and face lead the motion with a restrained squash-and-turn; the torso remains planted so the pet does not slide or spin. The eyes are physical expressive eye globes: the whole eye surface, iris, pupil, eyelids, rims, and highlights turn together with the head rather than adding replacement pupils.

Cardinal pose families in viewer/screen coordinates:

- `000` up: feet and lower body stay planted; the face lifts, eyelids open upward, and both eyes rotate toward 12 o'clock. The lower face becomes slightly less visible.
- `090` screen-right: the soft upper body bends subtly right; the right side leads, the left cheek/body edge becomes more occluded, and the eye globes turn right with the head.
- `180` down: the face and upper body settle forward/down; eyelids and eye globes aim toward 6 o'clock while the lower body remains anchored.
- `270` screen-left: the upper body bends subtly left; the left side leads, the right cheek/body edge becomes more occluded, and the eye globes turn left with the head.

Intermediate directions use even 22.5-degree steps between these families. The face/eyes lead, the fuzzy upper silhouette follows with a small continuous bend, and the lower body remains stable. There are no props, cords, or detached effects to track. Keep the plush volume, teal/blue-violet fur, cream face/belly, and large original eye construction unchanged; do not rotate the entire sprite or add new eyes.

Motion budget: each adjacent direction changes gaze and upper-body bend by one small, visually even increment. The `157.5 -> 180` and `337.5 -> 000` joins must be continuous, with no scale pop, baseline jump, mirror flip, or front-facing reset.
