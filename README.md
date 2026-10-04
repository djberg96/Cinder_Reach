# Cinder Reach

A browser implementation of the Cinder Reach solo deck-building prototype. Govern Ark-9 for ten cycles: build the colony deck, survey and colonize worlds, answer political crises, and prepare for the Silent Fleet.

## Run locally

Requirements: Ruby 4.0 and Rails 8.1.

```sh
bin/setup
bin/rails server
```

Then open <http://localhost:3000>. Runs are saved in SQLite and can be continued from the landing page.

## Game flow

Each cycle has four phases:

1. Draw six cards from the twelve-card starter deck and assign two as Commands. Their abilities and crisis tags activate; the remaining four become Support and generate resources.
2. Take two actions in any combination: buy, survey (and optionally colonize), research, or purge. Supply pays for cards and colonies. Data pays for surveys and research, and banks between cycles. A surveyed world remains charted, so later visits skip its survey cost and reward.
3. Resolve the visible crisis. Only the two Command cards' tags provide cover.
4. Clean up, normally lose unspent Supply, and draw six cards. Banked Data remains.

Win immediately by reaching four Colonies before the Fleet lands, or finish cycle ten with at least two Colonies. Stability 0 is a loss. Fleet 5 is a loss unless two Colonies and the Defense Grid are online.

Research unlocks a branching lattice of twenty technologies across Navigation, Industry, Civics, and Defense. Each doctrine offers mutually exclusive specializations and a capstone. Upgrades cost Data and require matching Command tags, so both deck composition and the cards committed to Command determine which strategic paths are open.

## Verification

```sh
bin/rails test
RUBOCOP_CACHE_ROOT=/tmp/cinder-rubocop-cache bin/rubocop
bundle exec brakeman -q
```

The original printable rules and cards remain in `Documents/`.
