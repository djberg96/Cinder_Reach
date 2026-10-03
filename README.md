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

1. Play any cards from your hand to gain Supply and activate effects.
2. Take one main action: buy, survey (and optionally colonize), or purge.
3. Reveal and resolve one crisis. The tags on played cards provide cover.
4. Clean up, lose unspent Supply, and draw five cards.

Win immediately by reaching four Colonies before the Fleet lands, or finish cycle ten with at least two Colonies. Stability 0 is a loss. Fleet 5 is a loss unless two Colonies and the Defense Grid are online.

## Verification

```sh
bin/rails test
RUBOCOP_CACHE_ROOT=/tmp/cinder-rubocop-cache bin/rubocop
bundle exec brakeman -q
```

The original printable rules and cards remain in `Documents/`.
