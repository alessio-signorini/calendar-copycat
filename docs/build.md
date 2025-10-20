# Calendar Copycat - Build Specifications

## Project Overview

A Ruby/Sinatra application that runs on Fly.io to synchronize Google Calendar events between multiple accounts based on configurable YAML rules. The application is stateless (no database) and runs on a scheduled basis (every 15 minutes).

## Architecture Principles

### No Database Required
- Use in-memory lookups during each sync run
- Store OAuth refresh tokens in Fly.io environment variables
- Use Google Calendar event extended properties to track copied events
- Stateless operation between runs

### Authentication Flow
1. One-time OAuth flow (can run locally or on Fly.io)
2. Generate refresh tokens for each Google account
3. Store refresh tokens as Fly.io secrets (environment variables)
4. App exchanges refresh token for access token on each run
5. Access tokens are never persisted

### Duplicate Detection
- Store source event metadata in destination event's extended properties:
  ```ruby
  extended_properties: {
    private: {
      'copied_from_account' => 'work',
      'copied_from_calendar' => 'primary',
      'copied_from_event' => 'event_id_123'
    }
  }
  ```
- On each sync run:
  1. Fetch all destination calendar events in time window
  2. Build in-memory map: `source_event_id => destination_event`
  3. For each source event, check if it exists in map
  4. Create new or update existing accordingly

### Event Updates
- **Strategy**: Update destination events when source changes
- **Implementation**: 
  - Compare source event ID in the in-memory map
  - If found, update the destination event
  - Use event's `updated` timestamp to optimize (optional)

### Event Deletions
- **Strategy**: Delete destination events when source is deleted
- **Implementation**:
  - Track which source event IDs were processed in current sync
  - Any destination events with `copied_from_event` not in processed list = source deleted
  - Delete those orphaned destination events

## File Structure

```
calendar-copycat/
├── Gemfile
├── Gemfile.lock
├── config.ru
├── fly.toml
├── README.md
├── config/
│   └── rules.yaml
├── app.rb (main Sinatra application)
├── lib/
│   ├── google_auth.rb (OAuth and token management)
│   ├── calendar_sync.rb (main sync orchestration)
│   ├── rule_parser.rb (YAML parsing and validation)
│   ├── event_matcher.rb (source event filtering)
│   └── event_transformer.rb (destination event creation)
└── views/
    └── oauth_success.erb (displays ENV vars after OAuth)
```

## Environment Variables

### Google OAuth Application Credentials
```bash
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
```

### Per-Account Refresh Tokens
Naming convention: `ACCOUNT_{ID}_REFRESH_TOKEN` where `{ID}` matches the account ID in rules.yaml (uppercased)

```bash
ACCOUNT_PERSONAL_REFRESH_TOKEN=ya29.xxx...
ACCOUNT_WORK_REFRESH_TOKEN=ya29.xxx...
```

### Optional Configuration
```bash
SYNC_INTERVAL_MINUTES=15  # How often to run sync
```

## YAML Configuration Structure

### Full Example (config/rules.yaml)

