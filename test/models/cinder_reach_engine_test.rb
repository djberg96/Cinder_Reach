require "test_helper"

class CinderReachEngineTest < ActiveSupport::TestCase
  teardown { Game.delete_all }

  test "setup builds a twelve card deck and six card command hand" do
    game = CinderReach::Engine.start!(difficulty: "mandate")
    state = game.state

    assert_equal 1, state["cycle"]
    assert_equal 1, state["watch"]
    assert_equal 5, state["stability"]
    assert_equal 6, state["hand"].size
    assert_equal 6, state["deck"].size
    assert_equal 12, (state["hand"] + state["deck"]).size
    assert_includes state["hand"] + state["deck"], "survey_probe"
    assert_equal 4, state["reach"].size
    assert_equal 19, state["market_deck"].size
    assert_equal 3, state["system"].size
    assert_equal 3, state["deep"].size
    assert_equal %w[inner inner outer], state["system"].map { |key| CinderReach::Catalog.world(key)[:ring] }
    assert_equal 8, state["cycle_limit"]
    assert_equal 8, state["event_deck"].size
    assert_empty state["surveyed_worlds"]
    assert_empty state["unlocked_tech"]
    assert_empty state["support"]
    assert_empty state["prepared"]
    assert_equal 2, state["actions"]
    assert_equal 0, state["data"]
    assert_equal "command", state["phase"]
  end

  test "silent protocol opens with a silent ping" do
    game = CinderReach::Engine.start!(difficulty: "silent")

    assert_equal 1, game.state["fleet"]
    assert_equal "silent_ping", game.state["incoming_crisis"]
  end

  test "standard event deck mixes opportunities dilemmas and hazards" do
    game = CinderReach::Engine.start!(difficulty: "mandate")
    tones = game.state["event_deck"].map { |key| CinderReach::Catalog.event(key)[:tone] }.tally

    assert_equal({ "opportunity" => 3, "dilemma" => 3, "hazard" => 2 }, tones)
  end

  test "an existing game enters the two watch rules safely" do
    game = CinderReach::Engine.start!
    state = game.state
    state["rules_version"] = 2
    state.delete("watch")
    state.delete("prepared")
    game.update!(state: state)

    engine = CinderReach::Engine.new(game)

    assert_equal 4, engine.state["rules_version"]
    assert_equal 1, engine.state["watch"]
    assert_empty engine.state["prepared"]
    assert_equal 10, engine.state["cycle_limit"]
  end

  test "two command cards resolve abilities and the remainder becomes support" do
    game = CinderReach::Engine.start!
    state = game.state
    state["hand"] = %w[embassy gunship colonist survey_probe charter militia]
    state["fleet"] = 2
    game.update!(state: state)

    engine = game.engine
    engine.play_card!(0)
    assert_equal "command", engine.state["phase"]
    engine.play_card!(0)

    assert_equal 6, engine.state["stability"]
    assert_equal 1, engine.state["fleet"]
    assert_equal 3, engine.state["supply"]
    assert_equal 2, engine.state["data"]
    assert_equal %w[DECREE FLEET], engine.tags
    assert_equal %w[colonist survey_probe charter militia], engine.state["support"]
    assert_empty engine.state["hand"]
    assert_equal "action", engine.state["phase"]
  end

  test "crisis defense reports whether the whole threat is averted" do
    game = CinderReach::Engine.start!
    state = game.state
    state["incoming_crisis"] = "probe_swarm"
    state["played"] = [ "militia" ]
    state["fleet"] = 2
    game.update!(state: state)

    assert game.engine.crisis_defended?
    assert game.engine.crisis_averted?

    state = game.reload.state
    state["fleet"] = 3
    game.update!(state: state)

    engine = CinderReach::Engine.new(game.reload)
    assert engine.crisis_defended?
    assert_not engine.crisis_averted?
  end

  test "only two cards can be assigned as commands" do
    game = CinderReach::Engine.start!
    state = game.state
    state["hand"] = %w[colonist militia charter colonist survey_probe militia]
    game.update!(state: state)

    2.times { game.engine.play_card!(0) }

    assert_equal 2, game.state["played"].size
    assert_equal 4, game.state["support"].size
    assert_equal "action", game.state["phase"]
    assert_raises(CinderReach::InvalidMove) { game.engine.play_card!(0) }
  end

  test "research spends banked data and one of two actions" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["played"] = [ "survey_probe", "militia" ]
    state["data"] = 2
    game.update!(state: state)

    game.engine.research!("nav_probes")

    assert_includes game.state["unlocked_tech"], "nav_probes"
    assert_equal 0, game.state["data"]
    assert_equal 1, game.state["actions"]
    assert_equal "action", game.state["phase"]
  end

  test "technology branches become mutually exclusive" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["played"] = [ "survey_probe", "field_lab" ]
    state["data"] = 8
    state["unlocked_tech"] = [ "nav_probes" ]
    game.update!(state: state)

    game.engine.research!("nav_xenology")

    assert game.engine.tech?("nav_xenology")
    assert_not game.engine.tech_available?("nav_gateways")
  end

  test "two actions advance the first watch and the crisis waits for the second" do
    game = CinderReach::Engine.start!
    incoming = game.state["incoming_crisis"]
    following = game.state["crisis_deck"].first
    state = game.state
    state["phase"] = "action"
    state["watch"] = 1
    state["supply"] = 10
    state["hand"] = []
    state["played"] = %w[militia charter]
    state["support"] = %w[colonist survey_probe colonist militia]
    state["reach"] = %w[survey_skiff habitat_ring]
    state["event_deck"] = [ "fleet_diversion" ]
    game.update!(state: state)

    game.engine.buy!(0)
    assert_equal "action", game.state["phase"]
    assert_equal 1, game.state["actions"]

    game.engine.buy!(1)
    assert_equal "event", game.state["phase"]
    event = CinderReach::Catalog.event(game.state["current_event"])
    game.engine.resolve_event!(choice: event[:choices].keys.first)
    assert_equal "command", game.state["phase"]
    assert_equal 2, game.state["watch"]
    assert_equal %w[militia charter], game.state["prepared"]
    assert_equal 6, game.state["hand"].size
    assert_equal 5, game.state["supply"]
    assert_nil game.state["current_crisis"]
    assert_equal incoming, game.state["incoming_crisis"]
    assert_includes game.engine.crisis_tags, "FLEET"

    2.times { game.engine.play_card!(0) }
    game.engine.end_actions!

    assert_equal "crisis", game.state["phase"]
    assert_equal incoming, game.state["current_crisis"]
    assert_equal following, game.state["incoming_crisis"]
  end

  test "watch one command abilities expire but cycle limits do not reset" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["watch"] = 1
    state["hand"] = []
    state["played"] = %w[charter militia]
    state["support"] = %w[colonist colonist survey_probe militia]
    state["buy_discount"] = 1
    state["hunter_used"] = true
    state["world_action_used"] = true
    game.update!(state: state)

    game.engine.end_actions!

    event = CinderReach::Catalog.event(game.state["current_event"])
    game.engine.resolve_event!(choice: event[:choices].keys.first)

    assert_equal 0, game.state["buy_discount"]
    assert game.state["hunter_used"]
    assert game.state["world_action_used"]
    assert_equal %w[charter militia], game.state["prepared"]
    assert_equal %w[DECREE FLEET], game.engine.crisis_tags
    assert_empty game.engine.tags
  end

  test "survey spends data once and colonization completes one action" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["system"] = [ "rust_mesa" ]
    state["inner_deep"] = [ "glass_sea" ]
    state["outer_deep"] = []
    state["deep"] = [ "glass_sea" ]
    state["data"] = 2
    state["supply"] = 5
    game.update!(state: state)

    engine = game.engine
    engine.survey!(0)
    assert_equal 0, engine.state["data"]
    assert_equal 7, engine.state["supply"]
    assert_includes engine.state["log"], "Surveyed Rust Mesa for 2 Data (2 → 0)."
    assert_includes engine.state["log"], "Rust Mesa survey reward: +2 Supply (5 → 7)."
    engine.colonize!

    assert_equal 1, engine.state["colonies"]
    assert_not_includes engine.state["surveyed_worlds"], "rust_mesa"
    assert_equal 6, engine.state["stability"]
    assert_includes engine.state["discard"], "outpost"
    assert_equal [ "glass_sea" ], engine.state["system"]
    assert_equal 1, engine.state["actions"]
    assert_equal "action", engine.state["phase"]
    assert_includes engine.state["log"], "Colonized Rust Mesa for 5 Supply (7 → 2). Colony 1 is online."
  end

  test "a surveyed world stays charted and does not charge or reward twice" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["system"] = [ "pale_garden" ]
    state["data"] = 2
    game.update!(state: state)

    engine = game.engine
    engine.survey!(0)
    assert_equal 0, engine.state["data"]
    assert_equal 6, engine.state["stability"]
    assert_includes engine.state["surveyed_worlds"], "pale_garden"
    engine.pass_colony!

    state = game.state
    state["supply"] = 4
    game.update!(state: state)
    engine = CinderReach::Engine.new(game)
    engine.survey!(0)

    assert_equal 0, engine.state["data"]
    assert_equal 6, engine.state["stability"]
    assert_equal "survey_decision", engine.state["phase"]
    assert_not engine.state["surveyed_this_action"]
  end

  test "intercept cancels the first fleet advance from a crisis" do
    game = CinderReach::Engine.start!
    state = game.state
    state["prepared"] = [ "militia_wing" ]
    state["played"] = []
    state["hand"] = []
    state["phase"] = "crisis"
    state["current_crisis"] = "silent_ping"
    state["fleet"] = 2
    game.update!(state: state)

    game.engine.resolve_crisis!

    assert_equal 2, game.state["fleet"]
    assert game.state["intercept_used"]
    assert_equal "cleanup", game.state["phase"]
  end

  test "a command prepared in watch one can block the crisis" do
    game = CinderReach::Engine.start!
    state = game.state
    state["prepared"] = [ "militia" ]
    state["played"] = []
    state["phase"] = "crisis"
    state["current_crisis"] = "admiralty_demand"
    state["fleet"] = 2
    game.update!(state: state)

    game.engine.resolve_crisis!

    assert_equal 2, game.state["fleet"]
    assert_equal "cleanup", game.state["phase"]
  end

  test "cleanup draws six and preserves data but not ordinary supply" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "cleanup"
    state["watch"] = 2
    state["hand"] = []
    state["prepared"] = %w[charter militia]
    state["played"] = %w[colonist militia]
    state["support"] = %w[colonist survey_probe charter militia]
    state["data"] = 3
    state["supply"] = 4
    game.update!(state: state)

    game.engine.cleanup!

    assert_equal 6, game.state["hand"].size
    assert_equal 3, game.state["data"]
    assert_equal 0, game.state["supply"]
    assert_equal 1, game.state["watch"]
    assert_empty game.state["prepared"]
    assert_equal "command", game.state["phase"]
  end

  test "the grid and two colonies hold an invasion" do
    game = CinderReach::Engine.start!
    state = game.state
    state["colonies"] = 2
    state["grid"] = true
    state["fleet"] = 4
    state["phase"] = "crisis"
    state["current_crisis"] = "silent_ping"
    game.update!(state: state)

    game.engine.resolve_crisis!

    assert_equal "playing", game.reload.status
    assert game.state["held"]
    assert_equal 5, game.state["fleet"]
  end

  test "the mandate deadline requires three colonies including an outer colony" do
    game = CinderReach::Engine.start!
    state = game.state
    state["cycle"] = 8
    state["colonized_worlds"] = %w[rust_mesa glass_sea red_choir]
    state["colonies"] = 3
    state["phase"] = "cleanup"
    game.update!(state: state)

    game.engine.cleanup!

    assert_equal "won", game.reload.status
    assert_equal "finished", game.state["phase"]
  end

  test "an outer world is technology gated and takes separate survey and colony actions" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["system"] = [ "rust_mesa", "glass_sea", "red_choir" ]
    state["data"] = 3
    state["supply"] = 6
    game.update!(state: state)

    assert_raises(CinderReach::InvalidMove) { game.engine.survey!(2) }

    state = game.state
    state["unlocked_tech"] = [ "nav_probes" ]
    game.update!(state: state)
    game.engine.survey!(2)

    assert_includes game.state["surveyed_worlds"], "red_choir"
    assert_equal "action", game.state["phase"]
    assert_equal 1, game.state["actions"]
    assert_nil game.state["surveyed_world"]

    game.engine.survey!(2)
    assert_equal "survey_decision", game.state["phase"]
    game.engine.colonize!
    assert_includes game.state["colonized_worlds"], "red_choir"
    assert_equal 1, game.engine.outer_colonies
  end

  test "midwatch events resolve before watch two" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["watch"] = 1
    state["current_event"] = nil
    state["event_deck"] = [ "quiet_signal" ]
    state["data"] = 1
    game.update!(state: state)

    game.engine.end_actions!
    assert_equal "event", game.state["phase"]
    assert_equal "quiet_signal", game.state["current_event"]

    game.engine.resolve_event!(choice: "archive")
    assert_equal 3, game.state["data"]
    assert_equal 2, game.state["watch"]
    assert_equal "command", game.state["phase"]
  end
end
