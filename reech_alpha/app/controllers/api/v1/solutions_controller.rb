module Api
	module V1
		class SolutionsController < ApiController
		before_filter :restrict_access
		respond_to :json	

			def create
				@solver = User.find_by_reecher_id(params[:user_id])
				@solution = Solution.new()
				@solution.body = params[:solution]
				@solution.question_id = params[:question_id]
				@solution.solver_id = @solver.reecher_id
				@solution.solver = "#{@solver.first_name} #{@solver.last_name}"
				@solution.ask_charisma = params[:ask_charisma] 

				if !params[:solution_image].blank? 
					data = StringIO.new(Base64.decode64(params[:solution_image]))
					@solution.picture = data
				end

				if !params[:expert_details].nil?
					if !params[:expert_details][:emails].nil?
						# if the expert is in reech network directly link the question 
						# Otherwise send an simple email to him
						params[:expert_details][:emails].each do |email|
							linked_user = User.find_by_email(email)
							if linked_user.present?
								linked_question = LinkedQuestion.where(:user_id => linked_user.reecher_id, :question_id => params[:question_id], :linked_by_uid => @solver.reecher_id)
								if !linked_question.present?
									link_question = LinkedQuestion.new
									link_question.user_id = linked_user.reecher_id
									link_question.question_id = params[:question_id]
									link_question.linked_by_uid = @solver.reecher_id
									link_question.save
								end	
							else
							  
				        begin
                  UserMailer.send_link_question_email(email, @solver).deliver
                rescue Exception => e
                  logger.error e.backtrace.join("\n")
                end
								
							end	
						end	
					end

					if !params[:expert_details][:phone_numbers].nil?
						client = Twilio::REST::Client.new(TWILIO_CONFIG['sid'], TWILIO_CONFIG['token'])
						params[:expert_details][:phone_numbers].each do |number|
							sms = client.account.sms.messages.create(
        							from: TWILIO_CONFIG['from'],
        							to: number,
        							body: "your friend #{@solver.first_name} #{@user.last_name}  want to solve his friend's question on Reech."
      						)
      						logger.debug ">>>>>>>>>Sending sms to #{number} with text #{sms.body}"
						end
					end	
			 end	
       
        
      
        
			if @solution.save
				    # send push notification to user who posted this question
            qust_details = Question.find_by_question_id(params[:question_id])
            #user_details = User.includes(:questions).where("questions.question_id" =>params[:question_id]) 
             #delete_linked_question(@solver.reecher_id,qust_details.question_id)
            if !qust_details.nil?
               check_setting= check_notify_question_when_answered(qust_details.posted_by_uid)
               puts "check_setting==#{check_setting}"
               if check_setting
                #device_details = Device.where("reecher_id=?",user_details[0][:posted_by_uid].to_s)
                device_details=Device.select("device_token,platform").where("reecher_id=?",qust_details.posted_by_uid.to_s)
                puts "device_details==#{device_details.inspect}"
                response_string ="PRSLN,"+ @solution.solver + ","+params[:question_id]+","+Time.now().to_s
                if !device_details.empty? 
                    device_details.each do |d|
                      
                      send_device_notification(d[:device_token].to_s, response_string ,d[:platform].to_s, @solution.solver+PUSH_TITLE_PRSLN)
                    end  
                end 
               end
             
            end
          
           #Send push notification to those who starred this question
           @voting = Voting.where(question_id: qust_details.id)
           if !@voting.blank?
            @voting.each do |v|
             check_setting= notify_when_my_stared_question_get_answer(v.user_id)
             puts "check_setting====#{check_setting}"
             puts "check_setting---user====#{v.user_id}"
               if check_setting
                starred_user = User.find_by_id(v.user_id)
                puts "starred_user===#{starred_user.inspect}"
                device_details = Device.select("device_token,platform").where("reecher_id=?",starred_user.reecher_id)
                puts "device_details===#{device_details.inspect}"
                response_string = "STARSOLS,"+ @solution.solver + ","+params[:question_id]+"," +Time.now().to_s
                  if !device_details.blank?   
                     device_details.each do |d|
                       puts "SEND NOTIFCAITION TO ===#{d[:device_token].to_s}"
                       send_device_notification(d[:device_token].to_s, response_string ,d[:platform].to_s,@solution.solver+PUSH_TITLE_STARSOLS)
                     end
                  end
               end
           end
          end
				
					msg = {:status => 200, :solution => @solution}
					
				else
					msg = {:status => 400, :message => "Failed"}
				end	
				render :json => msg
			end

			def purchase_solution
			  user = User.find_by_reecher_id(params[:user_id])
				solution = Solution.find(params[:solution_id])
				question = Question.where(:question_id =>solution.question_id)
				#sfdsdfs
				question_id = question[0][:question_id]
				quest_asker = question[0][:posted_by_uid]
        quest_is_public = question[0][:is_public]
				
				purchased_sl = PurchasedSolution.where(:user_id => user.id, :solution_id => solution.id)
				if purchased_sl.present?
					msg = {:status => 400, :message => "You have Already Purchased this Solution."}
				else	
					if user.points > solution.ask_charisma
						purchased_solution = PurchasedSolution.new
						purchased_solution.user_id = user.id
						purchased_solution.solution_id = solution.id
						purchased_solution.save
					
						if ((quest_asker.to_s == user.reecher_id.to_s) && !quest_is_public) 						  
						 PostQuestionToFriend.create(:user_id =>user.reecher_id ,:friend_reecher_id =>solution.solver_id, :question_id=>question[0][:question_id])
						end
						
						
						#Make friend between login user and solution provider
						check_friend = Friendship::are_friends(user.reecher_id,solution.solver_id)						
						if !check_friend						  
						  make_friendship_standard(user.reecher_id,solution.solver_id)						 
						end
						
						#End of friendship  code
						
            linked_by = LinkedQuestion.find_by_question_id(solution.question_id)
						
						# Send notification to the solver
						check_setting= notify_when_someone_grab_my_answer(solution.solver_id)
						if check_setting
						  solver_details = User.find_by_reecher_id(solution.solver_id)
                     if !solver_details.blank? && linked_by.blank?  
                         device_details = Device.where(:reecher_id=>solver_details.reecher_id)
                         if !device_details.blank?
                         notify_string ="GRABSOLS," + user.full_name + "," + (solution.id).to_s + "," + Time.now().to_s
                           device_details.each do |d|
                                send_device_notification(d[:device_token].to_s, notify_string ,d[:platform].to_s,user.full_name+PUSH_TITLE_GRABSOLS)
                           end

                         end
                     end  
            end
						preview_solution = PreviewSolution.find_by_user_id_and_solution_id(user.id, solution.id)
						preview_solution.destroy
						#Add points to solution provider
						solution_provider = User.find_by_reecher_id(solution.solver_id)
						#Revert back the points to user who post the question
						
					   	if linked_by.blank?		
						    quest_asker = question[0][:posted_by_uid]
						    solution_provider.add_points(solution.ask_charisma)						   
						    if quest_asker == params[:user_id]
							   user.subtract_points(solution.ask_charisma)
							   all_solution_for_this_question = Solution.where(:question_id=>solution.question_id)
							   all_solution_for_this_question = all_solution_for_this_question.collect{|s| s.id}
							   
							   ssss =check_one_time_bonus_distribution(solution.question_id ,all_solution_for_this_question,user.id)
							   if ssss
							     user.add_points(10)        
							   end
						    else
						     user.subtract_points(solution.ask_charisma)	
						    end	
						    
					    else
					    	linked_by_user = User.find_by_reecher_id(linked_by.linked_by_uid)		
					    	device_details = Device.where(:reecher_id=>solver_details.reecher_id)
                if !device_details.blank?
                   msgText = user.full_name + " just grabbed an answer you gave to your friend " + linked_by_user.first_name + "'s question." + user.first_name + " is now a part of your REECH."
                   notify_string ="GRABSOLSLINK," + msgText + "," + (solution.id).to_s + "," + Time.now().to_s
                   device_details.each do |d|
                   send_device_notification(d[:device_token].to_s, notify_string ,d[:platform].to_s,user.full_name+PUSH_TITLE_GRABSOLSLINK)
                   end
                end
					    	one_by_five = (((solution.ask_charisma).to_i ) * 1/5).floor
					    	fourth_by_five = (((solution.ask_charisma).to_i ) * 4/5).floor
					    	linked_by_user.add_points(one_by_five)
					    	solution_provider.add_points(fourth_by_five)					    	
                all_solution_for_this_question = Solution.where(:question_id=>solution.question_id)
                all_solution_for_this_question = all_solution_for_this_question.collect{|s| s.id}
					    	quest_asker = question[0][:posted_by_uid]
					    	if quest_asker== params[:user_id]
							   user.subtract_points(solution.ask_charisma)
							   ssss =check_one_time_bonus_distribution(solution.question_id ,all_solution_for_this_question,user.id)
                 if ssss
                   user.add_points(10)        
                 end
							   
						    else
						     user.subtract_points(solution.ask_charisma)	
						    end	

					    end 	
             # make friend 
  
                         
						msg = {:status => 200, :message => "Success"}
					else
						msg = {:status => 400, :message => "Sorry, you need at least #{solution.ask_charisma} Charisma Credits to purchase this Solution! Earn some by providing Solutions!"}
					end	
				end
				render :json => msg
			end	

			def view_solution
				solution = Solution.find(params[:solution_id])
				solution_owner_profile = User.find_by_reecher_id(solution.solver_id).user_profile
				@solution = solution.attributes
				@solution[:hi5] = solution.votes_for.size
				solution.picture_file_name != nil ? @solution[:image_url] =  solution.picture_original_url : @solution[:image_url] = nil
				solution_owner_profile.picture_file_name != nil ? @solution[:solver_image] = solution_owner_profile.picture_url : @solution[:solver_image] = nil
			    user = User.find_by_reecher_id(params[:user_id])
			    res  =  ActiveRecord::Base.connection.select("Select count(*) as num_row from votes where voter_id=#{user.id} and votable_id=#{solution.id} and votable_type ='Solution';")
			    res_num_row =res[0]
			    if res_num_row["num_row"] >0
			     hi5 =true	
			     else
			     hi5 =false	
			    end	
			    
			    msg = {:status => 201, :message => "Success", :user_id=>solution_owner_profile.reecher_id}
				msg = {:status => 200, :solution => @solution ,:has_hi5=>hi5} 
				render :json => msg
			end	
			
