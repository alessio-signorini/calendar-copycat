require 'time'
require 'google/apis/calendar_v3'

class EventTransformer
  def initialize(destination_config, source_account, source_calendar)
    @config = destination_config['event'] || {}
    @source_account = source_account
    @source_calendar = source_calendar
  end
  
  def transform(source_event, title_groups)
    event = Google::Apis::CalendarV3::Event.new
    
    # Transform title
    event.summary = apply_template(@config['title'], title_groups) || source_event.summary
    
    # Transform description
    if @config.key?('description')
      event.description = apply_template(@config['description'], title_groups)
    else
      event.description = source_event.description
    end
    
    # Transform location
    if @config.key?('location')
      event.location = @config['location']
    else
      event.location = source_event.location
    end
    
    # Transform time
    time_delta = @config['time_delta'] || {}
    start_minutes = time_delta['start_minutes'] || 0
    end_minutes = time_delta['end_minutes'] || 0
    
    if source_event.start.date_time
      # Regular timed event
      start_time = Time.parse(source_event.start.date_time.to_s)
      end_time = Time.parse(source_event.end.date_time.to_s)
      
      event.start = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: apply_time_delta(start_time, start_minutes),
        time_zone: source_event.start.time_zone
      )
      
      event.end = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: apply_time_delta(end_time, end_minutes),
        time_zone: source_event.end.time_zone
      )
    else
      # All-day event
      event.start = Google::Apis::CalendarV3::EventDateTime.new(
        date: source_event.start.date
      )
      event.end = Google::Apis::CalendarV3::EventDateTime.new(
        date: source_event.end.date
      )
    end
    
    # Set color
    event.color_id = @config['color_id'].to_s if @config['color_id']
    
    # Set visibility
    event.visibility = @config['visibility'] if @config['visibility']
    
    # Set attendees
    if @config.key?('attendees')
      if @config['attendees'].is_a?(Array)
        event.attendees = @config['attendees'].map do |email|
          Google::Apis::CalendarV3::EventAttendee.new(email: email)
        end
      end
    else
      event.attendees = source_event.attendees
    end
    
    # Set reminders
    if @config['reminders']
      event.reminders = Google::Apis::CalendarV3::Event::Reminders.new(
        use_default: @config['reminders']['use_default'] || false,
        overrides: (@config['reminders']['overrides'] || []).map do |reminder|
          Google::Apis::CalendarV3::EventReminder.new(
            method: reminder['method'],
            minutes: reminder['minutes']
          )
        end
      )
    end
    
    # Add extended properties for tracking
    event.extended_properties = Google::Apis::CalendarV3::Event::ExtendedProperties.new(
      private: {
        'copied_from_account' => @source_account,
        'copied_from_calendar' => @source_calendar,
        'copied_from_event' => source_event.id
      }
    )
    
    event
  end
  
  private
  
  def apply_template(template, groups)
    return nil if template.nil?
    return template unless template.is_a?(String)
    return template if groups.empty?
    
    result = template.dup
    groups.each_with_index do |group, index|
      result.gsub!("$#{index}", group.to_s)
    end
    result
  end
  
  def apply_time_delta(time, delta_minutes)
    return time if delta_minutes == 0
    time + (delta_minutes * 60)
  end
end
