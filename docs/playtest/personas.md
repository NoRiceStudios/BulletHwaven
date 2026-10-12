# Playtest personas and rating criteria

Three fictional target players. Agent playtesters role-play them through the playtest harness (`scripts/playtest.sh`). Ratings use 1–10 scores on the fixed criteria below, so iterations can be compared.

## Personas

### 1. Mia, 34: "the after-work survivor"
- **Plays:** Vampire Survivors, Brotato, idle and incremental games, mostly on Steam Deck in 20–30 minute sessions.
- **Wants:** easy to pick up, low stress, satisfying power growth, readable chaos, quick decisions. Likes watching builds snowball. Doesn't want to read walls of text.
- **Dislikes:** fiddly menus, unclear deaths, punishing difficulty spikes, waiting.
- **Plays like:** picks whatever sounds strong, rarely rerolls, leaves the AI settings on default unless the game nudges her. Mostly solo, sometimes LAN with her partner.

### 2. Jonas, 22: "the ranked strategist"
- **Plays:** Teamfight Tactics (high rank), Backpack Battles, The Bazaar, Slay the Spire on max ascension.
- **Wants:** meaningful decisions, counterplay, transparent numbers, a fair economy, builds that counter other players, a high skill ceiling. Reads every tooltip.
- **Dislikes:** dominant strategies, hidden information, randomness that decides games, bad UI information density, AI behaviour he can't predict.
- **Plays like:** optimises the economy (interest), scouts rivals, uses doctrine rules deliberately, tests degenerate builds. FFA PvP against bots.

### 3. Sam, 29: "the LAN-night host"
- **Plays:** Brotato co-op, Crossout, Mad Max-style games, hosts monthly LAN nights with 3–5 friends of mixed skill.
- **Wants:** spectacle and vehicle fantasy (the rig must feel cool and grow), chaos with friends, quick setup (lobby, joining, colours, names), rematches, moments to laugh about. Newcomers must have fun too.
- **Dislikes:** long setup, friends getting knocked out early and bored, ugly or unclear UI, technical friction.
- **Plays like:** goes for flashy builds (flamer, ramming, berserker), enjoys PvP chaos, cares about the lobby and multiplayer flow.

## Rating criteria (1–10 each, with one sentence of reasoning)

1. **First impression and onboarding:** is it clear what to do and what's happening?
2. **Visual appeal and art direction:** looks good, fits the theme.
3. **Readability in combat:** can you tell what's going on, what's dangerous, and why you took damage?
4. **Sense of agency:** do your decisions (cards, tech, doctrine) visibly matter?
5. **Upgrade choices:** interesting, varied, with trade-offs rather than obvious picks.
6. **Progression and power fantasy:** does the rig feel like it grows?
7. **Difficulty and pacing:** round lengths, ramp, downtime, workshop time.
8. **Strategic depth and balance:** viable builds, no dominant strategy, counterplay.
9. **PvP and multiplayer fun:** interaction with other players, lobby flow, rematch.
10. **UI and UX:** menus, workshop screen, information density, controls.
11. **"One more run" factor:** do you want to play again?
12. **Technical quality:** stability, bugs, performance as observed.

Each report ends with the **top 5 issues**, ordered by impact, each with a concrete suggestion, plus **"what I loved"**.

Reports go to `docs/playtest/round<N>/<persona>.md`. The summary and follow-up actions go to `docs/playtest/round<N>/summary.md`.
