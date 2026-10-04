module CinderReach
  class Engine
    attr_reader :game, :state

    def self.start!(difficulty: "mandate")
      difficulty = difficulty.to_s
      raise InvalidMove, "Unknown difficulty" unless %w[prospect mandate silent].include?(difficulty)

      market = Catalog.expanded(Catalog::MARKET_COUNTS).shuffle
      worlds = Catalog::WORLDS.keys.shuffle
      crises = Catalog::CRISES.keys.shuffle
      if difficulty == "silent"
        crises.delete("silent_ping")
        crises.unshift("silent_ping")
      end

      starter = ([ "colonist" ] * 5 + [ "militia" ] * 3 + [ "charter" ] * 2).shuffle
      state = {
        "cycle" => 1, "stability" => difficulty == "prospect" ? 6 : 5,
        "fleet" => difficulty == "silent" ? 1 : 0, "colonies" => 0,
        "grid" => false, "held" => false, "supply" => 0, "orders" => 3,
        "tech" => { "expedition" => 0, "industry" => 0, "command" => 0 },
        "deck" => starter.drop(5), "hand" => starter.first(5), "discard" => [], "played" => [], "scrapped" => [],
        "market_deck" => market.drop(4), "reach" => market.first(4),
        "deep" => worlds.drop(3), "system" => worlds.first(3),
        "surveyed_worlds" => [],
        "crisis_deck" => crises.drop(1), "crisis_discard" => [], "incoming_crisis" => crises.first, "current_crisis" => nil,
        "phase" => "play", "surveyed_world" => nil, "surveyed_this_action" => false, "pending_effect" => nil,
        "buy_discount" => 0, "survey_discount" => 0, "vault_discount" => false,
        "intercept_used" => false, "stability_guard_used" => false, "glimpse" => nil,
        "log" => [ "Cycle 1 begins. Incoming signal identified." ], "outcome" => nil
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
    def tags = state["played"].filter_map { |key| card(key)[:tag] }
    def tech_level(track) = state["tech"].fetch(track.to_s, 0)
    def max_orders = tech_level("command") >= 1 ? 4 : 3

    def effective_buy_cost(key)
      info = card(key)
      vault = state["vault_discount"] && info[:tag] == "LAB"
      permanent_discount = tech_level("industry") >= 1 ? 1 : 0
      [ info[:cost] - state["buy_discount"] - permanent_discount - (vault ? 2 : 0), 0 ].max
    end

    def effective_survey_cost(key)
      permanent_discount = tech_level("expedition") >= 1 ? 1 : 0
      [ world(key)[:survey] - state["survey_discount"] - permanent_discount, 0 ].max
    end

    def effective_colony_cost(key)
      discount = tech_level("expedition") >= 3 ? 2 : 0
      [ world(key)[:colony] - discount, 0 ].max
    end

    def play_card!(index)
      require_phase!("play")
      raise InvalidMove, "Resolve the pending card effect first" if state["pending_effect"]
      raise InvalidMove, "No Orders remain this cycle" if state["orders"] <= 0
      key = state["hand"].delete_at(Integer(index))
      raise InvalidMove, "That card is no longer in your hand" unless key

      state["played"] << key
      state["orders"] -= 1
      state["supply"] += card(key)[:supply]
      state["orders"] += card(key).fetch(:orders, 0)
      log!("Played #{card(key)[:name]} for #{card(key)[:supply]} Supply.")
      resolve_card!(key)
      save!
    end

    def play_all!
      require_phase!("play")
      while state["hand"].any? && state["orders"].positive? && !state["pending_effect"] && playing?
        play_card!(0)
      end
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
      save!
    end

    def buy!(index)
      require_phase!("play")
      require_no_pending!
      key = state["reach"][Integer(index)]
      raise InvalidMove, "That Reach slot is empty" unless key

      info = card(key)
      vault = state["vault_discount"] && info[:tag] == "LAB"
      cost = effective_buy_cost(key)
      raise InvalidMove, "You need #{cost} Supply" if state["supply"] < cost

      state["supply"] -= cost
      state["discard"] << key
      state["reach"][Integer(index)] = state["market_deck"].shift
      state["vault_discount"] = false if vault
      log!("Bought #{info[:name]} for #{cost} Supply.")
      begin_crisis!
      save!
    end

    def survey!(index)
      require_phase!("play")
      require_no_pending!
      key = state["system"][Integer(index)]
      raise InvalidMove, "That System slot is empty" unless key
      info = world(key)

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
      raise InvalidMove, "You need #{cost} Supply" if state["supply"] < cost

      state["supply"] -= cost
      state["surveyed_worlds"] << key
      state["surveyed_world"] = key
      state["surveyed_this_action"] = true
      state["phase"] = "survey_decision"
      log!("Surveyed #{info[:name]} for #{cost} Supply.")
      case key
      when "rust_mesa" then state["supply"] += 2
      when "glass_sea" then draw!(1)
      when "pale_garden" then adjust_stability!(1)
      when "red_choir" then adjust_fleet!(-1)
      when "vault_orbit" then state["vault_discount"] = true
      when "black_relay"
        state["pending_effect"] = "black_relay"
        state["glimpse"] = [ state["incoming_crisis"], state["crisis_deck"].first ].compact
      end
      state["supply"] += 1 if tech_level("expedition") >= 2
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
      save!
    end

    def colonize!(relay_choice: nil)
      require_phase!("survey_decision")
      require_no_pending!
      key = state["surveyed_world"]
      info = world(key)
      colony_cost = effective_colony_cost(key)
      raise InvalidMove, "You need #{colony_cost} Supply" if state["supply"] < colony_cost
      if key == "black_relay" && !%w[grid fleet].include?(relay_choice)
        raise InvalidMove, "Choose the Relay's colony benefit"
      end

      state["supply"] -= colony_cost
      state["discard"] << "outpost"
      state["colonies"] += 1
      slot = state["system"].index(key)
      state["system"][slot] = state["deep"].shift if slot
      state["surveyed_worlds"].delete(key)
      state["surveyed_world"] = nil
      state["surveyed_this_action"] = false
      adjust_stability!(1) if key == "rust_mesa"
      scrap_first_unrest!(piles: %w[hand discard]) if key == "pale_garden"
      draw!(1) if key == "vault_orbit"
      if key == "black_relay"
        relay_choice == "grid" ? state["grid"] = true : adjust_fleet!(-1)
      end
      log!("Colonized #{info[:name]}. Colony #{state['colonies']} is online.")
      check_beacon!
      begin_crisis! if playing?
      save!
    end

    def research!(track_key)
      require_phase!("play")
      require_no_pending!
      track_key = track_key.to_s
      track = Catalog::TECH_TRACKS[track_key]
      raise InvalidMove, "Unknown technology track" unless track
      level = tech_level(track_key)
      upgrade = track[:levels][level]
      raise InvalidMove, "#{track[:name]} is already at maximum" unless upgrade

      matching_tags = tags.count { |tag| track[:tags].include?(tag) }
      raise InvalidMove, "You need #{upgrade[:tags]} matching tags in play" if matching_tags < upgrade[:tags]
      raise InvalidMove, "You need #{upgrade[:cost]} Supply" if state["supply"] < upgrade[:cost]

      state["supply"] -= upgrade[:cost]
      state["tech"][track_key] = level + 1
      state["grid"] = true if track_key == "command" && level + 1 == 3
      log!("#{track[:name]} advanced to #{upgrade[:name]}.")
      begin_crisis!
      save!
    end

    def pass_colony!
      require_phase!("survey_decision")
      require_no_pending!
      log!("Left #{world(state['surveyed_world'])[:name]} uncolonized.")
      state["surveyed_world"] = nil
      state["surveyed_this_action"] = false
      begin_crisis!
      save!
    end

    def purge!(index)
      require_phase!("play")
      require_no_pending!
      key = state["hand"][Integer(index)]
      raise InvalidMove, "That card is no longer in your hand" unless key
      raise InvalidMove, "Unrest can only be scrapped by card effects" if key == "unrest"

      state["hand"].delete_at(Integer(index))
      state["scrapped"] << key
      log!("Purged #{card(key)[:name]} from the deck.")
      begin_crisis!
      save!
    end

    def resolve_crisis!(choice: nil, card_index: nil)
      require_phase!("crisis")
      key = state["current_crisis"]
      raise InvalidMove, "There is no crisis to resolve" unless key

      case key
      when "ration_riot"
        unless tags.count("COLONY") >= 2
          adjust_stability!(-1); gain_unrest!
        end
      when "admiralty_demand"
        adjust_fleet!(1, crisis: true) unless tags.include?("FLEET")
      when "consortium_embargo"
        adjust_stability!(-1) unless tags.include?("DECREE")
      when "silent_ping"
        adjust_fleet!(1, crisis: true)
      when "council_fracture"
        unless tags.include?("DECREE")
          adjust_stability!(-1); gain_unrest!
        end
      when "harvest_blight"
        if choice == "scrap"
          scrap_hand_card!(card_index)
        elsif choice == "stability"
          adjust_stability!(-1)
        else
          raise InvalidMove, "Choose a card to scrap or lose Stability"
        end
      when "probe_swarm"
        adjust_fleet!(1, crisis: true) unless tags.include?("FLEET")
        adjust_stability!(-1) if state["fleet"] >= 3 && playing?
      when "refugee_wave"
        gain_unrest!; draw!(1)
      when "deep_signal"
        state["glimpse"] = state["crisis_deck"].first(1)
        if choice == "scrap"
          scrap_hand_card!(card_index)
        elsif choice == "fleet"
          adjust_fleet!(1, crisis: true)
        else
          raise InvalidMove, "Choose a card to scrap or advance the Fleet"
        end
      when "beacon_flicker"
        if state["colonies"] < 2
          adjust_stability!(-1)
          adjust_fleet!(1, crisis: true) if playing?
        end
      end

      finish_crisis!(key) if playing?
      save!
    end

    def cleanup!
      require_phase!("cleanup")
      state["discard"].concat(state["played"]).concat(state["hand"])
      state["played"] = []
      state["hand"] = []
      state["supply"] = 0
      state["buy_discount"] = 0
      state["survey_discount"] = 0
      state["intercept_used"] = false
      state["stability_guard_used"] = false
      state["glimpse"] = nil
      state["cycle"] += 1
      if state["cycle"] > 10
        if state["colonies"] >= 2
          win!("Mandate fulfilled. Ark-9 survives the tenth cycle.")
        else
          lose!("The mandate expired before two colonies could be established.")
        end
      else
        draw!(5)
        state["orders"] = max_orders
        state["supply"] = industry_starting_supply
        state["phase"] = "play"
        log!("Cycle #{state['cycle']} begins.")
      end
      save!
    end

    def score
      owned = state.values_at("deck", "hand", "discard", "played").flatten
      state["colonies"] * 3 + state["stability"] + (state["fleet"] <= 1 ? 2 : 0) +
        (state["grid"] ? 2 : 0) + owned.count { |key| card(key)[:tag] == "LAB" } - owned.count("unrest")
    end

    private

    def resolve_card!(key)
      case key
      when "survey_skiff" then state["survey_discount"] += 1
      when "decree" then scrap_first_unrest!
      when "embassy", "arcology" then adjust_stability!(1)
      when "field_lab" then state["buy_discount"] += 1
      when "listener_array"
        if state["incoming_crisis"]
          state["pending_effect"] = "listener"
          state["glimpse"] = [ state["incoming_crisis"] ]
        end
      when "gene_vault" then draw!(1)
      when "gunship" then adjust_fleet!(-1)
      when "defense_grid" then state["grid"] = true
      end
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
      if amount.negative? && tech_level("command") >= 2 && !state["stability_guard_used"]
        state["stability_guard_used"] = true
        log!("Civil Defense prevented the Stability loss.")
        return
      end
      state["stability"] = [ [ state["stability"] + amount, 0 ].max, 8 ].min
      lose!("The council collapsed. Ark-9 is lost from within.") if state["stability"].zero?
    end

    def intercept_available?
      (state["played"] & %w[militia_wing gunship defense_grid]).any?
    end

    def gain_unrest!
      state["discard"] << "unrest"
      log!("Unrest entered your discard pile.")
    end

    def scrap_first_unrest!(piles: %w[hand played discard])
      piles.each do |pile|
        index = state[pile].index("unrest")
        next unless index
        state[pile].delete_at(index)
        state["scrapped"] << "unrest"
        log!("Scrapped an Unrest.")
        return true
      end
      false
    end

    def scrap_hand_card!(index)
      raise InvalidMove, "Choose a card from your hand" if index.nil?
      key = state["hand"].delete_at(Integer(index))
      raise InvalidMove, "That card is no longer in your hand" unless key
      state["scrapped"] << key
      log!("Scrapped #{card(key)[:name]}.")
    end

    def draw!(count)
      count.times do
        if state["deck"].empty? && state["discard"].any?
          state["deck"] = state["discard"].shuffle
          state["discard"] = []
          log!("Shuffled the discard into a new deck.")
        end
        drawn = state["deck"].shift
        state["hand"] << drawn if drawn
      end
    end

    def check_beacon!
      win!("Beacon lock achieved. Four colonies answer across the Reach.") if state["colonies"] >= 4 && state["fleet"] <= 4
    end

    def industry_starting_supply
      case tech_level("industry")
      when 3 then 3
      when 2 then 1
      else 0
      end
    end

    def normalize_state!
      state["tech"] ||= { "expedition" => 0, "industry" => 0, "command" => 0 }
      %w[expedition industry command].each { |track| state["tech"][track] ||= 0 }
      state["surveyed_worlds"] ||= []
      if state["surveyed_world"] && !state["surveyed_worlds"].include?(state["surveyed_world"])
        state["surveyed_worlds"] << state["surveyed_world"]
      end
      state["orders"] = max_orders if state["orders"].nil?
      state["surveyed_this_action"] = false if state["surveyed_this_action"].nil?
      state["stability_guard_used"] = false if state["stability_guard_used"].nil?
      unless state.key?("incoming_crisis")
        state["incoming_crisis"] = state["crisis_deck"].shift
      end
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
