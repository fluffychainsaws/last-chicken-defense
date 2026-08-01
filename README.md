# Last Chicken Defense — The Armaeggin

Cozy chicken-farm sim by day. First-person horror tower defense by night.
Something comes out of the trees, and it wants your chickens. It might be zombies.
It might be goblins. It might be furious midget people with sticks. It might be
A LITERAL DRAGON???

Built with **Godot 4.7** (all placeholder models are procedural — no assets needed).

## Play it

**[Play in your browser →](https://fluffychainsaws.github.io/last-chicken-defense/)**

Every push to `main` exports the Web build and publishes it to GitHub Pages.
The browser build uses the WebGL2 (compatibility) renderer and ships without
`models/*.glb`, so the goblin falls back to its procedural placeholder there.

## Run it

Open the project folder in Godot 4.7+ and press **F5**, or from a terminal:

```
godot --path .
```

## How to play

| Input | Action |
| --- | --- |
| WASD / Shift / Space | Move / sprint / jump |
| Mouse | Look / attack |
| 1-4 or wheel | Shovel, Shotgun, Feed, Egg |
| E | Interact (market computer, repair coop, send/recall foragers) |
| Esc | Pause / close market |
| N | (debug) skip straight to night |

### Day
- Hens wander the yard and lay **eggs** every dawn — walk over eggs to collect.
- **E** on a chicken sends it foraging in the forest (it brings back coins).
- **Hold E** at the coop to repair damage from last night.
- The computer in the house runs the **Farmers Market app**: sell eggs, buy
  hens, a rooster (breeding), feed, shotgun/shells, fence tiers, armory
  plating, tiny war helmets, an egg turret, and more.

### Night
- The coop becomes the **Armory**. Chickens run to it — unless they have
  war helmets, in which case they have chosen violence.
- A random themed wave attacks: they chew the fence, grab chickens, and haul
  them into the dark. Bosses appear every 4th night (red moon).
- Lose every chicken and it's over. The Armaeggin has come.

## Roadmap
- [ ] Co-op up to 8 players (Godot high-level multiplayer / ENet — host authoritative)
- [ ] Real character models + animations (replace procedural placeholders)
- [ ] Grid inventory screen (current: hotbar + counts)
- [ ] More night events, weather, seasons
- [ ] Sound pass (current: procedural bleeps)
