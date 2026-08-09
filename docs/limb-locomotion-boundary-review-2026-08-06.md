> Superseded contract note: profile v9 now uses 398 inputs and 16 direct outputs, retains full target height/vertical relative motion, and adds physical per-limb grip/carry state. The standing mechanics and inherited hip/arena corrections remain relevant. See `docs/generic-grip-and-pickup-review-2026-08-06.md`.

# Limb locomotion, hip freedom, and arena-boundary review — 2026-08-06

## Runtime evidence

The user confirmed that the new generic elastic body stands reliably and can retain posture even when the chassis is tilted close to 90 degrees. The remaining behavior is therefore a locomotion-contract problem rather than a structural-collapse problem.

Observed behaviors:

- workers can walk through the open viewing edge and fall out of the room;
- normal walking attempts look radially stiff;
- policies favor a stiff crab gait;
- policies discovered a “jellyfish” exploit that rolls/drags the chassis while cramping the legs to gain target distance.

## Hip-axis review

The previous profile exposed:

- radial elevation around hip Z;
- axial twist around the upper segment's own long axis X.

Axial twist rotates the knee plane but does not move the complete upper leg forward/back around the body. It is therefore a poor substitute for a coxa-like horizontal sweep and explains why the model had to use stiff radial or whole-body tricks.

Profile v7 replaces the second semantic with actual horizontal sweep:

- hip X is body-local up at rest and yaws the complete leg;
- hip Z remains the tangent elevation axis that carries standing load;
- hip Y remains locked;
- stock sweep is widened to ±72 degrees;
- stock elevation is ±68 degrees;
- action order remains three values per limb: elevation, horizontal sweep, knee.

Godot's Generic6DOF joint allows each angular axis to be limited and spring-controlled independently. This makes the two-axis hip explicit rather than relying on an arbitrary swing/twist interpretation.

## Arena-edge review

The shared obstacle sensor previously queried only physical training-wall records. The open floor edge had no wall record, so it was invisible to the policy. Limb termination also ignored horizontal arena bounds, allowing bodies to fall indefinitely.

The correction:

- analytically intersects each directional ray with the arena floor rectangle;
- merges the nearest floor-edge distance with physical wall distances;
- marks a target path blocked when it crosses the floor edge;
- terminates when the chassis footprint crosses the safe floor rectangle or drops below the room;
- leaves sideways/upside-down states alive while still inside the arena.

No visible wall is added, and drone collision geometry is unchanged.

## Jellyfish/crab reward review

The former target-progress term paid for horizontal distance reduction regardless of how the body was supported. A one-time collision penalty could therefore be outweighed by repeated progress while the chassis rolled or dragged on the floor.

The correction separates:

- `core_contact`: any chassis contact;
- `core_wall_contact`: chassis contact with a training wall;
- `core_support_contact`: an external chassis contact whose normal points sufficiently upward.

Only `core_support_contact` identifies chassis crawling. It now:

- applies continuous `core_drag` punishment;
- zeros positive target-progress reward;
- does not erase negative reward for moving away;
- does not classify an upright wall brush as crawling.

Positive progress is additionally scaled by uprightness, standing-height quality, and useful foot-support ratio. This does not prescribe a gait; crab-like motion remains valid if the body is genuinely carried by its feet, while head-rolling/chassis-dragging loses its reward advantage.

## Compatibility decision

The physical meaning of action output 1 changed, so silent checkpoint reuse would be incorrect. The following identifiers were advanced:

- body profile `four_limb_physics_v7`;
- action schema 3;
- observation/feature schema 7.

The feature count remains 315 and the action count remains 12, but old models are intentionally rejected.

## Tests added or updated

- correct physical hip basis and dense action mapping;
- stock horizontal range and sanitization;
- open-edge lidar distance and terminal footprint boundary;
- target-path boundary blocking;
- in-arena sideways recovery remains nonterminal;
- chassis-supported progress is zero and continuously punished;
- wall-only chassis contact is not mistaken for dragging;
- authoritative chassis-support contact is required and reaches the model tensor.

## Sources used

- Godot 4.6 `Generic6DOFJoint3D` documentation: separate per-axis angular limits and springs.
- Godot 4.6 Jolt documentation: unsupported Generic6DOF limit softness/restitution/damping/ERP fields remain unused.
- Safe Reinforcement Learning for Legged Locomotion: motivates recovery behavior rather than treating every unsafe-looking posture as an immediate hard terminal.
- Learning agility and adaptive legged locomotion via curricular hindsight reinforcement learning: joint/base/foot state and orientation, height, slip, torque, acceleration, energy, and collision terms are all used to separate stable locomotion from reward exploits.

Verified source links:

- https://docs.godotengine.org/en/4.6/classes/class_generic6dofjoint3d.html
- https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html
- https://research.google/pubs/safe-reinforcement-learning-for-legged-locomotion/
- https://www.nature.com/articles/s41598-024-79292-4
