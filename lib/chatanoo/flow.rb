module Chatanoo

  class CLI < Thor

    def initialize(*args)
      super
      @config = YAML::load(File.open("#{ENV['HOME']}/.chatanoo/#{options[:env]}.yml")) if options[:env]

      @domain = Chatanoo::Domain.new(*args)
      @s3 = Chatanoo::S3.new(*args)
      @transcoder = Chatanoo::Transcoder.new(*args)
    end

    desc "createall", "Create chatanoo environment on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def createall
      create_domain
      create_mediascenter
    end

    desc "create_domain", "Create chatanoo domain and CDN on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def create_domain
      @domain.create( @config[:domain] )
      @s3.create( "cdn", @config[:domain] )
      say Rainbow("#{@config[:domain]} domain created!").bright.green
    end

    desc "create_mediascenter", "Create chatanoo MediasCenter on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def create_mediascenter
      @s3.create( "medias-input" )
      @s3.create( "medias-output", @config[:domain] )
      @transcoder.create( "medias-input", "medias-output", "arn:aws:iam::175828319502:role/aws-transcoder-role" )
      say Rainbow("MediasCenter created!").bright.green
    end

    desc "deleteall", "Delete chatanoo environment on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def deleteall
      delete_mediascenter
      delete_domain
    end

    desc "delete_domain", "Delete chatanoo domain and CDN on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def delete_domain
      @domain.create( @config[:domain] )
      @s3.create( "cdn", @config[:domain] )
      say Rainbow("#{@config[:domain]} domain deleted!").bright.green
    end

    desc "delete_mediascenter", "Delete chatanoo MediasCenter on AWS"
    option :env, required: true, aliases: '-e', desc: 'Select your environment'
    def delete_mediascenter
      @s3.delete( "medias-input" )
      @s3.delete( "medias-output", @config[:domain] )
      @transcoder.delete
      say Rainbow("MediasCenter delete!").bright.green
    end
  end

end
