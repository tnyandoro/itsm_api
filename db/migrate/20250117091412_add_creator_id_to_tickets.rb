class AddCreatorIdToTickets < ActiveRecord::Migration[7.1]
  def change
    add_reference :tickets, :creator, foreign_key: { to_table: :users }
  end
end