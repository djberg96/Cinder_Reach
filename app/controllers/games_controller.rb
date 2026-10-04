class GamesController < ApplicationController
  before_action :set_game, except: %i[index create]
  rescue_from CinderReach::InvalidMove, with: :invalid_move

  def index
    @current_game = Game.find_by(id: session[:game_id])
  end

  def create
    @game = CinderReach::Engine.start!(difficulty: params[:difficulty].presence || "mandate")
    session[:game_id] = @game.id
    redirect_to @game
  rescue CinderReach::InvalidMove => error
    redirect_to root_path, alert: error.message
  end

  def show
    @engine = @game.engine
    @state = @engine.state
  end

  def play_card = perform { @game.engine.play_card!(params[:card_index]) }
  def play_all = perform { @game.engine.play_all! }
  def resolve_listener = perform { @game.engine.resolve_listener!(move_to_bottom: params[:decision] == "bottom") }
  def buy = perform { @game.engine.buy!(params[:slot]) }
  def survey = perform { @game.engine.survey!(params[:slot]) }
  def arrange_crises = perform { @game.engine.arrange_crises!(params[:top_index]) }
  def colonize = perform { @game.engine.colonize!(relay_choice: params[:relay_choice]) }
  def pass_colony = perform { @game.engine.pass_colony! }
  def purge = perform { @game.engine.purge!(params[:pile], params[:card_index]) }
  def research = perform { @game.engine.research!(params[:tech]) }
  def end_actions = perform { @game.engine.end_actions! }
  def resolve_event = perform { @game.engine.resolve_event!(choice: params[:decision]) }
  def resolve_crisis = perform { @game.engine.resolve_crisis!(choice: params[:decision], card_index: params[:card_index], pile: params[:pile]) }
  def cleanup = perform { @game.engine.cleanup! }

  def destroy
    @game.destroy!
    session.delete(:game_id)
    redirect_to root_path, notice: "Run archived. The Reach is waiting."
  end

  private

  def set_game
    @game = Game.find(params[:id])
    session[:game_id] = @game.id
  end

  def perform
    yield
    redirect_to @game
  end

  def invalid_move(error)
    redirect_to @game, alert: error.message
  end
end
