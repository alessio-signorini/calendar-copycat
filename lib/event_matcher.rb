require 'time'

class EventMatcher
  def initialize(filters)
    @filters = filters || {}
    if @filters['title_pattern']
      begin
        @title_regex = Regexp.new(@filters['title_pattern'], Regexp::FIXEDENCODING)
      rescue RegexpError => e
        puts "[WARN] [EventMatcher] Invalid regex pattern: #{e.message}"
        @title_regex = nil
      end
    end
  end
  
  def matches?(event)
    return false unless matches_title?(event)
    return false unless matches_time?(event)
    return false unless matches_properties?(event)
    true
  end
  
  def extract_title_groups(event)
    return [] unless @title_regex
    return [] unless event.summary
    
    match = event.summary.match(@title_regex)
    return [] unless match
    
    # Return array with full match and capture groups
    [match[0]] + match.captures
  end
  
  private
  
  def matches_title?(event)
    return true unless @title_regex
    return false unless event.summary
    
    event.summary.match?(@title_regex)
  end
  
  def matches_time?(event)
    time_filters = @filters['time']
    return true unless time_filters
    
    # Get event start time
    start_time = parse_event_time(event)
    return true unless start_time # Can't filter if no time
    
    # Check hour range
    if time_filters['hour_range']
      hour_min = time_filters['hour_range']['min']
      hour_max = time_filters['hour_range']['max']
      hour = start_time.hour
      return false unless hour >= hour_min && hour < hour_max
    end
    
    # Check specific hours
    if time_filters['hours']
      hours = time_filters['hours']
      return false unless hours.include?(start_time.hour)
    end
    
    # Check days of week
    if time_filters['days_of_week']
      days = time_filters['days_of_week']
      return false unless days.include?(start_time.wday)
    end
    
    true
  end
  
  def matches_properties?(event)
    # Check not_all_day filter
    if @filters['not_all_day']
      # All-day events have 'date' instead of 'dateTime'
      return false if event.start.date && !event.start.date_time
    end
    
    # Check attendee count
    if @filters['attendee_count']
      attendees = event.attendees || []
      count = attendees.size
      
      if @filters['attendee_count']['min']
        return false if count < @filters['attendee_count']['min']
      end
      
      if @filters['attendee_count']['max']
        return false if count > @filters['attendee_count']['max']
      end
    end
    
    # Check response status
    if @filters['response_status']
      expected_status = @filters['response_status']
      # Find the user's response status (look for 'self' attendee)
      attendees = event.attendees || []
      self_attendee = attendees.find { |a| a.self }
      
      if self_attendee
        return false unless self_attendee.response_status == expected_status
      end
    end
    
    true
  end
  
  def parse_event_time(event)
    return nil unless event.start
    
    if event.start.date_time
      Time.parse(event.start.date_time.to_s)
    elsif event.start.date
      Time.parse(event.start.date.to_s)
    else
      nil
    end
  end
end
