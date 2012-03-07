say "################################################################################"
say "# Checking prerequisites"
say "################################################################################"

%w(capistrano).each do |gem_name|
  say "Checking for the #{gem_name} gem..."
  begin
    gem gem_name
  rescue GEM::LoadError
    if yes?("#{gem_name} is currenty not installed. Install ? (yes/no)")
      run "gem install #{gem_name}" 
      gem gem_name
    else
      exit
    end    
  end
end


config_file = ask("Where is your config file?")

require 'yaml' 
configuration = ::YAML.load(File.read(File.expand_path("../#{config_file}")))


################################################################################
# Gemfile for domain factory
################################################################################

append_file 'Gemfile'  do
<<-RUBY.gsub(/^ {2}/, '')

  group :staging, :production do
    gem 'mysql', '2.7'
  end  
  
  group :test, :development do
    gem 'sqlite3'
  end  
  
  group :development do
    gem 'capistrano'
    gem 'capistrano-ext'
  end    
RUBY
end

################################################################################
# config.ru and config/boot.rb for domain factory
################################################################################

inject_into_file 'config.ru', :before => "require ::File.expand_path('../config/environment',  __FILE__)" do
<<-RUBY.gsub(/^ {2}/, '')
  if (File.dirname(__FILE__).include?('staging'))
    GEM_HOME = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem'
    GEM_PATH = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem:/usr/lib/ruby/gems/1.8'
  end  

  if (File.dirname(__FILE__).include?('production'))
    GEM_HOME = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem'
    GEM_PATH = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem:/usr/lib/ruby/gems/1.8'
  end 
   
RUBY
end

inject_into_file 'config/boot.rb', :before => "require 'rubygems'" do
<<-RUBY.gsub(/^ {2}/, '')
  if (File.dirname(__FILE__).include?('staging'))
    GEM_HOME = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem'
    GEM_PATH = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem:/usr/lib/ruby/gems/1.8'
  end  

  if (File.dirname(__FILE__).include?('production'))
    GEM_HOME = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem'
    GEM_PATH = '/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem:/usr/lib/ruby/gems/1.8'
  end  
  
RUBY
end

################################################################################
# staging environment
################################################################################
copy_file File.join(destination_root, 'config/environments/production.rb'), 'config/environments/staging.rb'

inject_into_file 'config/application.rb', :after => "require 'rails/all'" do
<<-RUBY.gsub(/^ {2}/, '')

  if (File.dirname(__FILE__).include?('staging'))
    Rails.env = ActiveSupport::StringInquirer.new('staging')
  end  
  
RUBY
end

################################################################################
# Capistrano configuration
################################################################################
run 'capify .'

remove_file 'config/deploy.rb'
file 'config/deploy.rb', <<-FILE
set :stages, %w(production staging)
set :default_stage, "staging"
require 'capistrano/ext/multistage'

set :application, "#{configuration['application']['name']}"

set :scm, :#{configuration['deployment']['scm']['type']}
set :repository, "#{configuration['deployment']['scm']['repository']}"
set :deploy_via, :remote_cache

default_run_options[:pty]   = true  # Must be set for the password prompt from git to work
ssh_options[:forward_agent] = true  # Use local ssh keys

after "deploy:symlink", "bundle:symlink"
after "deploy:setup", "bundle:configure"
FILE

empty_directory "config/deploy"

file 'config/deploy/staging.rb', <<-FILE
set :branch, "#{configuration['environments']['staging']['github']['branch']}"

role :web, "#{configuration['deployment']['ssh']['domain']}"                   # Your HTTP server, Apache/etc
role :app, "#{configuration['deployment']['ssh']['domain']}"                   # This may be the same as your `Web` server
role :db,  "#{configuration['deployment']['ssh']['domain']}", :primary => true # This is where Rails migrations will run

set :user,     "#{configuration['deployment']['ssh']['username']}" # DomainFactory SSH User: ssh-xxxxxx-???
set :password, "#{configuration['deployment']['ssh']['password']}" # DomainFactory SSH Password
set :use_sudo, false        # Don't use sudo

# Deployment path on DomainFactory:
# /kunden/xxxxxx_xxxxx/foo_app
set :deploy_to, "/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging"



# If you are using Passenger mod_rails uncomment this:
# if you're still using the script/reapear helper you will need
# these http://github.com/rails/irs_process_scripts

namespace :deploy do
  task :start do ; end
  task :stop do ; end
  
  desc "Restart the server"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "\#{try_sudo} touch \#{current_path}/tmp/restart.txt"
  end
  
  desc "Run database migrations"
  task :migrate, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle exec rake RAILS_ENV=staging db:migrate
    CMD
  end  
end

namespace :bundle do
  desc "Creates and initial bundle configuration"
  task :configure, :roles => :app do
    run <<-CMD
      cd \#{shared_path};
      mkdir ./.bundle;
      cd ./.bundle;
      touch config;
      echo "---" >> config;
      echo "BUNDLE_WITHOUT: development:test" >> config;
      echo "BUNDLE_PATH: /kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem" >> config;
    CMD
  end
  
  desc "Install bundle without development and test"
  task :install, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle install --path=/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/staging/.gem --without development test
    CMD
  end
  
  desc "Update bundle"
  task :update, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle
    CMD
  end
  
  desc "Symlinks your machine specific bundle to your rails app"
  task :symlink, :roles => :app do
    run <<-CMD
      ln -nfs \#{shared_path}/.bundle \#{release_path}/.bundle;
    CMD
  end
