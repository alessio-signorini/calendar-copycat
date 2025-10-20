require 'yaml'

class RuleParser
  attr_reader :config
  
  def initialize(yaml_path = 'config/rules.yaml')
    @config = YAML.load_file(yaml_path)
    validate!
  end
  
  def rules
    @config['rules'] || []
  end
  
  def accounts
    accounts_array = @config['accounts'] || []
    accounts_array.each_with_object({}) do |account, hash|
      hash[account['id']] = account
    end
  end
  
  def sync_settings
    @config['sync_settings'] || {}
  end
  
  def validate!
    # Check required top-level keys
    raise "Missing 'accounts' in configuration" unless @config['accounts']
    raise "Missing 'rules' in configuration" unless @config['rules']
    
    # Validate accounts
    @config['accounts'].each do |account|
      raise "Account missing 'id' field" unless account['id']
      
      # Check for refresh token ENV var
      env_var = "ACCOUNT_#{account['id'].upcase}_REFRESH_TOKEN"
      puts "WARNING: Missing environment variable #{env_var}" unless ENV[env_var]
    end
    
    # Validate rules
    @config['rules'].each_with_index do |rule, index|
      raise "Rule #{index} missing 'name'" unless rule['name']
      raise "Rule #{index} missing 'source'" unless rule['source']
      raise "Rule #{index} missing 'destination'" unless rule['destination']
      
      # Validate source
      source_account = rule['source']['account']
      raise "Rule '#{rule['name']}': source account '#{source_account}' not found in accounts" unless accounts[source_account]
      
      # Validate destination
      dest_account = rule['destination']['account']
      raise "Rule '#{rule['name']}': destination account '#{dest_account}' not found in accounts" unless accounts[dest_account]
    end
    
    true
  end
end
