require 'sinatra'
require 'rufus-scheduler'
require_relative 'lib/google_auth'
require_relative 'lib/rule_parser'
require_relative 'lib/calendar_sync'

# Configure Sinatra
set :port, ENV['PORT'] || 8080
set :bind, '0.0.0.0'

# Initialize rule parser
def get_rule_parser
  @rule_parser ||= RuleParser.new('config/rules.yaml')
end

# Run sync for all rules
def run_sync
  rule_parser = get_rule_parser
  results = []
  
  rule_parser.rules.each do |rule|
    begin
      sync = CalendarSync.new(rule, rule_parser)
      result = sync.sync!
      results << { rule: rule['name'], status: 'success', stats: result }
    rescue => e
      puts "[ERROR] [App] Sync failed for rule '#{rule['name']}': #{e.message}"
      puts e.backtrace.join("\n")
      results << { rule: rule['name'], status: 'error', error: e.message }
    end
  end
  
  results
end

# Home page
get '/' do
  erb :index
end

# OAuth flow - start
get '/auth/:account_id' do
  account_id = params[:account_id]
  redirect_uri = "#{request.scheme}://#{request.host_with_port}/oauth/callback"
  
  auth_url = GoogleAuth.auth_url(account_id, redirect_uri)
  
  # Store account_id in session for callback
  session[:account_id] = account_id
  
  redirect auth_url
end

# OAuth callback
get '/oauth/callback' do
  code = params[:code]
  account_id = session[:account_id] || 'unknown'
  
  redirect_uri = "#{request.scheme}://#{request.host_with_port}/oauth/callback"
  
  begin
    result = GoogleAuth.exchange_code(code, redirect_uri)
    
    @account_id = account_id
    @email = result[:email]
    @refresh_token = result[:refresh_token]
    
    erb :oauth_success
  rescue => e
    "OAuth error: #{e.message}"
  end
end

# Manual sync trigger
post '/sync' do
  content_type :json
  
  begin
    results = run_sync
    { status: 'success', results: results }.to_json
  rescue => e
    status 500
    { status: 'error', error: e.message }.to_json
  end
end

# Cron sync endpoint (for Fly.io or external cron)
post '/cron/sync' do
  begin
    results = run_sync
    { status: 'success', results: results }.to_json
  rescue => e
    status 500
    { status: 'error', error: e.message }.to_json
  end
end

# Status endpoint
get '/status' do
  content_type :json
  
  begin
    rule_parser = get_rule_parser
    {
      status: 'ok',
      rules_count: rule_parser.rules.size,
      accounts: rule_parser.accounts.keys
    }.to_json
  rescue => e
    status 500
    { status: 'error', error: e.message }.to_json
  end
end

# Internal scheduler (optional - can also use external cron)
if ENV['ENABLE_SCHEDULER'] == 'true'
  scheduler = Rufus::Scheduler.new
  
  interval = ENV['SYNC_INTERVAL_MINUTES'] || '15'
  
  scheduler.every "#{interval}m" do
    puts "[INFO] [Scheduler] Running scheduled sync"
    run_sync
  end
  
  puts "[INFO] [Scheduler] Scheduler started with #{interval} minute interval"
end

# Enable sessions for OAuth flow
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(32)