```yaml
sync_settings:
  default_time_window_days: 14  # How many days forward to sync

accounts:
  - id: personal  # Maps to ACCOUNT_PERSONAL_REFRESH_TOKEN
    email: you@gmail.com  # For validation/documentation
  - id: work  # Maps to ACCOUNT_WORK_REFRESH_TOKEN
    email: you@work.com

rules:
  - name: "Copy work meetings to personal calendar"
    
    # Source calendar and filters
    source:
      account: work  # References account ID above
      calendar: primary  # Calendar ID or "primary"
      
      filters:
        # Regex pattern for title matching (supports capture groups)
        title_pattern: "^(Meeting|1:1|Standup).*"
        
        # Time-based filters
        time:
          # Option A: Specific hours list (24-hour format)
          hours: [9, 10, 11, 12, 13, 14, 15, 16, 17]
          
          # Option B: Hour range (use this OR hours, not both)
          hour_range:
            min: 9   # Inclusive
            max: 18  # Exclusive (9 AM to 5:59 PM)
          
          # Days of week (0=Sunday, 1=Monday, ..., 6=Saturday)
          days_of_week: [1, 2, 3, 4, 5]  # Monday-Friday
        
        # Event property filters
        not_all_day: true  # Skip all-day events
        
        attendee_count:
          min: 2  # Only events with 2+ attendees
          max: 50  # Optional maximum
        
        response_status: accepted  # accepted, declined, tentative, needsAction
        
    # Destination calendar and transformations
    destination:
      account: personal
      calendar: "Work Meetings"  # Calendar ID or name
      
      event:
        # Title transformation
        # Use $0 for full match, $1, $2, etc. for capture groups from title_pattern
        title: "🏢 $1"
        
        # Description
        # Use $0, $1, etc. from regex
        # null = clear field
        # omit = keep original value
        description: "Copied from work calendar\n\nOriginal: $0"
        
        # Location (null to clear, omit to keep original)
        location: null
        
        # Time adjustments (minutes)
        time_delta:
          start_minutes: -15  # Start 15 minutes earlier
          end_minutes: 0      # Keep same end time
        
        # Visual properties
        color_id: "9"  # Google Calendar color ID (1-11)
        visibility: private  # public, private, confidential
        
        # Attendees
        attendees: []  # Empty array = no attendees, omit = keep original
        
        # Reminders
        reminders:
          use_default: false
          overrides:
            - method: popup  # popup, email
              minutes: 10
            - method: email
              minutes: 60
    
    # Sync behavior for this rule
    behavior:
      update_existing: true  # Update destination if source changes
      delete_on_source_deletion: true  # Delete destination if source deleted
      time_window_days: 14  # Override default, optional

  - name: "Copy personal appointments to work (privacy mode)"
    source:
      account: personal
      calendar: "Appointments"
      filters:
        title_pattern: "Doctor|Dentist|DMV|Appointment"
        time:
          days_of_week: [1, 2, 3, 4, 5]  # Weekdays only
    
    destination:
      account: work
      calendar: primary
      event:
        title: "🏥 Personal - Busy"
        description: null  # Clear for privacy
        location: null
        visibility: private
        # Omitted fields keep original values

  - name: "Simple copy with minimal transformation"
    source:
      account: work
      calendar: "Team Calendar"
      filters:
        title_pattern: "All Hands"
    destination:
      account: personal
      calendar: primary
      event:
        title: "$0 (Work)"  # $0 = full original title
    behavior:
      update_existing: true
      delete_on_source_deletion: false  # Keep as historical record
```

## Component Specifications

### 1. Google Authentication (lib/google_auth.rb)

**Responsibilities:**
- Handle OAuth 2.0 flow for Google Calendar API
- Exchange refresh tokens for access tokens
- Create authenticated Google Calendar API clients

**Key Methods:**
```ruby
class GoogleAuth
  # Get authenticated client for an account ID
  def self.get_client(account_id)
    # 1. Read refresh token from ENV["ACCOUNT_#{account_id.upcase}_REFRESH_TOKEN"]
    # 2. Create Signet::OAuth2::Client
    # 3. Exchange refresh token for access token
    # 4. Return authenticated client
  end
  
  # OAuth flow for initial setup
  def self.auth_url(account_id)
    # Generate OAuth authorization URL
  end
  
  def self.exchange_code(code)
    # Exchange authorization code for tokens
    # Return hash with refresh_token, access_token, email
  end
end
```

**Required Scopes:**
- `https://www.googleapis.com/auth/calendar` (read/write)
- OR `https://www.googleapis.com/auth/calendar.events` (events only)

### 2. Rule Parser (lib/rule_parser.rb)

**Responsibilities:**
- Load and parse YAML configuration
- Validate configuration structure
- Provide easy access to rules and settings

**Key Methods:**
```ruby
class RuleParser
  def initialize(yaml_path = 'config/rules.yaml')
    # Load YAML file
  end
  
  def rules
    # Return array of rule hashes
  end
  
  def accounts
    # Return hash of account_id => account_config
  end
  
  def sync_settings
    # Return global sync settings
  end
  
  def validate!
    # Check for:
    # - Required fields present
    # - Account IDs referenced in rules exist
    # - ENV vars exist for all accounts
    # Raise error if invalid
  end
end
```

### 3. Event Matcher (lib/event_matcher.rb)

