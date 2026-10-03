module ApplicationHelper
  TAG_SYMBOLS = { "COLONY" => "⌂", "FLEET" => "✦", "DECREE" => "◇", "SURVEY" => "⌁", "LAB" => "△" }.freeze

  def tag_symbol(tag) = TAG_SYMBOLS[tag]
  def card_data(key) = CinderReach::Catalog.card(key)
  def world_data(key) = CinderReach::Catalog.world(key)
  def crisis_data(key) = CinderReach::Catalog.crisis(key)

  def effective_buy_cost(state, key)
    data = card_data(key)
    vault = state["vault_discount"] && data[:tag] == "LAB"
    [ data[:cost] - state["buy_discount"] - (vault ? 2 : 0), 0 ].max
  end

  def effective_survey_cost(state, key)
    [ world_data(key)[:survey] - state["survey_discount"], 0 ].max
  end

  def card_tone(tag) = tag&.downcase || "neutral"
end
