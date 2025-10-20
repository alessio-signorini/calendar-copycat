require_relative 'google_auth'
require_relative 'event_matcher'
require_relative 'event_transformer'

class CalendarSync
  def initialize(rule, rule_parser)
    @rule = rule
    @rule_parser = rule_parser
    
    # Get source and destination clients
    @source_account = rule['source']['account']
    @source_calendar = rule['source']['calendar']
    @source_client = GoogleAuth.get_client(@source_account)
    
    @dest_account = rule['destination']['account']
    @dest_calendar = rule['destination']['calendar']
    @dest_client = GoogleAuth.get_client(@dest_account)
    
    # Initialize helper objects
    @matcher = EventMatcher.new(rule['source']['filters'])
    @transformer = EventTransformer.new(rule['destination'], @source_account, @source_calendar)
  end
  
  def sync!
    puts "[INFO] [CalendarSync] Starting sync for rule: #{@rule['name']}"
    
    # Calculate time window
    time_window_days = @rule.dig('behavior', 'time_window_days') ||
                      @rule_parser.sync_settings['default_time_window_days'] ||
                      14
    
    time_min = Time.now.iso8601
    time_max = (Time.now + (time_window_days * 24 * 60 * 60)).iso8601
    
    # Fetch events
    source_events = fetch_source_events(time_min, time_max)
    dest_events = fetch_destination_events(time_min, time_max)
    
    puts "[INFO] [CalendarSync] Found #{source_events.size} source events, #{dest_events.size} destination events"
    
    # Build lookup map
    dest_map = build_destination_map(dest_events)
    
    # Process source events
    processed_ids = []
    created_count = 0
    updated_count = 0
    
    source_events.each do |source_event|
      next unless @matcher.matches?(source_event)
      
      processed_ids << source_event.id
      title_groups = @matcher.extract_title_groups(source_event)
      
      if dest_map[source_event.id]
        if update_event(source_event, dest_map[source_event.id], title_groups)
          updated_count += 1
        end
      else
        if create_event(source_event, title_groups)
          created_count += 1
        end
      end
    end
    
    # Handle deletions
    deleted_count = 0
    if @rule.dig('behavior', 'delete_on_source_deletion')
      deleted_count = handle_deletions(dest_map, processed_ids)
    end
    
    puts "[INFO] [CalendarSync] Sync complete: #{created_count} created, #{updated_count} updated, #{deleted_count} deleted"
    
    {
      created: created_count,
      updated: updated_count,
      deleted: deleted_count
    }
  end
  
  private
  
  def fetch_source_events(time_min, time_max)
    begin
      result = @source_client.list_events(
        @source_calendar,
        time_min: time_min,
        time_max: time_max,
        single_events: true,
        order_by: 'startTime'
      )
      result.items || []
    rescue => e
      puts "[ERROR] [CalendarSync] Failed to fetch source events: #{e.message}"
      []
    end
  end
  
  def fetch_destination_events(time_min, time_max)
    begin
      result = @dest_client.list_events(
        @dest_calendar,
        time_min: time_min,
        time_max: time_max,
        single_events: true
      )
      result.items || []
    rescue => e
      puts "[ERROR] [CalendarSync] Failed to fetch destination events: #{e.message}"
      []
    end
  end
  
  def build_destination_map(events)
    map = {}
    events.each do |event|
      next unless event.extended_properties
      next unless event.extended_properties.private
      
      source_event_id = event.extended_properties.private['copied_from_event']
      source_account = event.extended_properties.private['copied_from_account']
      source_calendar = event.extended_properties.private['copied_from_calendar']
      
      # Only map events that were copied from this specific source
      if source_event_id && source_account == @source_account && source_calendar == @source_calendar
        map[source_event_id] = event
      end
    end
    map
  end
  
  def create_event(source_event, title_groups)
    begin
      transformed_event = @transformer.transform(source_event, title_groups)
      @dest_client.insert_event(@dest_calendar, transformed_event)
      puts "[INFO] [CalendarSync] Created event: #{transformed_event.summary}"
      true
    rescue => e
      puts "[ERROR] [CalendarSync] Failed to create event: #{e.message}"
      false
    end
  end
  
  def update_event(source_event, dest_event, title_groups)
    return false unless @rule.dig('behavior', 'update_existing')
    
    # Optional optimization: skip if source hasn't been updated
    if source_event.updated && dest_event.updated
      return false if source_event.updated <= dest_event.updated
    end
    
    begin
      transformed_event = @transformer.transform(source_event, title_groups)
      @dest_client.update_event(@dest_calendar, dest_event.id, transformed_event)
      puts "[INFO] [CalendarSync] Updated event: #{transformed_event.summary}"
      true
    rescue => e
      puts "[ERROR] [CalendarSync] Failed to update event: #{e.message}"
      false
    end
  end
  
  def handle_deletions(dest_map, processed_ids)
    deleted_count = 0
    
    dest_map.each do |source_event_id, dest_event|
      next if processed_ids.include?(source_event_id)
      
      begin
        @dest_client.delete_event(@dest_calendar, dest_event.id)
        puts "[INFO] [CalendarSync] Deleted orphaned event: #{dest_event.summary}"
        deleted_count += 1
      rescue => e
        puts "[ERROR] [CalendarSync] Failed to delete event: #{e.message}"
      end
    end
    
    deleted_count
  end
end
