module ApplicationHelper
  TAG_SYMBOLS = { "COLONY" => "⌂", "FLEET" => "✦", "DECREE" => "◇", "SURVEY" => "⌁", "LAB" => "△" }.freeze

  def tag_symbol(tag) = TAG_SYMBOLS[tag]
  def card_data(key) = CinderReach::Catalog.card(key)
  def world_data(key) = CinderReach::Catalog.world(key)
  def crisis_data(key) = CinderReach::Catalog.crisis(key)
  def event_data(key) = CinderReach::Catalog.event(key)
  def tech_data(key) = CinderReach::Catalog.tech_tree(key)

  def effective_buy_cost(_state, key)
    @engine.effective_buy_cost(key)
  end

  def effective_survey_cost(_state, key)
    @engine.effective_survey_cost(key)
  end

  def effective_colony_cost(_state, key) = @engine.effective_colony_cost(key)

  def card_tone(tag) = tag&.downcase || "neutral"
end