**Responsibilities:**
- Filter source events based on rule criteria
- Match title patterns and extract capture groups
- Apply time-based filters
- Apply property filters (attendee count, response status, etc.)

**Key Methods:**
```ruby
class EventMatcher
  def initialize(filters)
    # Store filter configuration
    # Compile regex patterns
  end
  
  def matches?(event)
    # Return true if event matches ALL filters
    # Short-circuit on first non-match
  end
  
  def extract_title_groups(event)
    # Return array of regex capture groups from title
    # [full_match, group1, group2, ...]
  end
  
  private
  
  def matches_title?(event)
    # Check title_pattern regex
  end
  
  def matches_time?(event)
    # Check hour_range, hours, days_of_week
  end
  
  def matches_properties?(event)
    # Check not_all_day, attendee_count, response_status
  end
end
```

**Time Matching Details:**
- Parse event start time (handle both dateTime and date fields)
- For `hour_range`: `min <= hour < max` (min inclusive, max exclusive)
- For `hours`: `hour.in?(hours_array)`
- For `days_of_week`: `start_time.wday.in?(days_array)` (0=Sunday)

### 4. Event Transformer (lib/event_transformer.rb)

**Responsibilities:**
- Transform source events into destination events
- Apply title/description templates with regex capture groups
- Apply time deltas
- Set event properties

**Key Methods:**
```ruby
class EventTransformer
  def initialize(destination_config)
    # Store destination.event configuration
  end
  
  def transform(source_event, title_groups)
    # Create new event hash with transformed properties
    # title_groups = [$0, $1, $2, ...] from regex
    
    # Returns hash suitable for Google Calendar API:
    # {
    #   summary: "...",
    #   description: "...",
    #   start: { dateTime: "...", timeZone: "..." },
    #   end: { dateTime: "...", timeZone: "..." },
    #   colorId: "...",
    #   visibility: "...",
    #   attendees: [...],
    #   reminders: {...},
    #   extendedProperties: {
    #     private: {
    #       copied_from_account: "...",
    #       copied_from_calendar: "...",
    #       copied_from_event: "..."
    #     }
    #   }
    # }
  end
  
  private
  
  def apply_template(template, groups)
    # Replace $0, $1, $2, etc. with capture groups
    # Handle nil/null values
  end
  
  def apply_time_delta(time, delta_minutes)
    # Add/subtract minutes from DateTime
  end
end
```

**Template Replacement:**
- `$0` = full regex match (original title)
- `$1`, `$2`, etc. = capture groups from title_pattern
- If field is `null` in YAML → set to nil/empty
- If field is omitted in YAML → keep original value from source event

### 5. Calendar Sync (lib/calendar_sync.rb)

**Responsibilities:**
- Orchestrate the entire sync process
- Fetch events from source and destination calendars
- Build in-memory lookup maps
- Create, update, delete events as needed
- Handle errors and logging

**Key Methods:**
```ruby
class CalendarSync
  def initialize(rule, rule_parser)
    # Store rule configuration
    # Initialize source and destination clients
  end
  
  def sync!
    # Main sync workflow
    
    # 1. Fetch source events
    source_events = fetch_source_events
    
    # 2. Fetch destination events
    dest_events = fetch_destination_events
    
    # 3. Build lookup map
    dest_map = build_destination_map(dest_events)
    
    # 4. Process each source event
    processed_ids = []
    source_events.each do |source_event|
      next unless matcher.matches?(source_event)
      
      processed_ids << source_event.id
      title_groups = matcher.extract_title_groups(source_event)
      
      if dest_map[source_event.id]
        update_event(source_event, dest_map[source_event.id], title_groups)
      else
        create_event(source_event, title_groups)
      end
    end
    
    # 5. Handle deletions
    if rule['behavior']['delete_on_source_deletion']
      handle_deletions(dest_map, processed_ids)
    end
  end
  
  private
  
  def fetch_source_events
    # Get events from source calendar in time window
    # time_min = now
    # time_max = now + time_window_days
  end
  
  def fetch_destination_events
    # Get events from destination calendar in same time window
  end
  
  def build_destination_map(events)
    # Return hash: source_event_id => destination_event
    # Parse extended_properties.private.copied_from_event
  end
  
  def create_event(source, title_groups)
    # Transform and insert new event
    # Log success
  end
  
  def update_event(source, dest, title_groups)
    # Transform and update existing event
    # Skip if source.updated <= dest.updated (optimization)
    # Log success
  end
  
  def handle_deletions(dest_map, processed_ids)
    # Find events in dest_map not in processed_ids
    # Delete those events
    # Log deletions
  end
end
```

