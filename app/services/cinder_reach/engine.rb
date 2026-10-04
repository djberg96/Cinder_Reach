module CinderReach
  class Engine
    attr_reader :game, :state

    COMMAND_LIMIT = 2
    ACTION_LIMIT = 2
    COLONY_GOAL = 5
    OUTER_COLONY_GOAL = 2

    def self.build_event_deck(difficulty)
      grouped = Catalog::EVENTS.keys.group_by { |key| Catalog.event(key)[:tone] }
      cards = case difficulty.to_s
      when "prospect"
        grouped.fetch("opportunity") + grouped.fetch("dilemma") + grouped.fetch("hazard").sample(2)
      when "silent"
        grouped.fetch("opportunity").sample(2) + grouped.fetch("dilemma") + grouped.fetch("hazard")
      else
        grouped.fetch("opportunity").sample(3) + grouped.fetch("dilemma") + grouped.fetch("hazard").sample(2)
      end
      cards.shuffle
    end

    def self.start!(difficulty: "mandate")
      difficulty = difficulty.to_s
      raise InvalidMove, "Unknown difficulty" unless %w[prospect mandate silent].include?(difficulty)

      market = Catalog.expanded(Catalog::MARKET_COUNTS).shuffle
      inner_worlds = Catalog::WORLDS.keys.select { |key| Catalog.world(key)[:ring] == "inner" }.shuffle
      outer_worlds = Catalog::WORLDS.keys.select { |key| Catalog.world(key)[:ring] == "outer" }.shuffle
      crises = Catalog::CRISES.keys.shuffle
      if difficulty == "silent"
        crises.delete("silent_ping")
        crises.unshift("silent_ping")
      end

      starter = ([ "colonist" ] * 4 + [ "survey_probe" ] * 3 + [ "militia" ] * 3 + [ "charter" ] * 2).shuffle
      event_deck = build_event_deck(difficulty)
      cycle_limit = difficulty == "prospect" ? 10 : 8
      state = {
        "rules_version" => 4,
        "cycle" => 1, "watch" => 1, "stability" => difficulty == "prospect" ? 6 : 5,
        "fleet" => difficulty == "silent" ? 1 : 0, "colonies" => 0,
        "colonized_worlds" => [], "cycle_limit" => cycle_limit,
        "grid" => false, "held" => false, "supply" => 0, "data" => 0, "actions" => ACTION_LIMIT,
        "unlocked_tech" => [],
        "deck" => starter.drop(6), "hand" => starter.first(6), "discard" => [], "played" => [], "support" => [], "prepared" => [], "scrapped" => [],
        "market_deck" => market.drop(4), "reach" => market.first(4),
        "inner_deep" => inner_worlds.drop(2), "outer_deep" => outer_worlds.drop(1),
        "deep" => inner_worlds.drop(2) + outer_worlds.drop(1),
        "system" => inner_worlds.first(2) + outer_worlds.first(1), "surveyed_worlds" => [],
        "crisis_deck" => crises.drop(1), "crisis_discard" => [], "incoming_crisis" => crises.first, "current_crisis" => nil,
        "event_deck" => event_deck, "event_discard" => [], "current_event" => nil,
        "phase" => "command", "surveyed_world" => nil, "surveyed_this_action" => false, "pending_effect" => nil,
        "outer_survey_pending_completion" => false,
        "buy_discount" => 0, "survey_discount" => 0, "colony_discount" => 0, "research_discount" => 0,
        "vault_discount" => false, "intercept_used" => false, "stability_guard_used" => false,
        "unrest_guard_used" => false, "hunter_used" => false, "world_action_used" => false,
        "glimpse" => nil, "log" => [ "Cycle 1 · Watch I begins. Choose two Commands." ], "outcome" => nil
      }
      Game.create!(difficulty: difficulty, status: "playing", state: state)
    end

    def initialize(game)
      @game = game
      @state = game.state
      normalize_state!
    end

    def card(key) = Catalog.card(key)
    def world(key) = Catalog.world(key)
    def crisis(key) = Catalog.crisis(key)
    def playing? = game.status == "playing"
    def phase = state["phase"]
    def tech?(key) = state["unlocked_tech"].include?(key.to_s)
    def cycle_limit = state["cycle_limit"]
    def colony_goal = COLONY_GOAL
    def outer_colony_goal = OUTER_COLONY_GOAL
    def colony_count = [ state["colonies"].to_i, COLONY_GOAL ].min
    def colony_capacity_reached? = colony_count >= COLONY_GOAL
    def outer_colonies = state["colonized_worlds"].count { |key| world(key)[:ring] == "outer" }
    def completed_doctrines = state["unlocked_tech"] & Catalog::DOCTRINE_KEYS
    def doctrine_complete? = completed_doctrines.any?
    def mandate_met? = colony_capacity_reached? && outer_colonies >= OUTER_COLONY_GOAL && doctrine_complete?

    def world_accessible?(key)
      Array(world(key)[:requires_all]).all? { |tech| tech?(tech) }
    end

    def world_access_names(key)
      Array(world(key)[:requires_all]).map { |tech| Catalog.tech_node(tech)[:name] }
    end

    def tags
      tags_for(state["played"])
    end

    def crisis_tags
      tags_for(state["prepared"] + state["played"])
    end

    def crisis_defended?(key = state["incoming_crisis"])
      case key.to_s
      when "ration_riot"
        crisis_tags.count("COLONY") >= 2
      when "admiralty_demand", "probe_swarm"
        crisis_tags.include?("FLEET")
      when "consortium_embargo", "council_fracture"
        crisis_tags.include?("DECREE")
      when "beacon_flicker"
        state["colonies"] >= 2
      else
        false
      end
    end

    def crisis_averted?(key = state["incoming_crisis"])
      crisis_defended?(key) && (key.to_s != "probe_swarm" || state["fleet"] < 3)
    end

    def tags_for(cards)
      result = cards.filter_map { |key| card(key)[:tag] }
      result += %w[COLONY FLEET] if tech?("civ_unity") && result.include?("DECREE")
      result
    end

    def tech_level(tree_key)
      Catalog.tech_tree(tree_key.to_s)[:nodes].count { |node| tech?(node[:key]) }
    rescue KeyError
      0
    end

    def tech_available?(node_key)
      node = Catalog.tech_node(node_key)
      return false unless node && !tech?(node_key)
      return false if node[:parent] && !tech?(node[:parent])

      !node[:exclusive] || Catalog::TECH_TREES.values.flat_map { |tree| tree[:nodes] }
        .none? { |candidate| candidate[:exclusive] == node[:exclusive] && tech?(candidate[:key]) }
    end

    def matching_tech_tags(node_key)
      node = Catalog.tech_node(node_key)
      return 0 unless node
      tags.count { |tag| node[:tree_tags].include?(tag) }
    end

    def effective_research_cost(node_key)
      node = Catalog.tech_node(node_key)
      node ? [ node[:cost] - state["research_discount"], 0 ].max : 0
    end

    def effective_buy_cost(key)
      info = card(key)
      vault = state["vault_discount"] && info[:tag] == "LAB"
      [ info[:cost] - state["buy_discount"] - (tech?("ind_salvage") ? 1 : 0) - (vault ? 2 : 0), 0 ].max
    end

    def effective_survey_cost(key)
      outer_atlas_discount = world(key)[:ring] == "outer" && tech?("nav_living_atlas") ? 2 : 0
      [ world(key)[:survey] - state["survey_discount"] - (tech?("nav_probes") ? 1 : 0) - outer_atlas_discount, 0 ].max
    end

    def effective_colony_cost(key)
      outer_foundry_discount = world(key)[:ring] == "outer" && tech?("ind_forge") ? 2 : 0
      [ world(key)[:colony] - state["colony_discount"] - (tech?("nav_gateways") ? 1 : 0) - outer_foundry_discount, 0 ].max
    end

    def scrappable_cards
      %w[prepared support played hand].flat_map do |pile|
        state[pile].each_with_index.map { |key, index| [ pile, index, key ] }
      end
    end

    def play_card!(index)
      require_phase!("command")
      require_no_pending!
      raise InvalidMove, "Two Commands are already assigned" if state["played"].length >= COMMAND_LIMIT
      key = state["hand"].delete_at(Integer(index))
      raise InvalidMove, "That card is no longer in your hand" unless key

      state["played"] << key
      log!("Assigned #{card(key)[:name]} as Command #{state['played'].length}.")
      resolve_command!(key)
      commit_support! if state["played"].length == COMMAND_LIMIT && !state["pending_effect"]
      save!
    end

    def play_all!
      play_card!(0) while phase == "command" && state["played"].length < COMMAND_LIMIT && !state["pending_effect"]
      self
    end

    def resolve_listener!(move_to_bottom:)
      require_pending!("listener")
      if move_to_bottom && state["incoming_crisis"] && state["crisis_deck"].any?
        moved = state["incoming_crisis"]
        state["incoming_crisis"] = state["crisis_deck"].shift
        state["crisis_deck"] << moved
        log!("Listener Array sent #{crisis(moved)[:name]} to the bottom.")
      else
        log!("Listener Array left the signal on top.")
      end
      state["pending_effect"] = nil
      state["glimpse"] = nil
      commit_support! if phase == "command" && state["played"].length == COMMAND_LIMIT
      save!
    end

    def buy!(index)
      require_action!
      key = state["reach"][Integer(index)]
      raise InvalidMove, "That Reach slot is empty" unless key
      info = card(key)
      vault = state["vault_discount"] && info[:tag] == "LAB"
      cost = effective_buy_cost(key)
      raise InvalidMove, "You need #{cost} Supply" if state["supply"] < cost

      state["supply"] -= cost
      tech?("ind_precision") ? state["deck"].unshift(key) : state["discard"] << key
      state["reach"][Integer(index)] = state["market_deck"].shift
      state["vault_discount"] = false if vault
      log!("Bought #{info[:name]} for #{cost} Supply.")
      complete_action!(type: "buy")
      save!
    end

    def survey!(index)
      require_action!
      key = state["system"][Integer(index)]
      raise InvalidMove, "That System slot is empty" unless key
      info = world(key)
      unless world_accessible?(key)
        raise InvalidMove, "World access requires #{world_access_names(key).to_sentence(last_word_connector: ' and ')}"
      end

      if state["surveyed_worlds"].include?(key)
        colony_cost = effective_colony_cost(key)
        raise InvalidMove, "You need #{colony_cost} Supply" if state["supply"] < colony_cost
        state["surveyed_world"] = key
        state["surveyed_this_action"] = false
        state["phase"] = "survey_decision"
        log!("Returned to charted #{info[:name]} to establish a colony.")
        save!
        return
      end

      cost = effective_survey_cost(key)
      raise InvalidMove, "You need #{cost} Data" if state["data"] < cost
      data_before = state["data"]
      state["data"] -= cost
      state["surveyed_worlds"] << key
      state["surveyed_world"] = key
      state["surveyed_this_action"] = true
      state["phase"] = "survey_decision"
      log!("Surveyed #{info[:name]} for #{cost} Data (#{data_before} → #{state['data']}).")
      resolve_survey_reward!(key)
      if tech?("nav_xenology")
        data_before = state["data"]
        state["data"] += 1
        log!("Xenology Corps recovered 1 Data (#{data_before} → #{state['data']}).")
      end
      if info[:ring] == "outer"
        log!("#{info[:name]} is charted. Outer worlds require a later action to colonize.")
        if state["pending_effect"]
          state["outer_survey_pending_completion"] = true
        else
          finish_outer_survey_action!
        end
      end
      save!
    end

    def arrange_crises!(top_index)
      require_pending!("black_relay")
      pair = [ state["incoming_crisis"], state["crisis_deck"].shift ].compact
      chosen = pair.delete_at(Integer(top_index))
      raise InvalidMove, "Choose one of the scanned signals" unless chosen
      state["incoming_crisis"] = chosen
      state["crisis_deck"] << pair.first if pair.first
      state["pending_effect"] = nil
      state["glimpse"] = nil
      log!("Black Relay fixed #{crisis(chosen)[:name]} as the next signal.")
      finish_outer_survey_action! if state.delete("outer_survey_pending_completion")
      save!
    end

    def colonize!(relay_choice: nil)
      require_phase!("survey_decision")
      require_no_pending!
      raise InvalidMove, "Ark-9 can support only #{COLONY_GOAL} Colonies" if colony_capacity_reached?
      key = state["surveyed_world"]
      info = world(key)
      colony_cost = effective_colony_cost(key)
      raise InvalidMove, "You need #{colony_cost} Supply" if state["supply"] < colony_cost
      if key == "black_relay" && !%w[grid fleet].include?(relay_choice)
        raise InvalidMove, "Choose the Relay's colony benefit"
      end

      supply_before = state["supply"]
      state["supply"] -= colony_cost
      supply_after_payment = state["supply"]
      state["discard"] << "outpost"
      state["colonized_worlds"] << key
      state["colonies"] = state["colonized_worlds"].length
      slot = state["system"].index(key)
      if slot
        replacement_deck = info[:ring] == "outer" ? state["outer_deep"] : state["inner_deep"]
        state["system"][slot] = replacement_deck.shift
        sync_deep!
      end
      state["surveyed_worlds"].delete(key)
      state["surveyed_world"] = nil
      state["surveyed_this_action"] = false
      adjust_stability!(1) if key == "rust_mesa"
      scrap_first_unrest! if key == "pale_garden"
      reinforce_support!(1) if key == "vault_orbit"
      if key == "black_relay"
        relay_choice == "grid" ? state["grid"] = true : adjust_fleet!(-1)
      end
      if tech?("civ_frontier")
        state["data"] += 1
        adjust_stability!(1)
      end
      log!("Colonized #{info[:name]} for #{colony_cost} Supply (#{supply_before} → #{supply_after_payment}). Colony #{state['colonies']} is online.")
      check_beacon!
      complete_action!(type: "world") if playing?
      save!
    end

    def resolve_event!(choice:)
      require_phase!("event")
      key = state["current_event"]
      raise InvalidMove, "There is no midwatch event to resolve" unless key
      info = Catalog.event(key)
      choice = choice.to_s
      raise InvalidMove, "Choose how to resolve the event" unless info[:choices].key?(choice)

      case [ key, choice ]
      when [ "salvage_drift", "salvage" ]
        state["supply"] += 2
      when [ "quiet_signal", "archive" ]
        state["data"] += 2
      when [ "fleet_diversion", "observe" ]
        adjust_fleet!(-1)
      when [ "steady_hands", "rally" ]
        adjust_stability!(1)
      when [ "relief_convoy", "receive" ]
        reinforce_support!(1)
      when [ "emergency_levy", "accept" ]
        state["supply"] += 3
        gain_unrest!
      when [ "emergency_levy", "decline" ]
        nil
      when [ "frontier_grant", "supply" ]
        state["supply"] += 3
      when [ "frontier_grant", "data" ]
        state["data"] += 2
      when [ "colonial_petition", "unity" ]
        adjust_stability!(1)
      when [ "colonial_petition", "research" ]
        state["data"] += 1
      when [ "labor_dispute", "stores" ]
        state["supply"] = [ state["supply"] - 2, 0 ].max
      when [ "labor_dispute", "council" ]
        adjust_stability!(-1)
      when [ "data_corruption", "purge" ]
        state["data"] = [ state["data"] - 1, 0 ].max
      when [ "data_corruption", "conceal" ]
        gain_unrest!
      when [ "market_shock", "cycle" ]
        state["market_deck"].concat(state["reach"].compact).shuffle!
        state["reach"] = 4.times.map { state["market_deck"].shift }
      end

      return save! unless playing?
      log!("Midwatch: #{info[:name]} — #{info[:choices][choice]}.")
      state["event_discard"] << key
      state["current_event"] = nil
      begin_second_watch!
      save!
    end

    def pass_colony!
      require_phase!("survey_decision")
      require_no_pending!
      log!("Left #{world(state['surveyed_world'])[:name]} uncolonized; its survey remains charted.")
      state["surveyed_world"] = nil
      state["surveyed_this_action"] = false
      complete_action!(type: "world")
      save!
    end

    def research!(node_key)
      require_action!
      node_key = node_key.to_s
      node = Catalog.tech_node(node_key)
      raise InvalidMove, "Unknown technology" unless node
      raise InvalidMove, "That technology is already online or its branch is closed" unless tech_available?(node_key)
      matching = matching_tech_tags(node_key)
      raise InvalidMove, "You need #{node[:tags]} matching Command tags" if matching < node[:tags]
      cost = effective_research_cost(node_key)
      raise InvalidMove, "You need #{cost} Data" if state["data"] < cost

      state["data"] -= cost
      state["unlocked_tech"] << node_key
      state["research_discount"] = 0
      state["grid"] = true if node_key == "def_fortress"
      log!("#{node[:tree_name]} unlocked #{node[:name]}.")
      check_beacon!
      complete_action!(type: "research") if playing?
      save!
    end

    def purge!(pile, index = nil)
      require_action!
      if index.nil?
        index = pile
        pile = "support"
      end
      pile = pile.to_s
      raise InvalidMove, "Choose a Command or Support card" unless %w[support played].include?(pile)
      key = state[pile][Integer(index)]
      raise InvalidMove, "That card is no longer on the table" unless key
      raise InvalidMove, "Unrest can only be scrapped by card effects" if key == "unrest"

      state[pile].delete_at(Integer(index))
      state["scrapped"] << key
      log!("Purged #{card(key)[:name]} from the deck.")
      complete_action!(type: "purge")
      save!
    end

    def end_actions!
      require_action!
      log!("Ended the action phase with #{state['actions']} action#{'s' unless state['actions'] == 1} unused.")
      state["actions"] = 0
      advance_watch!
      save!
    end

    def resolve_crisis!(choice: nil, card_index: nil, pile: nil)
      require_phase!("crisis")
      key = state["current_crisis"]
      raise InvalidMove, "There is no crisis to resolve" unless key

      case key
      when "ration_riot"
        unless crisis_defended?(key)
          adjust_stability!(-1)
          gain_unrest! if playing?
        end
      when "admiralty_demand"
        adjust_fleet!(1, crisis: true) unless crisis_defended?(key)
      when "consortium_embargo"
        adjust_stability!(-1) unless crisis_defended?(key)
      when "silent_ping"
        adjust_fleet!(1, crisis: true)
      when "council_fracture"
        unless crisis_defended?(key)
          adjust_stability!(-1)
          gain_unrest! if playing?
        end
      when "harvest_blight"
        if choice == "scrap"
          scrap_table_card!(pile, card_index)
        elsif choice == "stability"
          adjust_stability!(-1)
        else
          raise InvalidMove, "Choose a card to scrap or lose Stability"
        end
      when "probe_swarm"
        adjust_fleet!(1, crisis: true) unless crisis_defended?(key)
        adjust_stability!(-1) if state["fleet"] >= 3 && playing?
      when "refugee_wave"
        gain_unrest!
        reinforce_support!(1) if playing?
      when "deep_signal"
        state["glimpse"] = state["crisis_deck"].first(1)
        if choice == "scrap"
          scrap_table_card!(pile, card_index)
        elsif choice == "fleet"
          adjust_fleet!(1, crisis: true)
        else
          raise InvalidMove, "Choose a card to scrap or advance the Fleet"
        end
      when "beacon_flicker"
        unless crisis_defended?(key)
          adjust_stability!(-1)
          adjust_fleet!(1, crisis: true) if playing?
        end
      end

      finish_crisis!(key) if playing?
      save!
    end

    def cleanup!
      require_phase!("cleanup")
      banked_supply = tech?("ind_automation") ? [ state["supply"], 2 ].min : 0
      state["discard"].concat(state["prepared"]).concat(state["played"]).concat(state["support"]).concat(state["hand"])
      state["prepared"] = []
      state["played"] = []
      state["support"] = []
      state["hand"] = []
      state["supply"] = banked_supply
      state["buy_discount"] = 0
      state["survey_discount"] = 0
      state["colony_discount"] = 0
      state["research_discount"] = 0
      state["intercept_used"] = false
      state["stability_guard_used"] = false
      state["unrest_guard_used"] = false
      state["hunter_used"] = false
      state["world_action_used"] = false
      state["glimpse"] = nil
      state["cycle"] += 1
      if state["cycle"] > cycle_limit
        mandate_met? ? win!("Mandate fulfilled. Five colonies and a completed doctrine hold the Reach.") : lose!("The mandate expired before five colonies, two Outer settlements, and a completed doctrine could be secured.")
      else
        draw!(6)
        state["watch"] = 1
        state["actions"] = ACTION_LIMIT
        state["supply"] += 3 if tech?("ind_replicator")
        state["supply"] += colony_count if tech?("civ_beacon")
        adjust_fleet!(-1) if tech?("def_aegis") && state["grid"]
        if state["colonized_worlds"].include?("vault_orbit")
          state["data"] += 1
          log!("Vault Orbit archived +1 Data for the new cycle.")
        end
        if state["colonized_worlds"].include?("red_choir")
          adjust_fleet!(-1)
          log!("Red Choir drew the Silent Fleet away by 1.")
        end
        state["phase"] = "command"
        refresh_intel!
        log!("Cycle #{state['cycle']} · Watch I begins. Choose two Commands.")
      end
      save!
    end

    def score
      owned = state.values_at("deck", "hand", "discard", "prepared", "played", "support").flatten
      colony_count * 3 + state["stability"] + (state["fleet"] <= 1 ? 2 : 0) +
        (state["grid"] ? 2 : 0) + state["unlocked_tech"].length + owned.count { |key| card(key)[:tag] == "LAB" } - owned.count("unrest")
    end

    private

    def finish_outer_survey_action!
      state["surveyed_world"] = nil
      state["surveyed_this_action"] = false
      state["outer_survey_pending_completion"] = false
      complete_action!(type: "world")
    end

    def sync_deep!
      state["deep"] = Array(state["inner_deep"]) + Array(state["outer_deep"])
    end

    def require_action!
      require_phase!("action")
      require_no_pending!
      raise InvalidMove, "No actions remain this Watch" unless state["actions"].positive?
    end

    def commit_support!
      state["support"] = state["hand"]
      state["hand"] = []
      gained_supply = state["support"].sum { |key| card(key)[:supply] }
      gained_data = state["support"].sum { |key| card(key)[:data] }
      state["supply"] += gained_supply
      state["data"] += gained_data
      state["phase"] = "action"
      refresh_intel!
      log!("Committed #{state['support'].length} Support: +#{gained_supply} Supply, +#{gained_data} Data.")
    end

    def resolve_command!(key)
      case key
      when "colonist", "habitat_ring", "outpost"
        state["colony_discount"] += 1
      when "arcology"
        state["colony_discount"] += 1
        adjust_stability!(1)
      when "survey_probe", "survey_skiff"
        state["survey_discount"] += 1
      when "charter", "foundry"
        state["buy_discount"] += 1
      when "decree"
        scrap_first_unrest!
      when "embassy"
        adjust_stability!(1)
      when "field_lab"
        state["research_discount"] += 1
      when "listener_array"
        if state["incoming_crisis"]
          state["pending_effect"] = "listener"
          state["glimpse"] = [ state["incoming_crisis"] ]
        end
      when "gene_vault"
        draw!(1)
      when "gunship"
        adjust_fleet!(-1)
      when "defense_grid"
        state["grid"] = true
      end
      if card(key)[:tag] == "FLEET" && tech?("def_hunters") && !state["hunter_used"]
        state["hunter_used"] = true
        adjust_fleet!(-1)
      end
    end

    def resolve_survey_reward!(key)
      case key
      when "rust_mesa"
        supply_before = state["supply"]
        state["supply"] += 2
        log!("Rust Mesa survey reward: +2 Supply (#{supply_before} → #{state['supply']}).")
      when "glass_sea" then reinforce_support!(1)
      when "pale_garden"
        stability_before = state["stability"]
        adjust_stability!(1)
        log!("Pale Garden survey reward: Stability +1 (#{stability_before} → #{state['stability']}).")
      when "red_choir"
        fleet_before = state["fleet"]
        adjust_fleet!(-1)
        log!("Red Choir survey reward: Fleet −1 (#{fleet_before} → #{state['fleet']}).")
      when "vault_orbit"
        state["vault_discount"] = true
        log!("Vault Orbit survey reward: the next LAB card costs 2 less Supply.")
      when "black_relay"
        state["pending_effect"] = "black_relay"
        state["glimpse"] = [ state["incoming_crisis"], state["crisis_deck"].first ].compact
        log!("Black Relay survey reward: scanned the next 2 crisis signals.")
      end
    end

    def complete_action!(type:)
      free = type == "world" && tech?("nav_slipstream") && !state["world_action_used"]
      state["world_action_used"] = true if type == "world"
      if free
        log!("Technology made that a free action.")
      else
        state["actions"] -= 1
      end
      state["phase"] = "action"
      state["actions"].positive? ? refresh_intel! : advance_watch!
    end

    def advance_watch!
      state["watch"] == 1 ? begin_event! : begin_crisis!
    end

    def begin_event!
      state["actions"] = 0
      state["phase"] = "event"
      state["current_event"] = state["event_deck"].shift
      if state["current_event"]
        info = Catalog.event(state["current_event"])
        log!("Midwatch event: #{info[:name]}.")
      else
        begin_second_watch!
      end
    end

    def begin_second_watch!
      state["discard"].concat(state["support"]).concat(state["hand"])
      state["prepared"].concat(state["played"])
      state["played"] = []
      state["support"] = []
      state["hand"] = []
      %w[buy_discount survey_discount colony_discount research_discount].each { |key| state[key] = 0 }
      state["watch"] = 2
      state["actions"] = ACTION_LIMIT
      state["phase"] = "command"
      draw!(6)
      refresh_intel!
      log!("Cycle #{state['cycle']} · Watch II begins with #{state['supply']} Supply. Choose two Commands.")
    end

    def begin_crisis!
      return unless playing?
      state["phase"] = "crisis"
      state["intercept_used"] = false
      state["current_crisis"] = state["incoming_crisis"]
      state["incoming_crisis"] = state["crisis_deck"].shift
      if state["current_crisis"]
        log!("Incoming: #{crisis(state['current_crisis'])[:name]}.")
        state["glimpse"] = [ state["incoming_crisis"] ].compact if state["current_crisis"] == "deep_signal"
      else
        log!("The crisis deck is empty. The Fleet advances.")
        adjust_fleet!(1, crisis: true)
        state["phase"] = "cleanup" if playing?
      end
    end

    def finish_crisis!(key)
      state["crisis_discard"] << key
      state["current_crisis"] = nil
      state["phase"] = "cleanup"
      log!("#{crisis(key)[:name]} resolved.")
    end

    def adjust_fleet!(amount, crisis: false)
      if amount.positive? && state["held"]
        log!("The Defense Grid holds. Fleet advance ignored.")
        return
      end
      if amount.positive? && crisis && intercept_available? && !state["intercept_used"]
        state["intercept_used"] = true
        log!("Intercept canceled the Fleet advance.")
        return
      end
      state["fleet"] = [ [ state["fleet"] + amount, 0 ].max, 5 ].min
      if state["fleet"] >= 5
        if state["colonies"] >= 2 && state["grid"]
          state["held"] = true
          log!("The Silent Fleet lands. The Grid holds.")
        else
          lose!("The Silent Fleet reached Ark-9 before the colony could hold the landing.")
        end
      end
    end

    def adjust_stability!(amount)
      if amount.negative? && tech?("civ_consensus") && !state["stability_guard_used"]
        state["stability_guard_used"] = true
        log!("Consensus Engine prevented the Stability loss.")
        return
      end
      state["stability"] = [ [ state["stability"] + amount, 0 ].max, 8 ].min
      lose!("The council collapsed. Ark-9 is lost from within.") if state["stability"].zero?
    end

    def intercept_available?
      crisis_commands = state["prepared"] + state["played"]
      special_command = (crisis_commands & %w[militia_wing gunship defense_grid]).any?
      special_command || (tech?("def_patrol") && crisis_tags.include?("FLEET"))
    end

    def gain_unrest!
      if tech?("civ_mesh") && !state["unrest_guard_used"]
        state["unrest_guard_used"] = true
        log!("Civic Mesh prevented Unrest.")
        return
      end
      state["discard"] << "unrest"
      log!("Unrest entered your discard pile.")
    end

    def scrap_first_unrest!
      %w[hand support played prepared discard deck].each do |pile|
        index = state[pile].index("unrest")
        next unless index
        state[pile].delete_at(index)
        state["scrapped"] << "unrest"
        log!("Scrapped an Unrest.")
        return true
      end
      false
    end

    def scrap_table_card!(pile, index)
      raise InvalidMove, "Choose a card from the table" if pile.nil? || index.nil?
      pile = pile.to_s
      raise InvalidMove, "Choose a card from the table" unless %w[prepared support played hand].include?(pile)
      key = state[pile].delete_at(Integer(index))
      raise InvalidMove, "That card is no longer on the table" unless key
      state["scrapped"] << key
      log!("Scrapped #{card(key)[:name]}.")
    end

    def draw!(count)
      count.times do
        drawn = draw_card!
        state["hand"] << drawn if drawn
      end
    end

    def reinforce_support!(count)
      count.times do
        key = draw_card!
        next unless key
        state["support"] << key
        state["supply"] += card(key)[:supply]
        state["data"] += card(key)[:data]
        log!("#{card(key)[:name]} reinforced Support: +#{card(key)[:supply]} Supply, +#{card(key)[:data]} Data.")
      end
    end

    def draw_card!
      if state["deck"].empty? && state["discard"].any?
        state["deck"] = state["discard"].shuffle
        state["discard"] = []
        log!("Shuffled the discard into a new deck.")
      end
      state["deck"].shift
    end

    def refresh_intel!
      deep_intel = tech?("def_analysis") || state["colonized_worlds"].include?("black_relay")
      state["glimpse"] = deep_intel ? [ state["crisis_deck"].first ].compact : nil
    end

    def check_beacon!
      win!("Beacon lock achieved. Five colonies answer through a completed doctrine.") if mandate_met? && state["fleet"] <= 4
    end

    def normalize_state!
      migrate_legacy_state! if state["rules_version"].to_i < 2
      migrate_two_watch_state! if state["rules_version"].to_i < 3
      migrate_frontier_state! if state["rules_version"].to_i < 4
      state["unlocked_tech"] ||= []
      state["support"] ||= []
      state["prepared"] ||= []
      state["watch"] ||= 1
      state["data"] ||= 0
      state["actions"] ||= ACTION_LIMIT
      state["surveyed_worlds"] ||= []
      state["colonized_worlds"] ||= []
      state["cycle_limit"] ||= game.difficulty == "prospect" ? 10 : 8
      state["event_deck"] ||= self.class.build_event_deck(game.difficulty)
      state["event_discard"] ||= []
      state["current_event"] = nil unless state.key?("current_event")
      state["outer_survey_pending_completion"] = false if state["outer_survey_pending_completion"].nil?
      if state["surveyed_world"] && !state["surveyed_worlds"].include?(state["surveyed_world"])
        state["surveyed_worlds"] << state["surveyed_world"]
      end
      %w[buy_discount survey_discount colony_discount research_discount].each { |key| state[key] ||= 0 }
      %w[surveyed_this_action stability_guard_used unrest_guard_used hunter_used world_action_used intercept_used].each do |key|
        state[key] = false if state[key].nil?
      end
      state["incoming_crisis"] = state["crisis_deck"].shift unless state.key?("incoming_crisis")
    end

    def migrate_legacy_state!
      legacy_tech = state["tech"] || {}
      migrations = {
        "expedition" => %w[nav_probes nav_xenology nav_living_atlas],
        "industry" => %w[ind_salvage ind_automation ind_replicator],
        "command" => %w[def_analysis def_fortress def_aegis]
      }
      state["unlocked_tech"] = migrations.flat_map { |track, nodes| nodes.first(legacy_tech.fetch(track, 0).to_i) }
      state["support"] ||= []
      state["data"] ||= 0
      state["actions"] = ACTION_LIMIT
      if state["phase"] == "play"
        cards_in_cycle = state["played"].length + state["hand"].length
        draw!(6 - cards_in_cycle) if cards_in_cycle < 6
        if state["played"].length >= COMMAND_LIMIT
          state["support"] = state["played"].drop(COMMAND_LIMIT) + state["hand"]
          state["played"] = state["played"].first(COMMAND_LIMIT)
          state["hand"] = []
          state["supply"] = state["support"].sum { |key| card(key)[:supply] }
          state["data"] += state["support"].sum { |key| card(key)[:data] }
          state["phase"] = "action"
        else
          state["supply"] = 0
          state["phase"] = "command"
        end
      end
      state["rules_version"] = 2
    end

    def migrate_two_watch_state!
      state["watch"] = %w[crisis cleanup finished].include?(state["phase"]) ? 2 : 1
      state["prepared"] = []
      state["rules_version"] = 3
    end

    def migrate_frontier_state!
      remaining = (Array(state["system"]) + Array(state["deep"])).compact.uniq
      state["colonized_worlds"] = Catalog::WORLDS.keys - remaining
      inner = remaining.select { |key| world(key)[:ring] == "inner" }
      outer = remaining.select { |key| world(key)[:ring] == "outer" }
      state["system"] = [ inner.shift, inner.shift, outer.shift ]
      state["inner_deep"] = inner
      state["outer_deep"] = outer
      sync_deep!
      state["colonies"] = state["colonized_worlds"].length
      state["cycle_limit"] = 10
      state["event_deck"] = self.class.build_event_deck(game.difficulty)
      state["event_discard"] = []
      state["current_event"] = nil
      state["outer_survey_pending_completion"] = false
      state["rules_version"] = 4
    end

    def win!(message)
      game.status = "won"
      state["phase"] = "finished"
      state["outcome"] = message
      log!(message)
    end

    def lose!(message)
      game.status = "lost"
      state["phase"] = "finished"
      state["outcome"] = message
      log!(message)
    end

    def require_phase!(*allowed)
      raise InvalidMove, "This action is not available right now" unless playing? && allowed.include?(phase)
    end

    def require_no_pending!
      raise InvalidMove, "Resolve the pending effect first" if state["pending_effect"]
    end

    def require_pending!(effect)
      raise InvalidMove, "That choice is no longer pending" unless state["pending_effect"] == effect
    end

    def log!(message)
      state["log"].unshift(message)
      state["log"] = state["log"].first(12)
    end

    def save!
      game.state = state
      game.save!
      self
    end
  end
end