end
FILE

file 'config/deploy/production.rb', <<-FILE
set :branch, "#{configuration['environments']['production']['github']['branch']}"

role :web, "#{configuration['deployment']['ssh']['domain']}"                   # Your HTTP server, Apache/etc
role :app, "#{configuration['deployment']['ssh']['domain']}"                   # This may be the same as your `Web` server
role :db,  "#{configuration['deployment']['ssh']['domain']}", :primary => true # This is where Rails migrations will run

set :user,     "#{configuration['deployment']['ssh']['username']}" # DomainFactory SSH User: ssh-xxxxxx-???
set :password, "#{configuration['deployment']['ssh']['password']}" # DomainFactory SSH Password
set :use_sudo, false        # Don't use sudo

# Deployment path on DomainFactory:
# /kunden/xxxxxx_xxxxx/foo_app
set :deploy_to, "/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production"



# If you are using Passenger mod_rails uncomment this:
# if you're still using the script/reapear helper you will need
# these http://github.com/rails/irs_process_scripts

namespace :deploy do
  task :start do ; end
  task :stop do ; end
  
  desc "Restart the server"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "\#{try_sudo} touch \#{current_path}/tmp/restart.txt"
  end
  
  desc "Run database migrations"
  task :migrate, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle exec rake RAILS_ENV=production db:migrate
    CMD
  end  
end

namespace :bundle do
  desc "Creates and initial bundle configuration"
  task :configure, :roles => :app do
    run <<-CMD
      cd \#{shared_path};
      mkdir ./.bundle;
      cd ./.bundle;
      touch config;
      echo "---" >> config;
      echo "BUNDLE_WITHOUT: development:test" >> config;
      echo "BUNDLE_PATH: /kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem" >> config;
    CMD
  end
  
  desc "Install bundle without development and test"
  task :install, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle install --path=/kunden/#{configuration['domainfactory']['customer_number']}/#{configuration['application']['name']}/production/.gem --without development test
    CMD
  end
  
  desc "Update bundle"
  task :update, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle
    CMD
  end
  
  desc "Symlinks your machine specific bundle to your rails app"
  task :symlink, :roles => :app do
    run <<-CMD
      ln -nfs \#{shared_path}/.bundle \#{release_path}/.bundle;
    CMD
  end
end
FILE

################################################################################
# Database configuration
################################################################################

gsub_file "Gemfile", /gem \'mysql2\'/, "# gem 'mysql2'"

remove_file 'config/database.yml'
file 'config/database.yml', <<-FILE
# SQLite version 3.x
#   gem install sqlite3-ruby (not necessary on OS X Leopard)
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: 5
  timeout: 5000

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test:
  adapter: sqlite3
  database: db/test.sqlite3
  pool: 5
  timeout: 5000
  
staging:
  adapter: mysql
  host: #{configuration['environments']['staging']['database']['host']}
  encoding: utf8
  reconnect: false
  database: #{configuration['environments']['staging']['database']['name']}
  pool: 5
  username: #{configuration['environments']['staging']['database']['username']}
  password: #{configuration['environments']['staging']['database']['password']}
  socket: /var/run/mysqld/mysqld.sock

production:
  adapter: mysql
  host: #{configuration['environments']['production']['database']['host']}
  encoding: utf8
  reconnect: false
  database: #{configuration['environments']['production']['database']['name']}
  pool: 5
  username: #{configuration['environments']['production']['database']['username']}
  password: #{configuration['environments']['production']['database']['password']}
  socket: /var/run/mysqld/mysqld.sock
FILE

say "################################################################################"
say "# Installing your bundle"
say "################################################################################"
run "bundle install --without staging production"

say "################################################################################"
say "# Setting up git and pushing your application to the git repository"
say "################################################################################"

################################################################################
# Initialize git repo and add github master
################################################################################
git :init
git :add => "."
git :commit => "-aqm 'Initial commit.'"
git :remote => "add origin #{configuration['deployment']['scm']['repository']}"


################################################################################
# Push the application to github
################################################################################
git :push => "-u origin master"

say "################################################################################"
say "# Deploying"
say "################################################################################"

################################################################################
# Run capistrano
################################################################################

run "cap staging deploy:setup"
run "cap staging deploy:update"
run "cap staging bundle:install"
run "cap staging deploy:migrate"
run "cap staging deploy:restart"

run "cap production deploy:setup"
run "cap production deploy:update"
run "cap production bundle:install"
run "cap production deploy:migrate"
run "cap production deploy:restart"


say "################################################################################"
say "# Finishing the configuration"
say "################################################################################"
say ""
say "Next steps for staging:"
say "  * go to http://admin.df.eu and login to your account"
say "  * create a new subdomain (i.e. staging.#{configuration['deployment']['ssh']['domain']})"
say "  * set the target to /#{configuration['application']['name']}/staging/current/public"
say "  * activate rails support and set the path to '/'"
say ""
say "Next steps for production:"
say "  * go to http://admin.df.eu and login to your account"
say "  * create a new subdomain (i.e. www.#{configuration['deployment']['ssh']['domain']})"
say "  * set the target to /#{configuration['application']['name']}/production/current/public"
say "  * activate rails support and set the path to '/'"
say ""
say "Your application should be fully deployed!"
say "Go, open http://staging.#{configuration['deployment']['ssh']['domain']}/ in your browser for production!"
say "Go, open http://www.#{configuration['deployment']['ssh']['domain']}/ in your browser for production!"

