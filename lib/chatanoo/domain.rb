require 'securerandom'

module Chatanoo

  class Domain < Thor
    class_option :env, required: true, aliases: '-e', desc: 'Select your environment'

    def initialize(*args)
      super
      @config = YAML::load(File.open("#{ENV['HOME']}/.chatanoo/#{options[:env]}.yml")) if options[:env]
      @route53 = Aws::Route53::Client.new({
        region: @config[:aws_region],
        credentials: Aws::Credentials.new(
          @config[:aws_access_key_id],
          @config[:aws_secret_access_key]
        )
      })
    end

    desc "create DOMAIN", "create domain"
    def create(domain)
      begin
        resp = @route53.create_hosted_zone({
          name: "#{domain}.",
          caller_reference: SecureRandom.uuid
        })
        @route53.change_tags_for_resource({
          resource_type: resp.hosted_zone.id.split('/')[1],
          resource_id: resp.hosted_zone.id.split('/')[2],
          add_tags: [
            { key: "chatanoo:env", value: @config[:env] },
            { key: "chatanoo:type", value: 'production' },
            { key: "chatanoo:role", value: 'hosting' }
          ]
        })
      rescue Exception => err
        say Rainbow("Fail to create the hosted zone!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- #{domain} hosted zone created!").green

      @config[:route53] = {} unless @config[:route53]
      @config[:route53][domain] = resp.hosted_zone
      save_config
    end

    desc "delete DOMAIN", "delete domain"
    def delete(domain)
      begin
        zone = @config[:route53][domain]
        @route53.delete_hosted_zone({
          id: zone.id
        })
      rescue Exception => err
        say Rainbow("Fail to delete the hosted zone!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- #{domain} hosted zone deleted!").green

      @config[:route53].delete(domain)
      save_config
    end

    private
    def save_config
      filename = "#{ENV['HOME']}/.chatanoo/#{@config[:env]}.yml"
      File.open(filename, "w") do |f|
        f.write( @config.to_yaml )
      end
    end
  end

  class CLI < Thor
    desc "domain COMMANDS", "Domain Controller"
    subcommand "domain", Chatanoo::Domain
  end

end
