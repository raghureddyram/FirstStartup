class PurchasedSolution < ActiveRecord::Base
  #attr_accessible :solution_id, :user_id
  belongs_to :user
  belongs_to :scribble_comment
end
