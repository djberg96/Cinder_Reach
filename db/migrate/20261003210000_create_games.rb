class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.string :difficulty, null: false, default: "mandate"
      t.string :status, null: false, default: "playing"
      t.text :state, null: false

      t.timestamps
    end
  end
end
