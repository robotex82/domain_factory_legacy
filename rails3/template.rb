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
# config.ru and config/boot.rb for domain factory
################################################################################

inject_into_file 'config.ru', :before => "require ::File.expand_path('../config/environment',  __FILE__)" do
<<-RUBY.gsub(/^ {2}/, '')
  if (File.dirname(__FILE__).include?('staging') || File.dirname(__FILE__).include?('production'))
    GEM_HOME = '/kunden/#{domainfactory_customer_number}/#{application_name}/.gem'
    GEM_PATH = '/kunden/#{domainfactory_customer_number}/#{application_name}/.gem:/usr/lib/ruby/gems/1.8'
  end  
  
RUBY
end

inject_into_file 'config/boot.rb', :before => "require 'rubygems'" do
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

after "deploy:symlink", "bundle:symlink"
after "deploy:setup", "bundle:configure"

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
      echo "BUNDLE_PATH: /kunden/#{domainfactory_customer_number}/#{application_name}/.gem" >> config;
    CMD
  end
  
  desc "Install bundle without development and test"
  task :install, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle install --path=/kunden/#{domainfactory_customer_number}/#{application_name}/.gem --without development test
    CMD
  end
  
  desc "Update bundle"
  task :update, :roles => :app do
    run <<-CMD
      cd \#{current_path}; 
      bundle update
    CMD
  end
  
  desc "Symlinks your machine specific bundle to your rails app"
  task :symlink, :roles => :app do
    run <<-CMD
      ln -nfs \#{shared_path}/.bundle \#{release_path}/.bundle;
    CMD
  end
end

namespace :domain_factory do
  desc "Symlinks the domain factory mysql gem to your gem path"
  task :replace_mysql_gem, :roles => :app do
    run <<-CMD
      cd /kunden/#{domainfactory_customer_number}/#{application_name}/.gem/ruby/1.8/gems;
      mv ./mysql-2.7 ./mysql-2.7-original;
      ln -nfs /usr/lib/ruby/gems/1.8/gems/mysql-2.7 ./mysql-2.7;
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
git :remote => "add origin #{repository}"


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
run "cap deploy:setup"
run "cap deploy:update"
run "cap bundle:install"
run "cap domain_factory:replace_mysql_gem"
run "cap deploy:migrate"
run "cap deploy:restart"

say "################################################################################"
say "# Finishing the configuration"
say "################################################################################"
say ""
say "Next steps:"
say "  * go to http://admin.df.eu and login to your account"
say "  * create a new subdomain (i.e. #{application_name}.#{domain})"
say "  * set the target to /#{application_name}/production/current/public"
say "  * activate rails support and set the path to '/'"
say ""
say "Your application should be fully deployed!"
say "Go, open http://#{application_name}.#{domain}/ in your browser!"
say ""
say "################################################################################"
say "# Developing"
say "################################################################################"
say ""
say "After each development cycle, you have to add your changes to git, commit, push"
say "and deploy:"
say ""
say "  $> git add ."
say "  $> git commit"
say "  $> git push"
say "  $> cap deploy"
