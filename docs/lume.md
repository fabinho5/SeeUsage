# Lume desktop companion

Enable **Show Lume companion** in Settings → General → Appearance. The companion is optional and starts hidden. It is independent of the floating quota bar.

Lume is SeeUsage’s origami firefly: a dark aubergine body, asymmetric mint and coral paper wings, and an amber lantern belly that dims as quota runs low. It is a small transparent desktop pet, roughly 70 pixels tall, with six original 2D sprites: idle, blink, worn, critical, hurt and celebrate. It drifts slowly around its current screen, stops under the pointer, can be dragged to another position or monitor, and stays within the visible desktop. Right-click to pause roaming, check quotas immediately or hide it. macOS Reduce Motion stops roaming and animated movement.

While enabled, it refreshes SeeUsage's quotas every five minutes. Claude's data comes from the existing status-line integration; the companion reloads that cache instead of altering Claude's configuration. Hiding Lume cancels its polling loop and animation timers.

The first successful observation establishes a baseline. Later observations compare each profile and quota window with its own previous reading. The largest drop in percentage points determines the damage number and shake strength; drops in 5h and weekly quotas are not added together, because they can represent the same consumption. A fresh check with no loss triggers a brief celebration. Quota resets, new profiles, missing data and repeated cache values do not invent damage.

The lowest available quota determines the resting expression: healthy at 40% or above, tired below 40%, and exhausted below 15%. If no fresh quota is available, Lume becomes muted and waits for data. No persistent quota labels or bars are added to the app's main interface.

Artwork and the complete generation prompts are recorded in [lume-artwork.md](lume-artwork.md). The generated transparent PNGs live in `Sources/SeeUsage/Resources/Companion`; SwiftPM and the app packaging script both include them.
