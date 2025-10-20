# Calendar Copycat 📅

A Ruby/Sinatra application that runs on Fly.io to synchronize Google Calendar events between multiple accounts based on configurable YAML rules. The application is stateless (no database) and runs on a scheduled basis.

## Features

- ✅ **Stateless Operation** - No database required, uses in-memory lookups
- 🔐 **OAuth 2.0** - Secure authentication with Google Calendar API
- 📋 **Flexible Rules** - YAML-based configuration for sync rules
- 🎯 **Smart Filtering** - Filter by title patterns, time ranges, attendee count, and more
- 🔄 **Automatic Updates** - Updates destination events when source changes
- 🗑️ **Deletion Handling** - Removes destination events when source is deleted
- 🎨 **Event Transformation** - Customize titles, descriptions, colors, and more
- ⏰ **Scheduled Sync** - Runs every 15 minutes (configurable)
- 🚀 **Fly.io Ready** - Configured for easy deployment

## Quick Start

### Prerequisites

- Ruby 3.2.0 or later
- Google Cloud Project with Calendar API enabled
- Fly.io account (for deployment)

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/calendar-copycat.git
   cd calendar-copycat
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Set up Google OAuth credentials**

   Create a Google Cloud Project:
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create a new project
   - Enable Google Calendar API
   - Create OAuth 2.0 credentials (Web application)
   - Add authorized redirect URI: `http://localhost:8080/oauth/callback`
   - Download credentials

   Set environment variables:
   ```bash
   export GOOGLE_CLIENT_ID="your_client_id"
   export GOOGLE_CLIENT_SECRET="your_client_secret"
   ```

4. **Start the application**
   ```bash
   ruby app.rb
   ```

5. **Authenticate your Google accounts**
   - Visit `http://localhost:8080`
   - Click "Authenticate Personal Account" or "Authenticate Work Account"
   - Complete OAuth flow
   - Copy the displayed environment variable command
   - Run it in your terminal

6. **Configure sync rules**
   - Edit `config/rules.yaml`
   - Define your sync rules (see examples below)

7. **Test sync**
   - Visit `http://localhost:8080`
   - Click "Run Sync Now"

## Configuration

### Environment Variables

#### Required

- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
- `ACCOUNT_{ID}_REFRESH_TOKEN` - Refresh token for each account (generated via OAuth)

#### Optional

- `SYNC_INTERVAL_MINUTES` - Sync interval in minutes (default: 15)
- `ENABLE_SCHEDULER` - Enable internal scheduler (default: false, use external cron)
- `SESSION_SECRET` - Secret for session encryption (auto-generated if not set)

### Rules Configuration

Edit `config/rules.yaml` to define sync rules. See the example configuration in the file for detailed options.

#### Basic Rule Structure

```yaml
rules:
  - name: "Rule name"
    source:
      account: work
      calendar: primary
      filters:
        title_pattern: "^Meeting.*"
        time:
          hour_range:
            min: 9
            max: 18
          days_of_week: [1, 2, 3, 4, 5]
    destination:
      account: personal
      calendar: "Work Meetings"
      event:
        title: "🏢 $0"
        color_id: "9"
        visibility: private
    behavior:
      update_existing: true
      delete_on_source_deletion: true
```

### Filter Options

**Title Pattern**
- Regex pattern for matching event titles
- Supports capture groups ($0, $1, $2, etc.)

**Time Filters**
- `hour_range`: Filter by hour range (24-hour format, min inclusive, max exclusive)
- `hours`: List of specific hours
- `days_of_week`: Days to sync (0=Sunday, 6=Saturday)

**Property Filters**
- `not_all_day`: Skip all-day events
- `attendee_count`: Min/max number of attendees
- `response_status`: Filter by your response (accepted, declined, tentative, needsAction)

**Transformations**
- `title`: Transform title using regex capture groups
- `description`: Transform or clear description
- `location`: Transform or clear location
- `time_delta`: Add/subtract minutes from start/end time
- `color_id`: Set calendar color (1-11)
- `visibility`: Set visibility (public, private, confidential)
- `attendees`: Override attendee list
- `reminders`: Override reminders

## Deployment to Fly.io

1. **Install Fly CLI**
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. **Login to Fly.io**
   ```bash
   fly auth login
   ```

3. **Create app**
   ```bash
   fly launch
   ```

4. **Set secrets**
   ```bash
   fly secrets set GOOGLE_CLIENT_ID="your_client_id"
   fly secrets set GOOGLE_CLIENT_SECRET="your_client_secret"
   ```

5. **Deploy**
   ```bash
   fly deploy
   ```