**Time Window Calculation:**
```ruby
time_window_days = rule['behavior']['time_window_days'] || 
                   sync_settings['default_time_window_days'] || 
                   14

time_min = Time.now.iso8601
time_max = (Time.now + (time_window_days * 24 * 60 * 60)).iso8601
```

### 6. Sinatra Application (app.rb)

**Responsibilities:**
- Provide OAuth callback endpoints
- Display setup instructions after OAuth
- Provide manual sync trigger endpoint
- Run scheduled sync (via rufus-scheduler or external cron)

**Routes:**

```ruby
# GET /
# Home page - status, last sync time, quick links

# GET /auth/:account_id
# Start OAuth flow for account
# Redirect to Google OAuth consent screen

# GET /oauth/callback
# Handle OAuth callback
# Exchange code for tokens
# Display page with ENV var instructions

# POST /sync
# Manually trigger sync for all rules
# Run sync, return summary

# GET /status
# JSON endpoint with sync status
```

**Scheduler Integration:**

Option A - Internal scheduler (rufus-scheduler):
```ruby
require 'rufus-scheduler'

scheduler = Rufus::Scheduler.new

scheduler.every '15m' do
  # Run sync for all rules
end
```

Option B - Fly.io cron (preferred):
```ruby
# Single endpoint that runs full sync
post '/cron/sync' do
  # Verify request from Fly.io (optional security)
  # Run sync
  # Return 200 OK
end
```

### 7. OAuth Success View (views/oauth_success.erb)

Display after successful OAuth:

```erb
<h1>Authentication Successful!</h1>

<p>Account: <%= @email %></p>

<h2>Add this secret to Fly.io:</h2>

<pre>
fly secrets set ACCOUNT_<%= @account_id.upcase %>_REFRESH_TOKEN="<%= @refresh_token %>"
</pre>

<p>After setting the secret, redeploy your app:</p>

<pre>
fly deploy
</pre>
```

## Dependencies (Gemfile)

```ruby
source 'https://rubygems.org'

ruby '3.2.0'  # or latest stable

gem 'sinatra'
gem 'puma'  # Web server
gem 'google-api-client'  # Google Calendar API
gem 'rufus-scheduler'  # Optional: for internal scheduling
gem 'yaml'  # YAML parsing (built-in)
```

## Fly.io Configuration (fly.toml)

```toml
app = "calendar-copycat"
primary_region = "sjc"  # or your preferred region

[build]
  builder = "heroku/buildpacks:20"

[env]
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0  # Scale to zero when not in use

# Option A: Scheduled machine (if supported for 15min intervals)
[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 256

# Option B: Use fly-cron or external service to call /cron/sync endpoint
```

## Deployment Process

### Initial Setup

1. Create Google Cloud Project and OAuth credentials:
   ```
   - Go to Google Cloud Console
   - Create new project
   - Enable Google Calendar API
   - Create OAuth 2.0 credentials (Web application)
   - Add authorized redirect URI: https://your-app.fly.dev/oauth/callback
   - Save client ID and secret
   ```

2. Set Google OAuth credentials in Fly.io:
   ```bash
   fly secrets set GOOGLE_CLIENT_ID="your_client_id"
   fly secrets set GOOGLE_CLIENT_SECRET="your_client_secret"
   ```

3. Deploy application:
   ```bash
   fly launch
   fly deploy
   ```

4. Complete OAuth for each account:
   ```
   - Visit https://your-app.fly.dev/auth/personal
   - Complete Google OAuth flow
   - Copy the displayed fly secrets set command
   - Run it locally
   ```

5. Add rules to `config/rules.yaml`

6. Redeploy:
   ```bash
   fly deploy
   ```

### Ongoing Updates

- Edit `config/rules.yaml`
- Run `fly deploy`
- Monitor logs: `fly logs`

## Error Handling and Logging