=begin
			def view_all_solutions
				solutions = Solution.find_all_by_question_id(params[:question_id])
				#qust_details =Question.find_by_question_id(params[:question_id])
				logined_user = User.find_by_reecher_id(params[:user_id])
				@solutions = []
				if solutions.size > 0
					solutions.logger.error e.backtrace.join("\n")each do |sl|
					  
						solution_attrs = sl.attributes
						
						user = User.find_by_reecher_id(sl.solver_id)
						
						user.user_profile.picture_file_name != nil ? solution_attrs[:solver_image] =  "http://#{request.host_with_port}" + user.user_profile.picture_url : solution_attrs[:solver_image] = nil
						
						sl.picture_file_name != nil ? solution_attrs[:image_url] =  "http://#{request.host_with_port}" + sl.picture_url : solution_attrs[:image_url] = "http://#{request.host_with_port}/"+"no-image.png"
						
						purchased_sl = PurchasedSolution.where(:user_id => logined_user.id, :solution_id => sl.id)
					 
						if purchased_sl.present?  
							solution_attrs[:purchased] = true
						else
							solution_attrs[:purchased] = false	
						end	
						
						@solutions << solution_attrs
					
					end	
				end
				msg = {:status => 200, :solutions => @solutions} 
				logger.debug "******Response To #{request.remote_ip} at #{Time.now} => #{@solutions}"

				render :json => msg
			end	

