module CinderReach
  module Catalog
    CARDS = {
      "colonist" => { name: "Colonist", tag: "COLONY", supply: 1, data: 0, kind: "starter", command_text: "Colonization costs 1 less this cycle." },
      "survey_probe" => { name: "Survey Probe", tag: "SURVEY", supply: 0, data: 1, kind: "starter", command_text: "Surveying costs 1 less Data this cycle." },
      "militia" => { name: "Militia", tag: "FLEET", supply: 1, data: 0, kind: "starter", command_text: "Deploy a FLEET tag against the incoming crisis." },
      "charter" => { name: "Charter", tag: "DECREE", supply: 1, data: 1, kind: "starter", command_text: "The next Reach card costs 1 less this cycle." },
      "outpost" => { name: "Outpost", tag: "COLONY", supply: 2, data: 0, kind: "side", command_text: "Colonization costs 1 less this cycle." },
      "unrest" => { name: "Unrest", tag: nil, supply: 0, data: 0, kind: "unrest", command_text: "No command effect. It can only be removed by special effects." },
      "survey_skiff" => { name: "Survey Skiff", tag: "SURVEY", supply: 1, data: 2, cost: 2, command_text: "Surveying costs 1 less Data this cycle." },
      "habitat_ring" => { name: "Habitat Ring", tag: "COLONY", supply: 2, data: 0, cost: 3, command_text: "Colonization costs 1 less this cycle." },
      "decree" => { name: "Decree", tag: "DECREE", supply: 0, data: 2, cost: 2, command_text: "Scrap an Unrest from your deck." },
      "embassy" => { name: "Embassy", tag: "DECREE", supply: 1, data: 1, cost: 3, command_text: "Stability +1." },
      "militia_wing" => { name: "Militia Wing", tag: "FLEET", supply: 2, data: 0, cost: 3, command_text: "Intercept the first Fleet advance this crisis." },
      "field_lab" => { name: "Field Lab", tag: "LAB", supply: 1, data: 2, cost: 4, command_text: "Your next research costs 1 less Data." },
      "foundry" => { name: "Foundry", tag: "COLONY", supply: 3, data: 0, cost: 4, command_text: "The next Reach card costs 1 less this cycle." },
      "listener_array" => { name: "Listener Array", tag: "SURVEY", supply: 0, data: 3, cost: 4, command_text: "You may send the incoming crisis to the bottom." },
      "gene_vault" => { name: "Gene Vault", tag: "LAB", supply: 1, data: 2, cost: 5, command_text: "Draw 1 card before committing Support." },
      "gunship" => { name: "Gunship", tag: "FLEET", supply: 2, data: 0, cost: 5, command_text: "Fleet −1. Intercept the first Fleet advance this crisis." },
      "arcology" => { name: "Arcology", tag: "COLONY", supply: 3, data: 1, cost: 6, command_text: "Stability +1 and colonization costs 1 less." },
      "defense_grid" => { name: "Defense Grid", tag: "LAB", supply: 1, data: 2, cost: 6, command_text: "Switch the Grid on and gain Intercept." }
    }.freeze

    MARKET_COUNTS = {
      "survey_skiff" => 3, "habitat_ring" => 3, "decree" => 3,
      "embassy" => 2, "militia_wing" => 2, "field_lab" => 2,
      "foundry" => 2, "listener_array" => 1, "gene_vault" => 1,
      "gunship" => 2, "arcology" => 1, "defense_grid" => 1
    }.freeze

    WORLDS = {
      "rust_mesa" => { name: "Rust Mesa", survey: 2, colony: 5, survey_text: "+2 Supply", colony_text: "Outpost · Stability +1", flavor: "Iron dust veils a patient, buried biosphere." },
      "glass_sea" => { name: "Glass Sea", survey: 1, colony: 4, survey_text: "Reinforce Support", colony_text: "Outpost", flavor: "A frozen ocean rings beneath the survey lights." },
      "pale_garden" => { name: "Pale Garden", survey: 2, colony: 4, survey_text: "Stability +1", colony_text: "Outpost · Scrap an Unrest", flavor: "Something tends these colorless groves." },
      "red_choir" => { name: "Red Choir", survey: 2, colony: 5, survey_text: "Fleet −1", colony_text: "Outpost", flavor: "Radio storms sing in a language the Fleet fears." },
      "vault_orbit" => { name: "Vault Orbit", survey: 3, colony: 6, survey_text: "Next Lab costs 2 less", colony_text: "Outpost · Reinforce Support", flavor: "A dead civilization left one door unlocked." },
      "black_relay" => { name: "Black Relay", survey: 3, colony: 6, survey_text: "Reorder the next 2 crises", colony_text: "Outpost · Grid on or Fleet −1", flavor: "Its signal arrives before it is transmitted." }
    }.freeze

    CRISES = {
      "ration_riot" => { name: "Ration Riot", text: "Unless 2 COLONY tags are in command: Stability −1 and gain 1 Unrest.", threat: "COUNCIL" },
      "admiralty_demand" => { name: "Admiralty Demand", text: "Unless a FLEET tag is in command: Fleet +1.", threat: "FLEET" },
      "consortium_embargo" => { name: "Consortium Embargo", text: "Unless a DECREE tag is in command: Stability −1.", threat: "COUNCIL" },
      "silent_ping" => { name: "Silent Ping", text: "Fleet +1.", threat: "SIGNAL" },
      "council_fracture" => { name: "Council Fracture", text: "Unless a DECREE tag is in command: Stability −1 and gain 1 Unrest.", threat: "COUNCIL" },
      "harvest_blight" => { name: "Harvest Blight", text: "Scrap a card from the table, or Stability −1.", threat: "COLONY" },
      "probe_swarm" => { name: "Probe Swarm", text: "Unless a FLEET tag is in command: Fleet +1. If Fleet is then 3+, Stability −1.", threat: "FLEET" },
      "refugee_wave" => { name: "Refugee Wave", text: "Gain 1 Unrest, then reinforce Support.", threat: "COLONY" },
      "deep_signal" => { name: "Deep Signal", text: "See the next crisis. Then Fleet +1, unless you scrap a card from the table.", threat: "SIGNAL" },
      "beacon_flicker" => { name: "Beacon Flicker", text: "If you have fewer than 2 Colonies: Stability −1 and Fleet +1.", threat: "SIGNAL" }
    }.freeze

    TECH_TREES = {
      "navigation" => {
        name: "Navigation", symbol: "⌁", tags: %w[SURVEY LAB],
        nodes: [
          { key: "nav_probes", name: "Long-range Probes", cost: 2, tags: 1, text: "All surveys cost 1 less Data." },
          { key: "nav_xenology", name: "Xenology Corps", cost: 4, tags: 1, parent: "nav_probes", exclusive: "nav_route", text: "First-time surveys recover 1 Data." },
          { key: "nav_gateways", name: "Gate Cartography", cost: 4, tags: 1, parent: "nav_probes", exclusive: "nav_route", text: "All colonies cost 1 less Supply." },
          { key: "nav_living_atlas", name: "Living Atlas", cost: 7, tags: 2, parent: "nav_xenology", text: "Begin each cycle with Data for charted worlds, up to 3." },
          { key: "nav_slipstream", name: "Slipstream Doctrine", cost: 7, tags: 2, parent: "nav_gateways", text: "Your first world action each cycle is free." }
        ]
      },
      "industry" => {
        name: "Industry", symbol: "⬡", tags: %w[COLONY LAB],
        nodes: [
          { key: "ind_salvage", name: "Salvage Economy", cost: 2, tags: 1, text: "Reach cards cost 1 less Supply." },
          { key: "ind_automation", name: "Closed-loop Works", cost: 4, tags: 1, parent: "ind_salvage", exclusive: "ind_route", text: "Bank up to 2 unspent Supply between cycles." },
          { key: "ind_precision", name: "Precision Logistics", cost: 4, tags: 1, parent: "ind_salvage", exclusive: "ind_route", text: "Purchased cards go on top of your deck." },
          { key: "ind_replicator", name: "Matter Replicator", cost: 7, tags: 2, parent: "ind_automation", text: "Begin each cycle with 3 additional Supply." },
          { key: "ind_forge", name: "Orbital Forge", cost: 7, tags: 2, parent: "ind_precision", text: "Your first purchase each cycle is a free action." }
        ]
      },
      "civics" => {
        name: "Civics", symbol: "◇", tags: %w[DECREE COLONY],
        nodes: [
          { key: "civ_mesh", name: "Civic Mesh", cost: 2, tags: 1, text: "Prevent the first Unrest gained each cycle." },
          { key: "civ_consensus", name: "Consensus Engine", cost: 4, tags: 1, parent: "civ_mesh", exclusive: "civ_route", text: "Prevent the first Stability loss each cycle." },
          { key: "civ_frontier", name: "Frontier Compact", cost: 4, tags: 1, parent: "civ_mesh", exclusive: "civ_route", text: "Colonizing grants 1 Data and 1 Stability." },
          { key: "civ_unity", name: "Unity Protocol", cost: 7, tags: 2, parent: "civ_consensus", text: "A DECREE Command also counts as COLONY and FLEET." },
          { key: "civ_beacon", name: "Beacon Commonwealth", cost: 7, tags: 2, parent: "civ_frontier", text: "Begin each cycle with 1 Supply per colony." }
        ]
      },
      "defense" => {
        name: "Defense", symbol: "✦", tags: %w[FLEET LAB],
        nodes: [
          { key: "def_analysis", name: "Signal Analysis", cost: 2, tags: 1, text: "See one crisis beyond the incoming signal." },
          { key: "def_patrol", name: "Patrol Doctrine", cost: 4, tags: 1, parent: "def_analysis", exclusive: "def_route", text: "Any FLEET Command gains Intercept." },
          { key: "def_fortress", name: "Fortress Protocol", cost: 4, tags: 1, parent: "def_analysis", exclusive: "def_route", text: "Bring the Defense Grid online." },
          { key: "def_hunters", name: "Hunter Groups", cost: 7, tags: 2, parent: "def_patrol", text: "Your first FLEET Command each cycle reduces Fleet by 1." },
          { key: "def_aegis", name: "Aegis Network", cost: 7, tags: 2, parent: "def_fortress", text: "The Grid can hold Fleet 5 with only one colony." }
        ]
      }
    }.freeze

    module_function

    def card(key) = CARDS.fetch(key)
    def world(key) = WORLDS.fetch(key)
    def crisis(key) = CRISES.fetch(key)
    def tech_tree(key) = TECH_TREES.fetch(key)

    def tech_node(key)
      TECH_TREES.each_value do |tree|
        node = tree[:nodes].find { |candidate| candidate[:key] == key.to_s }
        return node.merge(tree_name: tree[:name], tree_tags: tree[:tags], tree_symbol: tree[:symbol]) if node
      end
      nil
    end

    def expanded(counts)
      counts.flat_map { |key, count| [ key ] * count }
    end
  end
end
