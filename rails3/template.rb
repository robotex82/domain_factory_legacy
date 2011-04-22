say "################################################################################"
say "# Checking prerequisites"
say "################################################################################"

say "Checking for the capistrano gem..."
begin
  gem 'capistrano'
rescue GEM::LoadError
  if yes?('Capistrano is currenty not installed. Install Capistrano on your local system? (yes/no)')
    run "sudo gem install capistrano" 
  else
    exit
  end    
end

say "[ok]"

say "################################################################################"
say "# Tell me about your configuration"
say "################################################################################"

say "DomainFactory"
say "============="
domainfactory_customer_number = ask("Enter your customer number (i.e.: 123456_12345):")

say "SSH"
say "==="
domain       = ask("Enter the domain name to connect to your webspace via ssh (i.e.: example.com):")
ssh_username = ask("Enter your ssh username (i.e.: ssh-123456-ssh): ")
ssh_password = ask("Enter your ssh password (i.e.: ssh_foobar): ")

say "Database"
say "========"
database    = ask("Enter your mysql database name (i.e.: db123456_1): ")
db_username = ask("Enter the database username (i.e.: db123456_1): ")
db_password = ask("Enter the database password (i.e.: db_foobar): ")

say "GitHub"
say "======"
repository = ask("Enter the github repository address (i.e.: git@github.com:johndoe/example_application.git): ")

say "Application"
say "==========="
application_name = ask("Enter your application name (i.e.: example_application):")


say "################################################################################"
say "# Configuring your application"
say "################################################################################"

################################################################################
# Configure .gitignore
################################################################################
remove_file '.gitignore'
file '.gitignore', <<-CODE.gsub(/^ {2}/, '')
  .bundle
  db/*.sqlite3
  log/*.log
  tmp/**/*
  *~
  webrat.log
CODE

################################################################################
# Gemfile for domain factory
################################################################################

inject_into_file 'Gemfile', :after => "# end"  do
<<-RUBY.gsub(/^ {2}/, '')

  group :staging, :production do
    gem 'mysql', '2.7'
  end  
  
  group :test, :development do
    gem 'sqlite3'
  end  
  
  group :development do
    gem 'capistrano'
  end    
RUBY
end

################################################################################
# config.ru for domain factory
################################################################################

inject_into_file 'config.ru', :before => "require ::File.expand_path('../config/environment',  __FILE__)" do
<<-RUBY.gsub(/^ {2}/, '')
if (File.dirname(__FILE__).include?('staging') || File.dirname(__FILE__).include?('production'))
  GEM_HOME = '/kunden/#{domainfactory_customer_number}/#{application_name}/.gem'
  GEM_PATH = '/kunden/#{domainfactory_customer_number}/#{application_name}/.gem:/usr/lib/ruby/gems/1.8'
end  
RUBY
end

################################################################################
# Capistrano configuration
################################################################################
capify!

deploy_to        = "/kunden/#{domainfactory_customer_number}/#{application_name}/production"

remove_file 'config/deploy.rb'
file 'config/deploy.rb', <<-FILE
set :application, "#{application_name}"

default_run_options[:pty]   = true  # Must be set for the password prompt from git to work
ssh_options[:forward_agent] = true  # Use local ssh keys
set :repository,  "#{repository}"
set :branch, "master"
set :deploy_via, :remote_cache


set :scm, :git
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`

role :web, "#{domain}"                   # Your HTTP server, Apache/etc
role :app, "#{domain}"                   # This may be the same as your `Web` server
role :db,  "#{domain}", :primary => true # This is where Rails migrations will run

set :user,     "#{ssh_username}" # DomainFactory SSH User: ssh-xxxxxx-???
set :password, "#{ssh_password}" # DomainFactory SSH Password
set :use_sudo, false        # Don't use sudo

# Deployment path on DomainFactory:
# /kunden/xxxxxx_xxxxx/foo_app
set :deploy_to, "/kunden/#{domainfactory_customer_number}/#{application_name}/production"

after "deploy:symlink", "#{deploy_to}"

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
end

namespace :bundle do
  desc "Install bundle without development and test"
  task :install, :roles => :app do
    run <<-CMD
      cd \#{current_path}; bundle install --path=/kunden/#{domainfactory_customer_number}/#{application_name}/.gem --without development test
    CMD
  end
  
  desc "Symlinks your machine specific bundle to your rails app"
  task :symlink, :roles => :app do
    run <<-CMD
      mkdir \#{shared_path}/.bundle
      ln -nfs \#{shared_path}/.bundle \#{release_path}/.bundle
    CMD
  end
end

namespace :domain_factory do
  desc "Symlinks the domain factory mysql gem to your gem path"
  task :copy_mysql_gem, :roles => :app do
    run <<-CMD
      mkdir /kunden/#{domainfactory_customer_number}/.gem/gems
      cd /kunden/#{domainfactory_customer_number}/.gem/gems
      rm -rf ./mysql-2.7
      
      ln -nfs /usr/lib/ruby/gems/1.8/gems/mysql-2.7 /kunden/#{domainfactory_customer_number}/.gem/gems/mysql-2.7
    CMD
  end
end

FILE

################################################################################
# Database configuration
################################################################################

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

production:
  adapter: mysql
  host: mysql5.#{domain}
  encoding: utf8
  reconnect: false
  database: #{database}
  pool: 5
  username: #{db_username}
  password: #{db_password}
  socket: /var/run/mysqld/mysqld.sock
FILE

################################################################################
# Initialize git repo and add github master
################################################################################
git :init
git :add => "."
git :commit => "-aqm 'Initial commit.'"
git :remote => "add origin #{repository}"


################################################################################
# Push the application to github
################################################################################
git :push => "-u origin master"

################################################################################
# Run capistrano
################################################################################
