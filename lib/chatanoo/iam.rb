module Chatanoo

  class Iam < Thor
    class_option :env, required: true, aliases: '-e', desc: 'Select your environment'

    def initialize(*args)
      super
      $config = YAML::load(File.open("#{ENV['HOME']}/.chatanoo/#{options[:env]}.yml")) if options[:env]
      @iam = Aws::IAM::Client.new({
        region: $config[:aws_region],
        credentials: Aws::Credentials.new(
          $config[:aws_access_key_id],
          $config[:aws_secret_access_key]
        )
      })
    end

    desc "create_role NAME CONTENT", "create IAM role"
    def create_role(name, content)
      begin
        policy_resp = @iam.create_policy({
          policy_name: "chatanoo-#{$config[:env]}-#{name}-policy",
          policy_document: content
        })
        resp = @iam.create_role({
          role_name: "chatanoo-#{$config[:env]}-#{name}-role",
          assume_role_policy_document: '{"Version":"2008-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":["sts:AssumeRole"]}]}'
        })
        @iam.attach_role_policy({
          role_name: "chatanoo-#{$config[:env]}-#{name}-role",
          policy_arn: policy_resp.policy.arn
        })
      rescue Exception => err
        say Rainbow("Fail to create role!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- #{name} role created!").green

      $config[:iam] = {} unless $config[:iam]
      $config[:iam][name] = {
        role: resp.role.arn,
        policy: policy_resp.policy.arn
      }
      save_config
    end

    desc "delete_role NAME", "delete IAM role"
    def delete_role(name)
      begin
        @iam.detach_role_policy({
          role_name: "chatanoo-#{$config[:env]}-#{name}-role",
          policy_arn: $config[:iam][name][:policy]
        })
        @iam.delete_role({
          role_name: "chatanoo-#{$config[:env]}-#{name}-role"
        })
        @iam.delete_policy({
          policy_arn: $config[:iam][name][:policy]
        })
      rescue Exception => err
        say Rainbow("Fail to delete role!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- #{name} role deleted!").green

      $config[:iam].delete(name)
      save_config
    end

    private
    def save_config
      filename = "#{ENV['HOME']}/.chatanoo/#{$config[:env]}.yml"
      File.open(filename, "w") do |f|
        f.write( $config.to_yaml )
      end
    end
  end

  class CLI < Thor
    desc "iam COMMANDS", "Domain Controller"
    subcommand "iam", Chatanoo::Iam
  end

end
