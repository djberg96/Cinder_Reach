require "test_helper"

class CinderReachEngineTest < ActiveSupport::TestCase
  teardown { Game.delete_all }

  test "setup builds the complete play area" do
    game = CinderReach::Engine.start!(difficulty: "mandate")
    state = game.state

    assert_equal 1, state["cycle"]
    assert_equal 5, state["stability"]
    assert_equal 5, state["hand"].size
    assert_equal 5, state["deck"].size
    assert_equal 4, state["reach"].size
    assert_equal 19, state["market_deck"].size
    assert_equal 3, state["system"].size
    assert_equal 3, state["deep"].size
    assert state["incoming_crisis"].present?
    assert_equal 9, state["crisis_deck"].size
    assert_equal 3, state["orders"]
    assert_equal({ "expedition" => 0, "industry" => 0, "command" => 0 }, state["tech"])
  end

  test "silent protocol opens with a silent ping" do
    game = CinderReach::Engine.start!(difficulty: "silent")

    assert_equal 1, game.state["fleet"]
    assert_equal "silent_ping", game.state["incoming_crisis"]
  end

  test "playing cards gains supply tags and resolves effects" do
    game = CinderReach::Engine.start!
    state = game.state
    state["hand"] = %w[embassy gunship]
    state["fleet"] = 2
    game.update!(state: state)

    engine = game.engine
    engine.play_card!(0)
    engine.play_card!(0)

    assert_equal 6, engine.state["stability"]
    assert_equal 1, engine.state["fleet"]
    assert_equal 5, engine.state["supply"]
    assert_equal %w[DECREE FLEET], engine.tags
  end

  test "orders force a choice among cards in hand" do
    game = CinderReach::Engine.start!
    state = game.state
    state["hand"] = %w[colonist militia charter colonist]
    game.update!(state: state)

    3.times { game.engine.play_card!(0) }

    assert_equal 0, game.state["orders"]
    assert_equal 1, game.state["hand"].size
    assert_raises(CinderReach::InvalidMove) { game.engine.play_card!(0) }
  end

  test "research spends supply and matching tags for a permanent upgrade" do
    game = CinderReach::Engine.start!
    state = game.state
    state["played"] = [ "colonist" ]
    state["supply"] = 2
    game.update!(state: state)

    game.engine.research!("industry")

    assert_equal 1, game.state.dig("tech", "industry")
    assert_equal 0, game.state["supply"]
    assert_equal "crisis", game.state["phase"]
    assert game.state["current_crisis"].present?
  end

  test "the next crisis is visible before committing and advances after the action" do
    game = CinderReach::Engine.start!
    incoming = game.state["incoming_crisis"]
    following = game.state["crisis_deck"].first
    state = game.state
    state["supply"] = 2
    state["reach"] = [ "survey_skiff" ]
    game.update!(state: state)

    game.engine.buy!(0)

    assert_equal incoming, game.state["current_crisis"]
    assert_equal following, game.state["incoming_crisis"]
  end

  test "buy uses discounts and reveals a crisis" do
    game = CinderReach::Engine.start!
    state = game.state
    state["reach"] = [ "defense_grid" ]
    state["supply"] = 5
    state["buy_discount"] = 1
    game.update!(state: state)

    game.engine.buy!(0)

    assert_equal 0, game.state["supply"]
    assert_includes game.state["discard"], "defense_grid"
    assert_equal "crisis", game.state["phase"]
    assert game.state["current_crisis"].present?
  end

  test "survey can flow into colonization" do
    game = CinderReach::Engine.start!
    state = game.state
    state["system"] = [ "rust_mesa" ]
    state["deep"] = [ "glass_sea" ]
    state["supply"] = 5
    game.update!(state: state)

    engine = game.engine
    engine.survey!(0)
    assert_equal 5, engine.state["supply"], "Rust Mesa refunds two Supply after its survey cost"
    engine.colonize!

    assert_equal 1, engine.state["colonies"]
    assert_equal 6, engine.state["stability"]
    assert_includes engine.state["discard"], "outpost"
    assert_equal [ "glass_sea" ], engine.state["system"]
    assert_equal "crisis", engine.state["phase"]
  end

  test "intercept cancels the first fleet advance from a crisis" do
    game = CinderReach::Engine.start!
    state = game.state
    state["played"] = [ "militia_wing" ]
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

  test "cycle ten awards the mandate with two colonies" do
    game = CinderReach::Engine.start!
    state = game.state
    state["cycle"] = 10
    state["colonies"] = 2
    state["phase"] = "cleanup"
    game.update!(state: state)

    game.engine.cleanup!

    assert_equal "won", game.reload.status
    assert_equal "finished", game.state["phase"]
  end
end
