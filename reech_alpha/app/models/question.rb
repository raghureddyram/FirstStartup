include Scrubber
class Question < ActiveRecord::Base
  has_merit

  attr_accessible :post, :posted_by, :posted_by_uid,:question_id, :points, :Charisma
  before_save :create_question_id
  
  belongs_to :user

  has_many :posted_solutions,
  :class_name => 'Solution',
  :primary_key=>'question_id',
  :foreign_key => 'question_id',
  :order => "solutions.created_at DESC"

  def create_question_id
    self.question_id=gen_question_id
  end

  def self.filterforuser(user_id)
    current_user = User.find_by_reecher_id("#{user_id}")
    @Qpostedbyuser = Question.where(:posted_by_uid => current_user.reecher_id)
    #@Questions = @Qpostedbyuser.collect{|question| {:value=>question.id, :label=>question.post}}
    @Questions = []
    @Questions << @Qpostedbyuser
    @Qbyfriendship = Question.find(:all, :order => 'questions.created_at DESC')
      @Qbyfriendship.each do |question|
        @posting_user = question.posted_by_uid
        if Friendship.are_friends(@posting_user,current_user.reecher_id)
           @Questions << question
        end
      end
      @Questions = @Questions.flatten
  end


end