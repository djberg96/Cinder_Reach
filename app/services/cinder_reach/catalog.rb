module CinderReach
  module Catalog
    CARDS = {
      "colonist" => { name: "Colonist", tag: "COLONY", supply: 1, kind: "starter", text: "+1 Supply." },
      "militia" => { name: "Militia", tag: "FLEET", supply: 1, kind: "starter", text: "+1 Supply." },
      "charter" => { name: "Charter", tag: "DECREE", supply: 2, kind: "starter", text: "+2 Supply." },
      "outpost" => { name: "Outpost", tag: "COLONY", supply: 2, kind: "side", text: "+2 Supply. Colony site." },
      "unrest" => { name: "Unrest", tag: nil, supply: 0, kind: "unrest", text: "Dead weight. Scrap only by card effects." },
      "survey_skiff" => { name: "Survey Skiff", tag: "SURVEY", supply: 2, cost: 2, text: "+2 Supply. Your survey this cycle costs 1 less." },
      "habitat_ring" => { name: "Habitat Ring", tag: "COLONY", supply: 2, cost: 3, text: "+2 Supply." },
      "decree" => { name: "Decree", tag: "DECREE", supply: 1, cost: 2, text: "+1 Supply. Scrap an Unrest from hand, play, or discard." },
      "embassy" => { name: "Embassy", tag: "DECREE", supply: 2, cost: 3, text: "+2 Supply. Stability +1." },
      "militia_wing" => { name: "Militia Wing", tag: "FLEET", supply: 2, cost: 3, text: "+2 Supply. Intercept." },
      "field_lab" => { name: "Field Lab", tag: "LAB", supply: 2, cost: 4, text: "+2 Supply. Your next buy this cycle costs 1 less." },
      "foundry" => { name: "Foundry", tag: "COLONY", supply: 3, cost: 4, text: "+3 Supply." },
      "listener_array" => { name: "Listener Array", tag: "SURVEY", supply: 2, cost: 4, text: "+2 Supply. Look at the top crisis; you may put it on the bottom." },
      "gene_vault" => { name: "Gene Vault", tag: "LAB", supply: 2, cost: 5, text: "+2 Supply. Draw 1." },
      "gunship" => { name: "Gunship", tag: "FLEET", supply: 3, cost: 5, text: "+3 Supply. Fleet −1. Intercept." },
      "arcology" => { name: "Arcology", tag: "COLONY", supply: 4, cost: 6, text: "+4 Supply. Stability +1." },
      "defense_grid" => { name: "Defense Grid", tag: "LAB", supply: 2, cost: 6, text: "+2 Supply. Switch the Grid on. Intercept." }
    }.freeze

    MARKET_COUNTS = {
      "survey_skiff" => 3, "habitat_ring" => 3, "decree" => 3,
      "embassy" => 2, "militia_wing" => 2, "field_lab" => 2,
      "foundry" => 2, "listener_array" => 1, "gene_vault" => 1,
      "gunship" => 2, "arcology" => 1, "defense_grid" => 1
    }.freeze

    WORLDS = {
      "rust_mesa" => { name: "Rust Mesa", survey: 2, colony: 5, survey_text: "+2 Supply", colony_text: "Outpost · Stability +1", flavor: "Iron dust veils a patient, buried biosphere." },
      "glass_sea" => { name: "Glass Sea", survey: 1, colony: 4, survey_text: "Draw 1", colony_text: "Outpost", flavor: "A frozen ocean rings beneath the survey lights." },
      "pale_garden" => { name: "Pale Garden", survey: 2, colony: 4, survey_text: "Stability +1", colony_text: "Outpost · Scrap an Unrest", flavor: "Something tends these colorless groves." },
      "red_choir" => { name: "Red Choir", survey: 2, colony: 5, survey_text: "Fleet −1", colony_text: "Outpost", flavor: "Radio storms sing in a language the Fleet fears." },
      "vault_orbit" => { name: "Vault Orbit", survey: 3, colony: 6, survey_text: "Next Lab costs 2 less", colony_text: "Outpost · Draw 1", flavor: "A dead civilization left one door unlocked." },
      "black_relay" => { name: "Black Relay", survey: 3, colony: 6, survey_text: "Reorder the next 2 crises", colony_text: "Outpost · Grid on or Fleet −1", flavor: "Its signal arrives before it is transmitted." }
    }.freeze

    CRISES = {
      "ration_riot" => { name: "Ration Riot", text: "Unless 2 COLONY tags are in play: Stability −1 and gain 1 Unrest.", threat: "COUNCIL" },
      "admiralty_demand" => { name: "Admiralty Demand", text: "Unless a FLEET tag is in play: Fleet +1.", threat: "FLEET" },
      "consortium_embargo" => { name: "Consortium Embargo", text: "Unless a DECREE tag is in play: Stability −1.", threat: "COUNCIL" },
      "silent_ping" => { name: "Silent Ping", text: "Fleet +1.", threat: "SIGNAL" },
      "council_fracture" => { name: "Council Fracture", text: "Unless a DECREE tag is in play: Stability −1 and gain 1 Unrest.", threat: "COUNCIL" },
      "harvest_blight" => { name: "Harvest Blight", text: "Scrap a card from hand, or Stability −1.", threat: "COLONY" },
      "probe_swarm" => { name: "Probe Swarm", text: "Unless a FLEET tag is in play: Fleet +1. If Fleet is then 3+, Stability −1.", threat: "FLEET" },
      "refugee_wave" => { name: "Refugee Wave", text: "Gain 1 Unrest, then draw 1.", threat: "COLONY" },
      "deep_signal" => { name: "Deep Signal", text: "See the next crisis. Then Fleet +1, unless you scrap a card from hand.", threat: "SIGNAL" },
      "beacon_flicker" => { name: "Beacon Flicker", text: "If you have fewer than 2 Colonies: Stability −1 and Fleet +1.", threat: "SIGNAL" }
    }.freeze

    module_function

    def card(key) = CARDS.fetch(key)
    def world(key) = WORLDS.fetch(key)
    def crisis(key) = CRISES.fetch(key)

    def expanded(counts)
      counts.flat_map { |key, count| [ key ] * count }
    end
  end
end
