# frozen_string_literal: true

module Api
    module V1
        class TicketsController < ApplicationController
            before_action :set_ticket, only: %i[show update destroy]
            before_action :set_organization
            before_action :set_creator, only: [:create]
            before_action :set_ticket, only: %i[show update destroy assign_to_user escalate_to_problem]
        
            # GET /organizations/:organization_id/tickets
        
            # def index
            #   valid_statuses = %w[open assigned escalated closed suspended resolved]
            
            #   # Validate the status query parameter
            #   if params[:status].present? && !valid_statuses.include?(params[:status])
            #     return render json: { error: 'Invalid status. Allowed values are: open, assigned, escalated, closed, suspended, resolved.' }, status: :unprocessable_entity
            #   end
            
            #   # Fetch tickets for a specific organization
            #   if params[:organization_id].present?
            #     @tickets = Ticket.where(organization_id: params[:organization_id])
            
            #     # Filter tickets by user if user_id is provided
            #     @tickets = @tickets.where(user_id: params[:user_id]) if params[:user_id].present?
            
            #     # Filter tickets by status if provided
            #     @tickets = @tickets.where(status: params[:status]) if params[:status].present?
            
            #     render json: @tickets
            #   else
            #     render json: { error: 'organization_id is required.' }, status: :unprocessable_entity
            #   end
            # end
        
            def index
                valid_statuses = %w[open assigned escalated closed suspended resolved pending]
                valid_categories = %w[technical billing support hardware software other] # Add your valid categories here
            
                # Validate the status query parameter
                if params[:status].present? && !valid_statuses.include?(params[:status])
                return render json: { error: 'Invalid status. Allowed values are: open, assigned, escalated, closed, suspended, resolved, pending.' }, status: :unprocessable_entity
                end
            
                # Validate the category query parameter
                if params[:category].present? && !valid_categories.include?(params[:category])
                return render json: { error: 'Invalid category. Allowed values are: technical, billing, support, hardware, software, other.' }, status: :unprocessable_entity
                end
            
                # Fetch tickets for a specific organization
                if params[:organization_id].present?
                @tickets = Ticket.where(organization_id: params[:organization_id])
            
                # Filter tickets by user if user_id is provided
                if params[:user_id].present?
                    @tickets = @tickets.where(assignee_id: params[:user_id])
                end
            
                # Filter tickets by status if provided
                if params[:status].present?
                    @tickets = @tickets.where(status: params[:status])
                end
            
                # Filter tickets by category if provided
                if params[:category].present?
                    @tickets = @tickets.where(category: params[:category])
                end
            
                render json: @tickets
                else
                render json: { error: 'organization_id is required.' }, status: :unprocessable_entity
                end
            end
            # GET /organizations/:organization_id/tickets/:id
            def show
            render json: @ticket
            end
        
            # POST /organizations/:organization_id/tickets
            def create
            @ticket = @organization.tickets.new(ticket_params)
            @ticket.creator = @creator # Set the creator of the ticket
            @ticket.requester = @creator # Set the requester to the creator by default (can be overridden in params)
        
            # Ensure the team belongs to the organization
            if params[:ticket][:team_id].present?
                team = @organization.teams.find_by(id: params[:ticket][:team_id])
                unless team
                return render json: { error: "Team not found in this organization" }, status: :unprocessable_entity
                end
                @ticket.team = team
            end
        
            if @ticket.save
                render json: @ticket, status: :created, location: organization_ticket_url(@organization, @ticket)
            else
                render json: { errors: @ticket.errors.full_messages }, status: :unprocessable_entity
            end
            end
        
            # PATCH/PUT /organizations/:organization_id/tickets/:id
            def update
            # Ensure the team belongs to the organization (if team_id is being updated)
            if params[:ticket][:team_id].present?
                team = @organization.teams.find_by(id: params[:ticket][:team_id])
                unless team
                return render json: { error: "Team not found in this organization" }, status: :unprocessable_entity
                end
                @ticket.team = team
            end
        
            # Ensure the assignee belongs to the team (if assignee_id is being updated)
            if params[:ticket][:assignee_id].present?
                assignee = @ticket.team.users.find_by(id: params[:ticket][:assignee_id])
                unless assignee
                return render json: { error: "Assignee not found in the team" }, status: :unprocessable_entity
                end
                @ticket.assignee = assignee
            end
        
            if @ticket.update(ticket_params)
                render json: @ticket
            else
                render json: { errors: @ticket.errors.full_messages }, status: :unprocessable_entity
            end
            end
        
            # DELETE /organizations/:organization_id/tickets/:id
            def destroy
            @ticket.destroy!
            head :no_content
            end
        
            # POST /organizations/:organization_id/tickets/:id/assign_to_user
        
            def assign_to_user
            # Ensure the current user is a team lead for the ticket's team
            unless current_user.teamlead? && current_user.team == @ticket.team
                return render json: { error: "You are not authorized to assign this ticket" }, status: :unauthorized
            end
        
            # Find the user within the team
            assignee = @ticket.team.users.find_by(id: params[:user_id])
            unless assignee
                return render json: { error: "User not found in the team" }, status: :unprocessable_entity
            end
        
            # Assign the ticket to the user
            if @ticket.update(assignee: assignee)
                # Enqueue the job to send emails
                SendTicketAssignmentEmailsJob.perform_later(@ticket, @ticket.team, assignee)
        
                # Create a system notification for the assigned user, scoped to the organization
                Notification.create!(
                user: assignee,
                organization: @ticket.organization, # Associate with the organization
                message: "You have been assigned a new ticket: #{@ticket.title}",
                read: false,
                metadata: { ticket_id: @ticket.id } # Optional: Include additional metadata
                )
        
                render json: @ticket, status: :ok
            else
                render json: { errors: @ticket.errors.full_messages }, status: :unprocessable_entity
            end
            end
        
            # POST /organizations/:organization_id/tickets/:id/escalate_to_problem
            def escalate_to_problem
            # Ensure the current user is a team lead
            unless current_user.teamlead?
                render json: { error: "Only team leads can escalate tickets to problems" }, status: :forbidden
                return
            end
        
            # Ensure the ticket is an incident
            unless @ticket.incident?
                render json: { error: "Only incident tickets can be escalated to problems" }, status: :unprocessable_entity
                return
            end
        
            # Create a new problem from the ticket
            problem = Problem.create!(
                description: @ticket.description,
                organization: @ticket.organization,
                team: @ticket.team,
                creator: current_user,
                reported_at: Time.current
            )
        
            # Link the ticket to the problem
            @ticket.update!(problem: problem)
        
            render json: { message: "Ticket escalated to problem", problem: ProblemSerializer.new(problem) }, status: :created
            end
        
            private
        
            # Use callbacks to share common setup or constraints between actions.
            def set_ticket
            @ticket = Ticket.find(params[:id])
            end
        
            # Set the organization based on the organization_id in the URL
            def set_organization
            @organization = Organization.find(params[:organization_id])
            rescue ActiveRecord::RecordNotFound
            render json: { error: 'Organization not found' }, status: :not_found
            end
        
            # Set the creator of the ticket (current user)
            def set_creator
            @creator = current_user
            unless @creator
                render json: { error: "User not authenticated" }, status: :unauthorized
            end
            end
        
            # Only allow a list of trusted parameters through
            def ticket_params
            params.require(:ticket).permit(
                :title, :description, :ticket_type, :status, :urgency, :priority, :impact,
                :assignee_id, :team_id, :category, :caller_name, :caller_surname, :caller_email,
                :caller_phone, :customer, :source, :reported_at, :requester_id
            ).tap do |ticket_params|
                # Ensure required fields are present
                required_fields = [
                :title, :description, :ticket_type, :status, :urgency, :priority, :impact,
                :team_id, :category, :caller_name, :caller_surname, :caller_email, :caller_phone,
                :customer, :source, :reported_at
                ]
                required_fields.each do |field|
                ticket_params.require(field) # Raise ActionController::ParameterMissing if any required field is missing
                end
            end
            end
        end
    end
end
