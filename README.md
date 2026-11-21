# Bumpball 24/7 Free GitHub Actions Bot Trainer

Train `src/server/BotWeights.luau` continuously on free public GitHub Actions runners (no credit card required) while keeping your main Bumpball repository private.

## 6-Step Setup

1. **Create a new *public* GitHub repository** (e.g., `bumpball-bot-trainer`). Public repos get unlimited free standard GitHub Actions minutes.
2. **Copy only the minimal simulation & trainer files** into that repo (no art, UI, or private game scripts):
   - `src/shared/BobblePhysics.luau`
   - `src/shared/BobbleRoster.luau`
   - `src/shared/KickoffFormations.luau`
   - `src/shared/PowerPlays.luau`
   - `src/shared/PrototypeRound.luau`
   - `src/server/BotWeights.luau`
   - `src/server/BotBrain.luau`
   - `scripts/train-bot.luau`
3. **Copy the workflow file** `scripts/github-trainer/train-bot.yml` into `.github/workflows/train-bot.yml` in the public trainer repo.
4. **Push to `main`**. In GitHub, open **Settings -> Actions -> General -> Workflow permissions**, enable **Read and write permissions**, and save.
5. **Trigger the first run** in the **Actions** tab (`Bumpball Bot Self-Play Trainer` -> **Run workflow**). Every 6 hours the workflow resumes from `checkpoint.json`, trains for ~280 minutes via symmetric side-swapped self-play against a champion league, and commits improvements back to `src/server/BotWeights.luau` + `checkpoint.json`.
6. **Pull trained weights back into `Z:\Bumpball 2`**:
   Download or copy `src/server/BotWeights.luau` from the trainer repo into `Z:\Bumpball 2\src\server\BotWeights.luau`, then run `./scripts/verify.ps1` to verify and build.

## Local Smoke Test

```powershell
& "$env:USERPROFILE\.rokit\bin\lune.exe" run scripts/train-bot.luau -- --generations 1 --matches 2 --dry-run
```
