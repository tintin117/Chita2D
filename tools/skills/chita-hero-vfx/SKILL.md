---
name: chita-hero-vfx
description: Design, revise, and verify Chita hero sprites, attack and spell effects, and ability icons in Godot. Use for hero redesigns, directional poses, camera projection, cast alignment, hit feedback, and kit art.
---

# Chita hero art and VFX

## Agree on the look and scope

- For a redesign with open design choices, ask about the silhouette, weapon or prop, and signature visual before producing the full sheet. Use the user's references and approved features as the target. When the direction is already specified, proceed with it. For a narrow revision, preserve the approved design and change the part the user identified.
- Identify the exact ability and assets in scope. Chita has distinct display slots for the basic, RMB skill, passive, and ult. Inspect the hero entry in [hero.gd](../../../scripts/hero.gd), the spell implementation, and the cast selection in [player.gd](../../../scenes/player/player.gd). Compare the tooltip with the actual mechanic.
- Treat changes to damage, timing, reach, targeting, and hit area as gameplay changes. Get the user's decision when correcting the camera would change coverage. For an approved projection change, update the visual boundary and hit test together, then check lock-on, chase, and bot range checks that depend on the same geometry.

## Meet the roster's art standard

- Compare the actual gameplay sprites for Knight, Rogue, Mage, and Ranger. Match their elevation, scale, shadow placement, and pixel density. Use the approved concept to guide the hero-specific silhouette, material, palette, and highlights. For a larger redesign, inspect one representative pose and effect at game scale before building every sheet.
- Standard character atlases in `assets/isometric_character/<unit>/` are 1,920 × 1,024, with 15 columns and eight rows of 128 × 128 cells. Keep the pivot, shadow, and transparent margins consistent between frames. Leave enough clearance for shader offsets and trails. Keep nearest filtering and check that atlas frames sample their own cells.
- Give each finished effect readable shape, value changes, and motion. For Chaos Lord, tapered lilac edges, dark violet cavities, and broken translucent facets echo the robe and blades. Inspect the effect against grass and stone. Check transparent edges for visible rectangular mattes, adjacent-cell bleed, clipped tips, and harsh fill that covers the character. Keep range cues light enough for the attack pose to read.
- Place hero effects under `assets/isometric_projecttile/` alongside the hero's kit. Use `SheetFrames.seq` or `SheetFrames.play_once` for existing frame folders where they fit. Layer ground art below actors and place elevated or front-facing parts at their proper depth.

## Match the camera, pose, and hit

- Use the [arena Projection Lab](../../../scenes/levels/projection_lab.tscn) and the actual arena tiles as the camera reference. The 32 × 16 floor tiles use a 2:1 projection. Judgement, Chaos Cleave, and Time Sphere render ground offsets with `Vector2(1.0, 0.5)` and divide screen offsets by that scale for their hit tests. Project elevated features separately from the footprint. Purify uses its own 0.58 ratio for both drawing and hit tests, so check the mechanic's existing convention before adopting a ratio.
- [SheetFrames](../../../scripts/sheet_frames.gd) orders the rows SE, S, SW, W, NW, N, NE, E. Those are runtime facing labels. Inspect the painted profile and rear views for believable depth, hidden surfaces, stable weapon edges, and smooth changes across rows. Test diagonal boundary crossings and cases where raw aim and the resolved cast direction differ. A locked attack that retargets at release should update the displayed facing without restarting the attack frames. Use the resolved direction for the cast pose and launch effect when they need to line up.
- Work from the frames the game plays. Check anticipation, release, and recovery, or idle and movement for a held effect. Match the brightest release beat to when the ability actually fires. Immediate casts can open on a strong release pose and use the later frames for recoil. Measure each relevant row in native pixels, then apply the sprite's offset, scale, rotation, and transform. Interpolate measured key poses when the anchor moves.
- Attach a trail to the painted blade tips or to sampled projectile positions, including through a turn. Place launch art at the measured aperture and use front or rear layering as the actor turns. For fields, use the active timer and hit boundary for gameplay cues. Keep fade-out purely visual once the field expires.
- For basic attacks, trace the LMB cast through the selected sprite clip, any separate range or windup drawing, and the victim impact. A requested removal must cover every phase that draws the old effect. Knight Cleave uses a white blade trail on the swing and dedicated hit art. Check the opening cut, return cut, and finisher at match speed so a brighter trail on one combo beat cannot hide a missing trail on another. [Knight Cleave render and timing](../../../spells/knight_fx.gd), [basic attack runtime](../../../spells/hero_basic.gd)
- When a move calls for a travel, hold, and impact sequence, coordinate movement, sprite timing, and the hit window from the same phase durations. For Judgement, horizontal travel ends at the apex, the Knight holds and descends in place, and the grounded sword pose, damage, and end of airborne protection coincide. Check the first impact physics tick and try movement input through the hold. [Judgement](../../../spells/judgement.gd), [player movement and cast playback](../../../scenes/player/player.gd)
- Distinguish release, travel, confirmed impact, miss, and expiration where applicable. Play custom hit art only for a confirmed hit and preserve existing sound, hit-stop, and status feedback. Route networked impact art through the authoritative result and suppress the replaced shared flash so each hit reads once.

To inspect the native pixels, use the [pose sheet helper](scripts/pose_sheet.py):

```sh
python3 tools/skills/chita-hero-vfx/scripts/pose_sheet.py \
  assets/isometric_character/10ChaosLord/CastSpell.png /tmp/chita-cast.png \
  --frame 0 --frame 2 --frame 5 --grid 8
```

## Connect kit art

Use [ArenaUi](../../../scenes/ui/arena_ui.gd) for the local pick screen, Gym and online pick, and match HUD. Display slots are basic, skill, passive, ult. Runtime combat slot 2 is the ult, while display slot 2 is the passive. Dedicated kit sheets use a vertical strip of four 16 × 16 cells in display order. Give icons distinct silhouettes at HUD size, especially when two abilities share a prop, such as Knight's thrown shield and Bulwark. Check all four slots, the skill's cooldown overlay, and both ult charge and ready states. Retain the shared fallback for heroes that use it.

## Verify before handoff

- Open a fresh, separate Godot preview after the changed textures have imported. Exercise the normal input path and inspect the actual render at gameplay scale. An already-running match can still show the previous assets. For projection or art readability, include a painted arena such as Four Quarters at match zoom as well as the Gym where useful.
- Review every touched facing on the contact sheet. In Godot, capture the changed poses and effects across the affected angles and phases. Let lingering effects from earlier casts clear when checking whether a trail, arc, or flash is gone. For attacks and fields, check a hit, a miss or just-outside target, and cleanup. For a projected area, check both axes. For persistent fields, check a late entrant and release. For a moving or held effect, check the caster or target in motion. Compare with the approved reference and iterate if the shape, angle, or timing still reads poorly.
- Run focused checks for the changed behavior and inspect the log after the effect has drawn. Headless runners that depend on autoloads should defer their test body until the scene tree is ready. Report what was actually tested and identify previews as Godot captures or mockups. Call out material gaps such as untested multiplayer replication or incomplete directional coverage.

For implementation examples, see [Chaos Blast](../../../spells/rift_bolt.gd) for per-facing release anchors and sampled homing trails, [Time Sphere](../../../spells/stillwake.gd) for layered glass and projected hit coverage, [Purify](../../../spells/purification.gd) for a two-pass sweep and confirmed impact, and [Guardian Angel](../../../spells/guardian_angel.gd) for a body-attached effect with separate front and rear layers.
