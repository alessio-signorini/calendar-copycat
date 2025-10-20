require 'google/apis/calendar_v3'
require 'googleauth'

class GoogleAuth
  SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR
  
  # Get authenticated Calendar API client for an account
  def self.get_client(account_id)
    refresh_token = ENV["ACCOUNT_#{account_id.upcase}_REFRESH_TOKEN"]
    raise "Missing refresh token for account: #{account_id}" unless refresh_token
    
    # Create credentials with refresh token
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      scope: SCOPE,
      refresh_token: refresh_token
    )
    
    # Refresh to get access token
    credentials.fetch_access_token!
    
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = credentials
    service
  end
  
  # Generate OAuth authorization URL
  def self.auth_url(account_id, redirect_uri)
    client_id = Google::Auth::ClientId.new(
      ENV['GOOGLE_CLIENT_ID'],
      ENV['GOOGLE_CLIENT_SECRET']
    )
    
    authorizer = Google::Auth::UserAuthorizer.new(
      client_id,
      SCOPE,
      Google::Auth::Stores::InMemoryTokenStore.new
    )
    
    authorizer.get_authorization_url(base_url: redirect_uri)
  end
  
  # Exchange authorization code for tokens
  def self.exchange_code(code, redirect_uri)
    client_id = Google::Auth::ClientId.new(
      ENV['GOOGLE_CLIENT_ID'],
      ENV['GOOGLE_CLIENT_SECRET']
    )
    
    authorizer = Google::Auth::UserAuthorizer.new(
      client_id,
      SCOPE,
      Google::Auth::Stores::InMemoryTokenStore.new
    )
    
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: 'default',
      code: code,
      base_url: redirect_uri
    )
    
    # Get user email from Calendar API
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = credentials
    
    calendar_list = service.list_calendar_lists(max_results: 1)
    email = calendar_list.items.first&.id || 'unknown'
    
    {
      refresh_token: credentials.refresh_token,
      access_token: credentials.access_token,
      email: email
    }
  end
end
