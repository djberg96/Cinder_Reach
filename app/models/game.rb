class Game < ApplicationRecord
  serialize :state, coder: JSON

  validates :difficulty, inclusion: { in: %w[prospect mandate silent] }
  validates :status, inclusion: { in: %w[playing won lost] }

  def engine
    @engine ||= CinderReach::Engine.new(self)
  end
end
