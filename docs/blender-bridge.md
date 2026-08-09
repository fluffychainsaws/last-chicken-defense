# Driving Blender from Claude Code

Notes for pointing a local Claude Code session at a live Blender, so mesh and
rig work can be done in the viewport instead of by rendering stills and
inspecting them. This is local-only: a cloud session has no route to your
desktop, and no amount of configuration changes that.

The bridge is [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp).
It has two halves that must agree with each other:

- **`addon.py`**, installed into Blender, which opens a socket on port 9876
- **an MCP server process**, which Claude Code launches and which dials that
  socket

## Setup

1. **Install `uv`** — the official installer, not pip.
   ```powershell
   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
   ```
   Open a new terminal afterwards or `uvx` will not be on PATH yet.

2. **Install the addon.** Download `addon.py` from the repo, then in Blender:
   `Edit > Preferences > Add-ons > Install from Disk`, pick the file, and **tick
   its checkbox** — installing does not enable it. Watch that your browser saved
   it as `addon.py` and not `addon.py.txt`.

3. **Register the server, from git — not PyPI.** This is the part that matters:
   ```
   claude mcp add blender -- uvx --from git+https://github.com/ahujasid/blender-mcp blender-mcp
   ```
   Run it **from the repository folder**. The server is registered per project,
   so a session started anywhere else gets no Blender tools at all.

4. **Verify the command string** before starting anything:
   ```
   claude mcp list
   ```
   It must end in `blender-mcp` with nothing after it. Typing the next command
   on the same line silently registers something like `blender-mcpclaude`, which
   then fails in a way that looks like a much deeper problem.

5. **Connect from Blender.** In the 3D viewport press **N**, open the
   **BlenderMCP** tab, and click **Connect to MCP server**. It should then read
   "Running on port 9876". Leave the four asset-service checkboxes off; none are
   needed and Poly Haven is documented as unreliable.

6. **Start Claude Code from the repo folder** and test with the smallest
   possible call before anything real:
   > use blender to run print("ping")

## Why it has to come from git

`uvx blender-mcp` pulls the PyPI release, which lags `addon.py` from GitHub
master. When the two disagree the failure is thoroughly misleading:

- `claude mcp list` and `/mcp` both report **connected, 22 tools**
- every actual call hangs about **40 seconds** and returns
  `Incomplete JSON response received`
- Blender's console shows the addon registering and **nothing else** — commands
  arrive but never execute
- a trivial `print("ping")` fails exactly like a full glb import, so it does not
  look import-specific either

Installing the server from the same source as the addon makes both halves speak
the same protocol and the whole class of symptom disappears.

## Things that look like the problem and are not

Recording the dead ends, because each one cost real time and each one is easy to
try again:

- **`MCP_TIMEOUT`.** Raising it (`.claude/settings.json`) takes the server from
  `failed` to `connected`, which reads like progress but only masks the
  mismatch — the tools still do not work. The file is kept because a longer
  startup allowance is harmless, not because it fixes anything.
- **The Python version.** Pinning `--python 3.11` changes nothing; 3.14 and 3.11
  stall identically (39.6s vs 40.0s on the same handshake).
- **The Blender version.** Verified working on **Blender 5.2**, so there is no
  need to install an old LTS. An addon that is merely incompatible registers
  without complaint, so "no traceback" does not rule version trouble out — but
  here it genuinely was not the cause.

## Diagnosing, when it does break

Read **both** sides. The terminal only shows the MCP server; the addon's own
errors go to Blender's console, which is hidden by default:

`Window > Toggle System Console`

That console is the only way to tell "the command reached Blender and ran" from
"the command reached Blender and vanished" — and those two need completely
different fixes. Watch for `Executing handler for execute_code` followed by
`Handler execution complete`, which is what success looks like.

Also expect **the first call after startup to fail and the retry to succeed**.
That is a known rough edge, not a broken setup.

## While working

- Save `.blend` files to a scratch folder, never into `models/`. The repository
  should only ever gain the exported `.glb`.
- Only one client can hold the addon's socket. If you have run
  `uvx blender-mcp` by hand to debug, Ctrl+C it before starting Claude Code, or
  Claude Code cannot get in.
- `execute_blender_code` runs arbitrary Python inside Blender. That is the
  mechanism, so it cannot be avoided — just know that connecting grants it.

For the goblin specifically, read [goblin-rig.md](goblin-rig.md) first. It has
the bone map, the mesh's structure, and the traps that have already been paid
for once.
