module Api
	module V1
		class UserSettingsController < ApiController
			before_filter :restrict_access
			respond_to :json

			def view_settings
				@user = User.find_by_reecher_id(params[:user_id])
				msg = {:status => 200, :settings => @user.user_settings}_
				render :json => msg
			end	

			def update_settings
				@user = User.find_by_reecher_id(params[:user_id])
				user_settings = @user.user_settings
				user_settings.location_is_enabled = params[:loc_option]
				user_settings.pushnotif_is_enabled = params[:pushnotif_option]
				user_settings.emailnotif_is_enabled = params[:email_option]
				user_settings.notify_question_when_answered = params[:qanswered_option]
				user_settings.notify_linked_to_question = params[:lquestion_option]
				user_settings.notify_solution_got_highfive = params[:solutionhi5_option]
				user_settings.save
				msg = {:status => 200, :settings => @user.user_settings}_
				render :json => msg
			end
				
		end
	end
end			