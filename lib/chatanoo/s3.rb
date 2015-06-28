require 'securerandom'

module Chatanoo

  class S3 < Thor
    class_option :env, required: true, aliases: '-e', desc: 'Select your environment'

    def initialize(*args)
      super
      $config = YAML::load(File.open("#{ENV['HOME']}/.chatanoo/#{options[:env]}.yml")) if options[:env]
      @s3 = Aws::S3::Client.new({
        region: $config[:aws_region],
        credentials: Aws::Credentials.new(
          $config[:aws_access_key_id],
          $config[:aws_secret_access_key]
        )
      })
      @route53 = Aws::Route53::Client.new({
        region: $config[:aws_region],
        credentials: Aws::Credentials.new(
          $config[:aws_access_key_id],
          $config[:aws_secret_access_key]
        )
      })
      @cloudFront = Aws::CloudFront::Client.new({
        region: $config[:aws_region],
        credentials: Aws::Credentials.new(
          $config[:aws_access_key_id],
          $config[:aws_secret_access_key]
        )
      })
    end

    desc "create NAME [DOMAIN]", "create s3 bucket with cloudfront and DNS record"
    def create(name, domain=nil)
      create_bucket(name)
      if domain
        create_dns_record(name, domain)
        create_cloudfront(name, domain)
      end
      save_config
    end

    desc "delete NAME [DOMAIN]", "delete s3 bucket"
    def delete(name, domain=nil)
      if domain
        delete_cloudfront(name, domain)
        delete_dns_record(name, domain)
      end
      delete_bucket(name)
      save_config
    end

    private
    def create_bucket(name)
      bucketName = "chatanoo-#{$config[:env]}-#{name}"
      begin
        @s3.create_bucket({
          acl: "public-read",
          bucket: bucketName,
          create_bucket_configuration: {
            location_constraint: $config[:aws_region]
          }
        })
        @s3.put_bucket_cors({
          bucket: bucketName,
          cors_configuration: {
            cors_rules: [
              {
                allowed_origins: ["*"],
                allowed_methods: ["HEAD", "GET", "PUT", "POST", "DELETE"],
                allowed_headers: ["*"],
                expose_headers: ["ETag", "x-amz-meta-custom-header"]
              },
            ],
          }
        })
        @s3.put_bucket_tagging({
          bucket: bucketName,
          tagging: {
            tag_set: [
              { key: "chatanoo:env", value: $config[:env] },
              { key: "chatanoo:type", value: 'production' },
              { key: "chatanoo:role", value: 'cdn' }
            ],
          },
        })
      rescue Exception => err
        say Rainbow("Fail to create s3 bucket!").red
        say Rainbow("Error: #{err}").red
        fail err
      end
      say Rainbow("- #{name} s3 bucket created!").green
    end

    def delete_bucket(name)
      bucketName = "chatanoo-#{$config[:env]}-#{name}"
      begin
        @s3.delete_bucket({
          bucket: bucketName
        })
      rescue Exception => err
        say Rainbow("Fail to delete s3 bucket!").red
        say Rainbow("Error: #{err}").red
        fail err
      end
      say Rainbow("- #{name} s3 bucket deleted!").green
    end

    def create_cloudfront(name, domain)
      bucketName = "chatanoo-#{$config[:env]}-#{name}"
      begin
        resp = @cloudFront.create_distribution({
          distribution_config: { # required
            comment: "CloudFront Distribution for #{bucketName} s3 bucket",
            enabled: true,
            caller_reference: SecureRandom.uuid, # required
            aliases: {
              quantity: 1, # required
              items: [
                "#{name}.#{domain}"
              ],
            },
            origins: { # required
              quantity: 1, # required
              items: [
                {
                  id: "s3-#{bucketName}", # required
                  domain_name: "#{bucketName}.s3.amazonaws.com", # required
                  s3_origin_config: {
                    origin_access_identity: "", # required
                  }
                },
              ],
            },
            default_cache_behavior: { # required
              target_origin_id: "s3-#{bucketName}", # required
              forwarded_values: { # required
                query_string: false, # required
                cookies: { # required
                  forward: "none", # required, accepts none, whitelist, all
                }
              },
              trusted_signers: { # required
                enabled: false, # required
                quantity: 0, # required
              },
              viewer_protocol_policy: "allow-all", # required, accepts allow-all, https-only, redirect-to-https
              min_ttl: 0, # required
              allowed_methods: {
                quantity: 2, # required
                items: ["GET", "HEAD"], # required, accepts GET, HEAD, POST, PUT, PATCH, OPTIONS, DELETE
              },
              default_ttl: 86400,
              max_ttl: 31536000,
            }
          }
        })
      rescue Exception => err
        say Rainbow("Fail to create cloudfront distribution for s3 bucket!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      $config[:cloudfront] = {} unless $config[:cloudfront]
      $config[:cloudfront][domain] = {} unless $config[:cloudfront][domain]
      $config[:cloudfront][domain][name] = {
        id: resp.distribution.id,
        domain_name: resp.distribution.domain_name,
      }

      say Rainbow("- CloudFront Distribution for #{name} s3 bucket created!").green
    end

    def delete_cloudfront(name, domain)
      begin
        id = $config[:cloudfront][domain][name][:id]
        resp = @cloudFront.get_distribution({
          id: id
        });
        resp.distribution.distribution_config.enabled = false
        resp = @cloudFront.update_distribution({
          id: id,
          if_match: resp.etag,
          distribution_config: resp.distribution.distribution_config
        })
        # @cloudFront.delete_distribution({
        #   id: id,
        #   if_match: resp.etag
        # })
      rescue Exception => err
        say Rainbow("Fail to delete cloudfront distribution for s3 bucket!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      $config[:cloudfront].delete(domain)

      say Rainbow("- CloudFront Distribution for #{name} s3 bucket deleted!").green
      say Rainbow("--> /!\ Think to delete the CloudFront Distribution #{id} in the AWS Console").yellow
    end

    def create_dns_record(name, domain)
      bucketName = "chatanoo-#{$config[:env]}-#{name}"
      begin
        @route53.change_resource_record_sets({
          hosted_zone_id: $config[:route53][domain].id, # required
          change_batch: { # required
            comment: "Add Record Set for CloudFront Distribution for #{bucketName} s3 bucket",
            changes: [ # required
              {
                action: "CREATE", # required, accepts CREATE, DELETE, UPSERT
                resource_record_set: { # required
                  name: "#{name}.#{domain}.", # required
                  type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
                  ttl: 300,
                  resource_records: [
                    { value: $config[:cloudfront][domain][name][:domain_name] }
                  ]
                },
              },
            ],
          },
        })
      rescue Exception => err
        say Rainbow("Fail to create DNS Record").red
        say Rainbow("Error: #{err}").red
        fail err
      end
      say Rainbow("- DNS Record for CloudFront Distribution to #{name} s3 bucket created!").green
    end

    def delete_dns_record(name, domain)
      bucketName = "chatanoo-#{$config[:env]}-#{name}"
      begin
        @route53.change_resource_record_sets({
          hosted_zone_id: $config[:route53][domain].id, # required
          change_batch: { # required
            comment: "Delete Record Set for CloudFront Distribution for #{bucketName} s3 bucket",
            changes: [ # required
              {
                action: "DELETE", # required, accepts CREATE, DELETE, UPSERT
                resource_record_set: { # required
                  name: "#{name}.#{domain}.", # required
                  type: "CNAME", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
                  ttl: 300,
                  resource_records: [
                    { value: $config[:cloudfront][domain][name][:domain_name] }
                  ]
                },
              },
            ],
          },
        })
      rescue Exception => err
        say Rainbow("Fail to delete DNS Record").red
        say Rainbow("Error: #{err}").red
        fail err
      end
      say Rainbow("- DNS Record for CloudFront Distribution to #{name} s3 bucket deleted!").green
    end

    def save_config
      filename = "#{ENV['HOME']}/.chatanoo/#{$config[:env]}.yml"
      File.open(filename, "w") do |f|
        f.write( $config.to_yaml )
      end
    end
  end

  class CLI < Thor
    desc "s3 COMMANDS", "S3 Controller"
    subcommand "s3", Chatanoo::S3
  end

end
