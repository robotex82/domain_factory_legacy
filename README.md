# Features #

This template will preconfigure your rails app. It will:

  * Push your application to github
  * Configure you gem environment to work on domain factory
  * Modify the capistrano deploy script to suite your domain factory configuration
  * Use the domain factory mysql gem
  * Configure your production database
  * Upload you application to  github
  * Deploy your application to your domain factory server (coming soon!)
  
# Usage #

rails new [APP_NAME] -m https://github.com/robotex82/domain_factory/raw/master/rails3/template.rb

# Prerequisites #

To use this template, you'll need:

  * an account at domain factory
  * a configured ssh user in your domain factory account
  * a mysql database at your domain factory account
  * capistrano. If you don't have it, it will ask for it.
  * a github account and a fresh repository for your application
  * to configure your ssh keys in github


# Information, you need to collect before applying the template #

This template will ask you for following data:

## DomainFactory ##

customer number (i.e.: 123456_12345): 

## SSH ##

domain (i.e.: example.com):   
username (i.e.: ssh-123456-ssh): 
password (i.e.: ssh_foobar): 

## Database ##

database (i.e.: db123456_1): 
username (i.e.: db123456_1): 
password (i.e.: db_foobar): 

## GitHub Repository ##

address (i.e.: git@github.com:johndoe/example_application.git): 

## Application ##

name (i.e.: example_application): 
