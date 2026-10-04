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
    assert_select ".world-card", 3
    assert_select ".reach-row .game-card", 4
    assert_select ".hand-row .game-card", 5
    assert_select ".board-tableau .tableau-panel", 2
    assert_select ".strategy-row .technology-console", 1
    assert_select ".strategy-row .played-zone", 1
    assert_select ".incoming-crisis", 1
    assert_select ".tech-track", 3
  end

  test "playing a card moves it onto the table and updates guidance" do
    game = CinderReach::Engine.start!
    played_name = CinderReach::Catalog.card(game.state["hand"].first)[:name]

    post play_card_game_path(game), params: { card_index: 0 }
    assert_redirected_to game_path(game)
    follow_redirect!

    assert_select ".played-card", 1
    assert_select ".played-card h3", played_name
    assert_select ".turn-guide h2", "Commit your turn"
    assert_select ".guide-supply strong", game.reload.state["supply"].to_s
    assert_select ".hand-row .card-hit-form", 4
  end

  test "researching a technology updates its track" do
    game = CinderReach::Engine.start!
    state = game.state
    state["played"] = [ "colonist" ]
    state["supply"] = 2
    game.update!(state: state)

    post research_game_path(game), params: { track: "industry" }

    assert_redirected_to game_path(game)
    assert_equal 1, game.reload.state.dig("tech", "industry")
  end
end