6. **Authenticate accounts**
   - Visit `https://your-app.fly.dev/auth/personal`
   - Complete OAuth flow
   - Run the displayed `fly secrets set` command

7. **Setup scheduled sync**

   Option A: Use Fly.io Machines with cron (recommended)
   ```bash
   # Add to fly.toml or use fly-cron
   ```

   Option B: Use external cron service (e.g., cron-job.org)
   - Create a cron job that calls `https://your-app.fly.dev/cron/sync`
   - Set to run every 15 minutes

   Option C: Enable internal scheduler
   ```bash
   fly secrets set ENABLE_SCHEDULER="true"
   fly secrets set SYNC_INTERVAL_MINUTES="15"
   fly deploy
   ```

## Architecture

### No Database Required

- Uses in-memory lookups during each sync run
- OAuth refresh tokens stored in environment variables
- Event tracking via Google Calendar extended properties
- Stateless operation between runs

### Duplicate Detection

Events are tracked using extended properties:
```ruby
extended_properties: {
  private: {
    'copied_from_account' => 'work',
    'copied_from_calendar' => 'primary',
    'copied_from_event' => 'event_id_123'
  }
}
```

On each sync:
1. Fetch all destination events in time window
2. Build in-memory map: `source_event_id => destination_event`
3. For each source event, check if it exists in map
4. Create new or update existing accordingly

## API Endpoints

- `GET /` - Home page with setup instructions
- `GET /auth/:account_id` - Start OAuth flow for account
- `GET /oauth/callback` - OAuth callback handler
- `POST /sync` - Manually trigger sync (returns JSON)
- `POST /cron/sync` - Cron endpoint for scheduled sync
- `GET /status` - Status endpoint (returns JSON)

## Development

### Using VS Code Dev Containers

This project includes a Dev Container configuration:

1. Install Docker and VS Code
2. Install "Dev Containers" extension
3. Open project in VS Code
4. Click "Reopen in Container"
5. Dependencies will be installed automatically

### Using GitHub Codespaces

1. Click "Code" → "Codespaces" → "Create codespace"
2. Wait for environment to build
3. Dependencies will be installed automatically
4. Port 8080 will be forwarded automatically

## Testing

### Manual Testing Checklist

- [ ] OAuth flow works for multiple accounts
- [ ] Events are created with correct transformations
- [ ] Title regex capture groups work
- [ ] Time filters work (hours, days of week)
- [ ] Property filters work (attendee count, all-day, etc.)
- [ ] Events are updated when source changes
- [ ] Events are deleted when source is deleted
- [ ] Time deltas are applied correctly
- [ ] Multiple rules run in sequence
- [ ] Duplicate events are not created

### Edge Cases

- All-day events (no dateTime, only date)
- Recurring events vs single events
- Events with no attendees
- Events spanning multiple days
- Timezone handling
- Empty/missing fields in source events

## Logging

All logs are written to stdout in the format:
```
[TIMESTAMP] [LEVEL] [Component] Message
```

**Log Levels:**
- `INFO` - Sync started/completed, events created/updated/deleted
- `WARN` - Non-fatal issues, API rate limits
- `ERROR` - Failures, auth errors, missing config

## Security Considerations

- Never commit refresh tokens to git
- Use Fly.io secrets for all sensitive data
- Rotate tokens periodically
- Extended properties are private (not visible to other users)
- Consider adding authentication to `/sync` endpoint for production

## Troubleshooting

### OAuth Errors

- Check that redirect URI matches in Google Cloud Console
- Verify GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are set correctly
- Ensure Calendar API is enabled in Google Cloud Project

### Sync Errors

- Check logs: `fly logs` (for Fly.io) or console output (local)
- Verify refresh tokens are set: `fly secrets list`
- Test configuration: Visit `/status` endpoint
- Validate YAML: `ruby -ryaml -e "puts YAML.load_file('config/rules.yaml')"`

### Missing Events

- Check time window (default 14 days)
- Verify filters in rules.yaml
- Test regex patterns: Use online regex tester
- Check event response status filter

## Performance

### API Usage

For each rule per sync:
- 1 API call to list source events
- 1 API call to list destination events
- N API calls to create/update/delete events

Google Calendar API allows ~1000 requests per 100 seconds per user.
With 15-minute intervals and 2-3 rules, this is well within limits.

### Memory Usage

In-memory maps scale with number of events in time window.
Estimate: ~1KB per event × 100 events × 5 calendars = ~500KB (negligible)

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

## Support

For issues and questions:
- Open a GitHub issue
- Check `docs/build.md` for detailed specifications

---

Built with ❤️ using Ruby and Sinatra
