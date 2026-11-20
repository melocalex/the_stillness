# THE STILLNESS

A cozy survival horror game for Roblox. You live in your grandfather's cabin
by a lake outside Pinehaven, a mountain town that went quiet. By day you
gather, repair and explore. At night you close the curtains, keep the fire
low, and keep Caramelo, your dog, close. Something is outside. You are home.

The horror exists to make the comfort mean something: the core loop is
building a safe, warm life in a world that is not safe.

## Run it

You need macOS or Windows with [Roblox Studio](https://create.roblox.com/)
(signed in with a Roblox account) and the toolchain below.

```bash
brew install rojo stylua selene lune luau
```

```bash
./scripts/setup.sh
```

```bash
./scripts/check.sh
```

`check.sh` formats, lints, type-checks (strict Luau), runs the unit tests and
builds `build/TheStillness.rbxlx`. Open that file in Studio and press
**Test > Start Test Session > Test**. The world is generated when the server
starts (a few seconds), then the menu appears; press **Play**.

For live editing, run `rojo serve` and connect the Rojo plugin in Studio
(installed with `rojo plugin install`).

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Shift | Run |
| C | Crouch / sneak |
| H (hold) | Hold your breath |
| Q | Coat on / off (once found) |
| E, F, R | Interact (prompts show which) |
| T | Pet Caramelo |
| G | Dog commands |
| I | Pack |
| J | Journal |
| B | Build mode (R rotates, click places, X cancels) |
| Mouse wheel | Zoom while looking out of a window |

## What is in the prototype

See [STATUS.md](STATUS.md) for what is implemented, what has been verified in
Studio, and what is still open. Design notes live in [docs/](docs/).

## Repository layout

| Path | Contents |
| --- | --- |
| `src/server` | Server scripts: world generation, gameplay services, creatures |
| `src/client` | Client scripts: UI, input, camera, weather, audio |
| `src/shared` | Config (pure data), pure gameplay logic, remotes |
| `tests` | Lune unit tests for `src/shared/Logic` |
| `assets` | Vetted Creator Store models (`StillnessAssets.rbxm`) |
| `tools` | Asset search, extraction and Studio helper scripts |
| `docs` | Design, architecture, development, testing, asset licenses |