=end
			def preview_solution
				@user = User.find_by_reecher_id(params[:user_id])
				@solution = Solution.find(params[:solution_id])
				@preview_solution = PreviewSolution.where(:user_id => @user.id, :solution_id => @solution.id)
				if @preview_solution.present? 
				  msg = {:status => 400, :message => "You have to purchase this solution."}
				else
					preview_solution = PreviewSolution.new
					preview_solution.user_id = @user.id
					preview_solution.solution_id = @solution.id
					preview_solution.save
					msg = {:status => 200, :solution => @solution}
				end	
				render :json => msg
			end	

			def previewed_solutions
				@user = User.find_by_reecher_id(params[:user_id])
				previewed_solutions = @user.preview_solutions
				solution_ids = []
				if previewed_solutions.size > 0
					previewed_solutions.each do |ps|
						solution_ids << ps.solution_id
					end
				end	
				msg = {:status => 200, :solution_ids => solution_ids}
				logger.debug "******Response To #{request.remote_ip} at #{Time.now} => #{solution_ids}"
				render :json => msg
			end	

			def solution_hi5
				solution = Solution.find(params[:solution_id])
				user = User.find_by_reecher_id(params[:user_id])
				solution.liked_by(user)
				@solution = solution.attributes
				@solution[:hi5] = solution.votes_for.size
				solution.picture_file_name != nil ? @solution[:image_url] =  solution.picture_url : @solution[:image_url] = nil
				# send push notification while hi5 solution
				check_setting= notify_solution_got_highfive(solution.solver_id)
                puts "check_setting==#{check_setting}"
               if check_setting
                device_details=Device.select("device_token,platform").where("reecher_id=?",solution.solver_id.to_s)
                response_string ="HGHFV,"+ user.full_name + "," + params[:solution_id] +","+Time.now().to_s
                if !device_details.empty? 
                    device_details.each do |d|
                      send_device_notification(d[:device_token].to_s, response_string ,d[:platform].to_s,user.full_name+PUSH_TITLE_HGHFV)
                    end  
                end 
               end
				solution.picture_file_name != nil ? @solution[:image_url] =solution.picture_url : @solution[:image_url] = nil
				msg = {:status => 200, :solution => @solution}
				render :json => msg
				
				
			end	
      
       def get_solution_details
        sol_id = params[:solution_id]
        sol_details = Solution.find_by_question_id(sol_id)
        msg = {:status => 200, :solution_details => sol_details}
        render :json =>msg 
        
       end
     
       
      def question_details_with_solutions
        solutions = Solution.find_all_by_question_id(params[:question_id])
        qust_details =Question.find_by_question_id(params[:question_id])
        question_owner = User.find_by_reecher_id(qust_details[:posted_by_uid])
         #puts "aaaaaaaaaaaaaaa=#{solutions["question_id"]}"
        question_owner_profile = question_owner.user_profile
        qust_details.is_stared? ? qust_details[:stared] = true : qust_details[:stared] =false
        qust_details[:owner_location] = question_owner_profile.location
        qust_details[:avatar_file_name] != nil ? qust_details[:image_url] =  qust_details.avatar_original_url : qust_details[:image_url] = nil
        question_owner_profile.picture_file_name != nil ? qust_details[:owner_image] = question_owner_profile.thumb_picture_url : qust_details[:owner_image] = nil
        logined_user = User.find_by_reecher_id(params[:user_id])
        @voting = Voting.where(:user_id=> logined_user.id, :question_id=> qust_details.id) 
          if @voting.blank?
           is_login_user_starred_qst = false
          else  
           is_login_user_starred_qst = true
          end
        @solutions = []        
        @lk = LinkedQuestion.find_by_question_id(params[:question_id])    
        @pqtfs = PostQuestionToFriend.where(:question_id=>params[:question_id])  
        reecher_user_associated_to_question=@pqtfs.collect{|pq| pq.friend_reecher_id}  if !@pqtfs.blank?
        
        question_asker = qust_details.posted_by_uid
        question_asker_name = qust_details.posted_by
        question_is_public = qust_details.is_public
        if ((logined_user.reecher_id ==  question_asker) || question_is_public)
           qust_details[:question_referee] = qust_details.posted_by   
           qust_details[:no_profile_pic] = false 
        elsif(!@pqtfs.blank? && (reecher_user_associated_to_question.include? logined_user.reecher_id.to_s)) 
           qust_details[:question_referee] = qust_details.posted_by   
           qust_details[:no_profile_pic] = false 
        else          
           qust_details[:question_referee] = "Friend"  
           qust_details[:no_profile_pic] = true 
        end    
            
       # if @lk.blank?               
         #if @pqtfs.blank?
           #reecher_user_associated_to_question=@pqtfs.collect{|pq| pq.reecher_id}                 
         #end
       #end
     
        
        if solutions.size > 0
          puts "Solutions 2 === #{solutions.inspect}"
          solutions.each do |sl|
            solution_attrs = sl.attributes
            user = User.find_by_reecher_id(sl.solver_id)
             user.user_profile.picture_file_name != nil ? solution_attrs[:solver_image] = user.user_profile.thumb_picture_url : solution_attrs[:solver_image] = nil
            sl.picture_file_name != nil ? solution_attrs[:image_url] = sl.picture_url : solution_attrs[:image_url] = nil
            ############
            check_friend = Friendship::are_friends(logined_user.reecher_id,sl.solver_id)
            purchased_sl = PurchasedSolution.where(:user_id => logined_user.id, :solution_id => sl.id)
        
            puts "11zero   = check_friend == #{check_friend.inspect}"
            puts "11ONE   = logined_user == #{logined_user.full_name},   logined_user.reecher_id = #{logined_user.reecher_id}"
            puts "11TWO   = reecher_user_associated_to_question == #{reecher_user_associated_to_question.inspect}"
            puts "11THREE = question_owner.reecher_id      == #{question_owner.reecher_id}"
            puts "11FOUR  = user.reecher_id                == #{user.reecher_id}"
            puts "11FIVE  = sl.solver                      == #{sl.solver}"
            puts "11SIX =purchased_sl ====#{purchased_sl.inspect}"
            puts "11SEVEN =purchased_sl.present? ====#{purchased_sl.present?}" 
            puts "11EIGHT =purchased_sl_user_id ====#{purchased_sl[0]['user_id']}" if purchased_sl.present?
            puts "11NINE =logined_user_id====#{logined_user.id}"
            
       
          #  if (question_owner.reecher_id == logined_user.reecher_id) 
               if @lk.blank?   
                 
                   puts "I AM IN WITHOUT LINKED QUESTION BLOCK" 
                 # @pqtfs = PostQuestionToFriend.where(:question_id=>params[:question_id])            
                  if !@pqtfs.blank?
                   puts " I am on post question to friend block in without linked question "
                      
                      #  reecher_user_associated_to_question=@pqtfs.collect{|pq| pq.friend_reecher_id} 
                        if check_friend && ((reecher_user_associated_to_question.include? logined_user.reecher_id)||(reecher_user_associated_to_question.include? user.reecher_id))
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false  
                        elsif ((logined_user.reecher_id == question_owner.reecher_id) && (reecher_user_associated_to_question.include? user.reecher_id))
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false 
                        elsif(user.reecher_id.to_s == logined_user.reecher_id.to_s) 
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false 
                        elsif (purchased_sl.present? && (purchased_sl[0]['user_id'].to_s == logined_user.id.to_s))
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false     
                        elsif !check_friend && ((reecher_user_associated_to_question.include? logined_user.reecher_id) && ((reecher_user_associated_to_question.include? user.reecher_id)))
                        solution_attrs[:solution_provider_name] =  "Friend of #{question_owner.first_name}"
                        solution_attrs[:no_profile_pic] = false   
                        elsif !check_friend && (!(reecher_user_associated_to_question.include? logined_user.reecher_id) && (!(reecher_user_associated_to_question.include? user.reecher_id)))
                        solution_attrs[:solution_provider_name] =  "Friend of Friend"
                        solution_attrs[:no_profile_pic] = true               
                        else                        
                        solution_attrs[:solution_provider_name] = "Friend"
                        solution_attrs[:no_profile_pic] = true 
                        end             
                
                  else
                        puts "SIX     = check_friend == #{check_friend.inspect}"
                        puts "SEVEN   = purchased_sl == #{purchased_sl.inspect}"
                        if check_friend && purchased_sl.present?
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false 
                        elsif check_friend && (!(reecher_user_associated_to_question.include? logined_user.reecher_id)||(!reecher_user_associated_to_question.include? user.reecher_id))
                        solution_attrs[:solution_provider_name] = sl.solver
                        solution_attrs[:no_profile_pic] = false  
                        elsif (check_friend && (!purchased_sl.present?))
                        solution_attrs[:solution_provider_name] = "Friend"
                        solution_attrs[:no_profile_pic] = truhece 
                        elsif (check_friend && (!reecher_user_associated_to_question.include? logined_user.reecher_id))
                         solution_attrs[:solution_provider_name] = sl.solver
                         solution_attrs[:no_profile_pic] = false 
                        elsif user.reecher_id == logined_user.reecher_id
                         solution_attrs[:solution_provider_name] = sl.solver
                         solution_attrs[:no_profile_pic] = false 
                        else                      
                         solution_attrs[:solution_provider_name] = "Friend"
                         solution_attrs[:no_profile_pic] = true
                        end  
                  end
              else
                  
                  puts "I AM IN LINKED QUESTION BLOCK" 
                  
                  puts "LINKED QUESTION DETAILS=#{@lk.inspect}"
                  
                   linker_reecher_id = @lk.linked_by_uid
                   
                   puts "ELEVEN   = linker_reecher_id == #{linker_reecher_id.inspect}"
                      
                   linked_by_reecher_id = @lk.user_id  
                   
                   linker_user_details = User.find_by_reecher_id(linker_reecher_id)  
                  
                  
                  check_friend_with_linker_user = Friendship::are_friends(logined_user.reecher_id,linker_reecher_id)
                   
                  check_friend_with_linked_user = Friendship::are_friends(logined_user.reecher_id,linked_by_reecher_id)
                   
                 
                  
                  if (user.reecher_id.to_s == logined_user.reecher_id.to_s)
                    solution_attrs[:solution_provider_name] = sl.solver
                    solution_attrs[:no_profile_pic] = false 
                  elsif(purchased_sl.present?)
                    solution_attrs[:solution_provider_name] = sl.solver
                    solution_attrs[:no_profile_pic] = false 
                  elsif(check_friend && (reecher_user_associated_to_question.include? logined_user.reecher_id)) 
                    solution_attrs[:solution_provider_name] = sl.solver
                    solution_attrs[:no_profile_pic] = false 
                  elsif((logined_user.reecher_id == linker_reecher_id)  && (user.reecher_id == linked_by_reecher_id ))
                    solution_attrs[:solution_provider_name] = sl.solver
                    solution_attrs[:no_profile_pic] = false 
                  elsif (check_friend_with_linker_user &&  (!check_friend_with_linked_user) && (reecher_user_associated_to_question.include? logined_user.reecher_id || logined_user.reecher_id== question_owner.reecher_id))
                    solution_attrs[:solution_provider_name] = "Friend of #{linker_user_details.full_name}"
                    linker_user_details.user_profile.picture_file_name != nil ? solution_attrs[:solver_image] = linker_user_details.user_profile.thumb_picture_url : solution_attrs[:solver_image] = nil
                    solution_attrs[:no_profile_pic] = true
                  elsif(!check_friend_with_linker_user && !check_friend_with_linked_user)   
                    solution_attrs[:solution_provider_name] = "Friend of Friend"
                    solution_attrs[:no_profile_pic] = true 
                  elsif ((logined_user.reecher_id == question_owner.reecher_id ) && !check_friend_with_linker_user )   
                    solution_attrs[:solution_provider_name] = "Friend of Friend"
                    solution_attrs[:no_profile_pic] = true 
                  elsif (check_friend_with_linker_user &&  (!check_friend_with_linked_user) && (!reecher_user_associated_to_question.include? logined_user.reecher_id || logined_user.reecher_id == question_owner.reecher_id)) 
                    solution_attrs[:solution_provider_name] = "Friend of Friend"
                    solution_attrs[:no_profile_pic] = true
                  else
                    solution_attrs[:solution_provider_name] = "Friend"
                    solution_attrs[:no_profile_pic] = true  
                  end  
                  
                  
                  
              end
          # end
          ############
           
           
            if !sl.picture_file_name.blank?
           	sol_pic_geo=((sl.sol_pic_geometry).to_s).split('x') 	
  	        solution_attrs[:image_width]=sol_pic_geo[0]	
  	        solution_attrs[:image_height] = sol_pic_geo[1]
            end
            
          
              
          purchased_sl = PurchasedSolution.where(:user_id => logined_user.id, :solution_id => sl.id)
                  if purchased_sl.present?
                    solution_attrs[:purchased] = true
                  else
                    solution_attrs[:purchased] = false  
                  end 
            @solutions << solution_attrs
          end 
          sorted_sol = []
          
          @solutions.each do |sol|            
            if sol[:purchased]
            sorted_sol << sol
            end
            
          end
          @solutions.each do |sol|
            
            if !sol[:purchased]
            sorted_sol << sol
            end
          end  
         
        end
        msg = {:status => 200, :qust_details=>qust_details ,:solutions => sorted_sol,:is_login_user_starred_qst=>is_login_user_starred_qst} 
        logger.debug "******Response To #{request.remote_ip} at #{Time.now} => #{sorted_sol}"
        render :json => msg
      end  
          
      def post_solution_with_image
        
        @solver = User.find_by_reecher_id(params[:user_id])
        @solution = Solution.new()
        @solution.body = params[:solution]
        @solution.question_id = params[:question_id]
        @solution.solver_id = @solver.reecher_id
        @solution.solver = "#{@solver.first_name} #{@solver.last_name}"
        @solution.ask_charisma = params[:ask_charisma] 

        if !params[:file].blank? 
          @solution.picture = params[:file]
        end

        if !params[:expert_details].nil?
          if !params[:expert_details][:emails].nil?
            # if the expert is in reech network directly link the question 
            # Otherwise send an simple email to him
            params[:expert_details][:emails].each do |email|
              linked_user = User.find_by_email(email)
              if linked_user.present?
                linked_question = LinkedQuestion.where(:user_id => linked_user.reecher_id, :question_id => params[:question_id], :linked_by_uid => @solver.reecher_id)
                if !linked_question.present?
                  link_question = LinkedQuestion.new
                  link_question.user_id = linked_user.reecher_id
                  link_question.question_id = params[:question_id]
                  link_question.linked_by_uid = @solver.reecher_id
                  link_question.save
                end 
              else
                   begin
                      UserMailer.send_link_question_email(email, @solver).deliver
                    rescue Exception => e
                      logger.error e.backtrace.join("\n")
                    end
                
              end 
            end 
          end

          if !params[:expert_details][:phone_numbers].nil?
            client = Twilio::REST::Client.new(TWILIO_CONFIG['sid'], TWILIO_CONFIG['token'])
            params[:expert_details][:phone_numbers].each do |number|
              begin
              sms = client.account.sms.messages.create(
                      from: TWILIO_CONFIG['from'],
                      to: number,
                      body: "your friend #{@solver.first_name} #{@user.last_name}  want to solve his friend's question on Reech."
                  )
                  logger.debug ">>>>>>>>>Sending sms to #{number} with text #{sms.body}"
             rescue Exception => e
                      logger.error e.backtrace.join("\n")
             end
            end
          end 
       end  
       
        
      
        
        if @solution.save
            # send push notification to user who posted this question
            qust_details = Question.find_by_question_id(params[:question_id])
            #user_details = User.includes(:questions).where("questions.question_id" =>params[:question_id]) 
            puts "question posted by= #{qust_details.posted_by_uid}"
            
            #delete_linked_question(@solver.reecher_id,qust_details.question_id)
            
            if !qust_details.nil?
               check_setting= check_notify_question_when_answered(qust_details.posted_by_uid)
               puts "check_setting==#{check_setting}"
               if check_setting
                #device_details = Device.where("reecher_id=?",user_details[0][:posted_by_uid].to_s)
              
                device_details=Device.select("device_token,platform").where("reecher_id=?",qust_details.posted_by_uid.to_s)
                #puts "device_details==#{deimplicit conversion of Fixnum into Svice_details.inspect}"
                response_string ="PRSLN,"+ @solution.solver + ","+params[:question_id]+","+Time.now().to_s
                
                if !device_details.empty? 
                    device_details.each do |d|
                      
                   # begin
                      send_device_notification(d[:device_token].to_s, response_string ,d[:platform].to_s,@solution.solver+PUSH_TITLE_PRSLN)
                    #rescue Exception => e
                    #  logger.error e.backtrace.join("\n")
                    #end
                    end  
                end 
               end            
            end
            