### Logging Strategy
- All logs to stdout (Fly.io captures automatically)
- Log levels: INFO, WARN, ERROR
- Log format: `[TIMESTAMP] [LEVEL] [Component] Message`

### What to Log

**INFO:**
- Sync started/completed
- Events created/updated/deleted
- OAuth token refreshed

**WARN:**
- Source event matches filter but transformation fails
- API rate limits hit (with retry)
- Destination calendar not found

**ERROR:**
- OAuth refresh fails
- API errors
- YAML validation errors
- Missing ENV variables

### Error Recovery

- **Transient errors** (network, rate limit): Retry with exponential backoff
- **Auth errors**: Log and skip that account (don't crash entire sync)
- **Invalid config**: Fail fast on startup with clear error message

## Testing Considerations

### Manual Testing Checklist

1. OAuth flow works for multiple accounts
2. Events are created with correct transformations
3. Title regex capture groups work
4. Time filters work (hours, days of week)
5. Property filters work (attendee count, all-day, etc.)
6. Events are updated when source changes
7. Events are deleted when source is deleted
8. Time deltas are applied correctly
9. Multiple rules can run in sequence
10. Duplicate events are not created

### Edge Cases to Handle

- All-day events (no dateTime, only date)
- Recurring events vs single events
- Events with no attendees
- Events spanning multiple days
- Timezone handling
- Empty/missing fields in source events
- Malformed regex patterns in YAML
- Missing calendars or insufficient permissions
- API rate limits (Calendar API: 1M requests/day)

## Performance Considerations

### API Call Optimization

For each rule:
- 1 API call to list source events
- 1 API call to list destination events
- N API calls to create/update/delete events

**Rate Limit**: Google Calendar API allows ~1000 requests per 100 seconds per user.

With 15-minute intervals and 2-3 rules, this is well within limits.

### Memory Usage

In-memory maps scale with:
- Number of events in time window
- Number of calendars

Estimate: ~1KB per event × 100 events × 5 calendars = ~500KB (negligible)

## Security Considerations

### Secrets Management
- Never commit refresh tokens to git
- Use Fly.io secrets for all sensitive data
- Rotate tokens periodically

### API Access
- Use minimal required OAuth scopes
- Consider adding authentication to `/sync` endpoint
- Verify requests to `/cron/sync` come from Fly.io

### Data Privacy
- Extended properties are private (not visible to other users)
- Consider adding option to encrypt event data
- Log filtering (don't log full event contents)

## Future Enhancements (Out of Scope)

- Web UI for managing rules
- Webhook support for real-time sync
- Bidirectional sync
- Support for other calendar providers (Outlook, etc.)
- Event conflict detection
- Email notifications on sync errors
- Sync history/audit log
- Rule testing/dry-run mode

## Success Criteria

The application is complete when:

1. ✅ OAuth flow generates refresh tokens for multiple accounts
2. ✅ Refresh tokens are stored in ENV and used to get access tokens
3. ✅ YAML rules are parsed and validated
4. ✅ Source events are filtered by title, time, and properties
5. ✅ Destination events are created with transformations applied
6. ✅ Regex capture groups work in title/description templates
7. ✅ Time deltas are applied correctly
8. ✅ Duplicate events are detected via extended properties
9. ✅ Existing events are updated when source changes
10. ✅ Destination events are deleted when source is deleted
11. ✅ Sync runs on schedule (every 15 minutes)
12. ✅ Application runs on Fly.io
13. ✅ All errors are logged to stdout
14. ✅ Multiple rules can run in a single sync cycle

## Implementation Order

Suggested build order:

1. **Setup project structure** - Gemfile, directory structure
2. **Google Auth module** - OAuth flow and token management
3. **Rule Parser** - YAML loading and validation
4. **Event Matcher** - Filtering logic (start with title, then time)
5. **Event Transformer** - Event transformation logic
6. **Calendar Sync** - Main orchestration (start with create only)
7. **Add update logic** - Detect and update existing events
8. **Add deletion logic** - Remove orphaned events
9. **Sinatra app** - Routes and OAuth UI
10. **Scheduler** - Add scheduled execution
11. **Fly.io deployment** - fly.toml and deployment
12. **Testing** - Manual testing of all features
13. **Documentation** - README with setup instructions

---

**END OF SPECIFICATIONS**
