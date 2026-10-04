require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  teardown { Game.delete_all }

  test "landing page offers all protocols" do
    get root_path

    assert_response :success
    assert_select "h1", /CINDER/
    assert_select "input[value=prospect]"
    assert_select "input[value=mandate]"
    assert_select "input[value=silent]"
  end

  test "a new game renders the command board" do
    post games_path, params: { difficulty: "mandate" }
    game = Game.last

    assert_redirected_to game_path(game)
    follow_redirect!
    assert_response :success
    assert_select ".command-strip"
    assert_select ".header-menu .header-drawer", 3
    assert_select ".mission-sidebar .cycle-panel", 1
    assert_select ".cycle-pip", 8
    assert_select ".watch-marker.active", 1
    assert_select ".colony-pips[data-count='0']", 1
    assert_select ".colony-pips .is-goal", text: /LOCK/, count: 1
    assert_select ".world-card", 3
    assert_select ".world-lane-label.inner-lane", /Inner Reach/
    assert_select ".world-lane-label.outer-lane", /Outer Reach/
    assert_select ".world-ring-badge", 0
    assert_select ".reach-row .game-card", 4
    assert_select ".hand-row .game-card", 6
    assert_select ".hand-zone[data-controller='hand-deal']", 1
    assert_select ".deck-pile[data-hand-deal-target='deck']", 1
    assert_select ".dealt-card[data-hand-deal-target='card']", 6
    assert_select ".board-tableau .tableau-panel", 2
    assert_select ".worlds-panel .section-heading h2", "Worlds in reach"
    assert_select ".market-panel .section-heading h2", "Market"
    assert_select ".worlds-panel .section-heading .micro-label", 0
    assert_select ".market-panel .section-heading .micro-label", 0
    assert_select ".strategy-row .technology-console", 1
    assert_select ".strategy-row .played-zone", 1
    assert_select ".command-slot", 2
    assert_select ".command-slot.is-empty", 2
    assert_select ".support-lane", 1
    assert_select ".turn-guide", 0
    assert_select ".incoming-crisis", 1
    assert_select ".incoming-crisis .card-kind", "CRISIS CARD"
    assert_select ".incoming-crisis .crisis-card-art", 1
    assert_select ".incoming-crisis .crisis-effect", 1
    assert_select ".incoming-crisis .incoming-status", /WATCH II/
    assert_select ".incoming-crisis .effect-results b", minimum: 1
    assert_select ".incoming-crisis .crisis-tooltip", /remains visible for both Watches/
    assert_select ".tech-summary-row", 4
    assert_select ".tech-tab", 4
    assert_select ".tech-tab-radio[checked]", 1
    assert_select ".tech-branch", 4
    assert_select ".tech-node", 20
    assert_select ".tech-node-requirement", /NEEDS A MATCHING COMMAND/
    assert_select ".tech-node-requirement small", /SURVEY OR LAB/
    assert_select ".tech-node-requirement", text: /No prerequisite/, count: 0
  end

  test "playing a card moves it into the next command slot" do
    game = CinderReach::Engine.start!
    played_name = CinderReach::Catalog.card(game.state["hand"].first)[:name]

    post play_card_game_path(game), params: { card_index: 0 }
    assert_redirected_to game_path(game)
    follow_redirect!

    assert_select ".played-card", 1
    assert_select ".played-card h3", played_name
    assert_select ".played-card .card-art", 1
    assert_select ".played-card .card-copy", 1
    assert_select ".command-slot .played-card", 1
    assert_select ".command-slot.is-empty.is-next", 1
    assert_select ".hand-row .card-hit-form", 5

    post play_card_game_path(game), params: { card_index: 0 }
    follow_redirect!

    assert_select ".command-slot .played-card", 2
    assert_select ".support-lane .played-card", 4
    assert_select ".table-phase-button", /End Watch I/
  end

  test "researching a technology updates the lattice" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "action"
    state["played"] = [ "colonist", "militia" ]
    state["data"] = 2
    game.update!(state: state)

    post research_game_path(game), params: { tech: "ind_salvage" }

    assert_redirected_to game_path(game)
    assert_includes game.reload.state["unlocked_tech"], "ind_salvage"
  end

  test "cleanup continuation sits below the mission clock" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "cleanup"
    state["watch"] = 2
    game.update!(state: state)

    get game_path(game)

    assert_response :success
    assert_select ".mission-sidebar .cycle-panel + .mission-advance-form", 1
    assert_select ".mission-advance-button", /BEGIN CYCLE 2/
    assert_select ".played-zone .mission-advance-button", 0
  end

  test "midwatch event presents its effect choices" do
    game = CinderReach::Engine.start!
    state = game.state
    state["phase"] = "event"
    state["actions"] = 0
    state["current_event"] = "emergency_levy"
    game.update!(state: state)

    get game_path(game)

    assert_response :success
    assert_select ".event-panel.event-dilemma", 1
    assert_select ".event-panel h2", "Emergency Levy"
    assert_select ".event-actions form", 2
    assert_select ".incoming-crisis", 0
  end

  test "a completed run can be permanently deleted" do
    game = CinderReach::Engine.start!
    game.update!(status: "won")
    get game_path(game)
    assert_select ".outcome-actions form[data-turbo-confirm*='cannot be undone'] .danger-text-button", "Delete run"

    assert_difference("Game.count", -1) do
      delete game_path(game)
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_select ".flash-stack[role='status'][aria-live='polite'] .flash span", /permanently deleted/i
    assert_select ".continue-panel", 0
  end

  test "the landing save slot offers continue and delete controls" do
    game = CinderReach::Engine.start!
    get game_path(game)
    get root_path

    assert_response :success
    assert_select ".continue-actions a", "Continue run"
    assert_select ".continue-actions form[data-turbo-confirm*='cannot be undone'] .danger-text-button", "Delete run"
  end

  test "signal analysis previews the following crisis" do
    game = CinderReach::Engine.start!
    state = game.state
    next_crisis = state["crisis_deck"].first
    state["unlocked_tech"] = [ "def_analysis" ]
    state["glimpse"] = [ next_crisis ]
    game.update!(state: state)

    get game_path(game)

    assert_response :success
    assert_select ".crisis-intel-trigger", /DEEP INTEL/
    assert_select ".crisis-preview-card h3", CinderReach::Catalog.crisis(next_crisis)[:name]
    assert_select ".crisis-preview-card .preview-effect-results b", minimum: 1
  end

  test "a charted world is presented as a colonization target" do
    game = CinderReach::Engine.start!
    world_key = game.state["system"].first
    state = game.state
    state["phase"] = "action"
    state["surveyed_worlds"] = [ world_key ]
    state["supply"] = 10
    game.update!(state: state)

    get game_path(game)

    assert_response :success
    assert_select ".world-card.is-surveyed .micro-label", /CHARTED .* WORLD/
    assert_select ".world-card.is-surveyed .world-action-label", /COLONIZE/
  end
end
