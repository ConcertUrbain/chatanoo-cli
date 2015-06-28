module Chatanoo

  class CLI < Thor
    desc "init", "Initialize the command-line tool"
    def init
      say Rainbow("Create a new environment in AWS").bright.green
      say Rainbow("Please respond to this form")
      say Rainbow("A new file shoulb be created in your home folder")
      say ""

      params = {}

      params[:env] = ask( Rainbow("Environment name? ").bright ) { |q| q.validate = /[a-z\-]*/ }

      params[:aws_access_key_id] =     ask( Rainbow("AWS Access Key ID? ").bright ) { |q| q.validate = /[A-Z0-9]{20}/ }
      params[:aws_secret_access_key] = ask( Rainbow("AWS Secret Access Key? ").bright ) { |q| q.validate = /[a-zA-Z0-9+]{40}/ }
      say Rainbow("AWS Region? ").bright
      params[:aws_region] = choose do |m|
        m.prompt = Rainbow("Please select your region? ")
        m.choices(
          "us-east-1",
          "us-west-2",
          "us-west-1",
          "eu-west-1",
          "eu-central-1",
          "ap-southeast-1",
          "ap-southeast-2",
          "ap-northeast-1",
          "sa-east-1"
        )
      end

      params[:domain] = ask( Rainbow("Your domain name? ").bright ) { |q| q.validate = /^([a-zA-Z0-9][a-zA-Z0-9\-_]{1,61}[a-zA-Z0-9]\.){1,}[a-zA-Z]{2,}$/ }

      say ""
      say Rainbow("A new user will be created to manager your infratructure ").bright
      params[:login] = ask( Rainbow("His login? ").bright ) { |q| q.validate = /^[a-zA-Z._-]*/ }
      params[:email] = ask( Rainbow("His email? ").bright ) { |q| q.validate = /[a-z0-9]+[_a-z0-9\.-]*[a-z0-9]+@[a-z0-9-]+(\.[a-z0-9-]+)*(\.[a-z]{2,4})/ }

      filename = "#{ENV['HOME']}/.chatanoo/#{params[:env]}.yml"
      dirname = File.dirname(filename)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end
      File.open(filename, "w") do |f|
        f.write( params.to_yaml )
      end

      say ""
      say Rainbow("#{filename} created!").bright.green
    end

    desc "list", "List available environments"
    def list
      say Rainbow("Available environments:").bright
      Dir["#{ENV['HOME']}/.chatanoo/*"].each do |file|
        say "- #{File.basename(file, '.*')}"
      end
    end

  end

end