=begin           
           # Send push notification to those who starred this question
           @voting = Voting.where(question_id: params[:question_id])
           if @voting.blank?
            @voting = Voting.new do |v|
            response_string ="PRSLN,"+ @solution.solver + ","+params[:question_id]
             check_setting= notify_solution_got_highfive(v.user_id)
             if check_setting
              device_details = Device.select("device_token,platform").where("reecher_id=?",qust_details.posted_by_uid.to_s)
              response_string ="HGHFV,"+ @solution.solver + ","+params[:question_id]+"," +Time.now().to_s
              if !device_details.blank?   
                 device_details.each do |d|
                    begin
                      send_device_notification(d[:device_token].to_s, response_string ,d[:platform].to_s)
                    rescue Exception => e
                      logger.error e.backtrace.join("\n")
                    end
                 end
              end
             end
           end
          end
=end        
          msg = {:status => 200, :solution => @solution}
          
        else
          msg = {:status => 400, :message => "Failed"}
        end 
        render :json => msg
        
      end    
        
		def check_one_time_bonus_distribution (q_id,sol_id,asker_id)
		 flag =true ;
		  purchased_sl_for_q_id = PurchasedSolution.where(:user_id =>asker_id ,:solution_id=>sol_id)
		  tot_row = purchased_sl_for_q_id.size
		  if tot_row >1
		  flag =false
		  end
		  flag 
		        
		end
		
		def delete_linked_question user_id , question_id
		  @lk = LinkedQuestion.where("user_id = ? and question_id = ? ", user_id , question_id)
      #question_owner = User.find_by_reecher_id(question.posted_by_uid)
      if !@lk.blank?
        @lk.destroy   
      end
		  
		end
=begin		
		def make_friendship_standard(friends, user)
		#  Friendship.create(:reecher_id=>friends,:friend_reecher_id=>user,:status=>"accepted")
		# Friendship.create(:reecher_id=>user,:friend_reecher_id=>friends,:status=>"accepted")		 
		friend =  Friendship.new()
		friend.reecher_id = friends
		friend.friend_reecher_id = user
		friend.status = "accepted"
		friend.save

    friend2 =  Friendship.new()
    friend2.reecher_id = user
    friend2.friend_reecher_id = friends
    friend2.status = "accepted"
    friend2.save
    end  
=end		
		end
	end
end			