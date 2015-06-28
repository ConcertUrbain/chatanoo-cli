require 'json'

module Chatanoo

  class Transcoder < Thor
    class_option :env, required: true, aliases: '-e', desc: 'Select your environment'

    def initialize(*args)
      super
      $config = YAML::load(File.open("#{ENV['HOME']}/.chatanoo/#{options[:env]}.yml")) if options[:env]
      @transcoder = Aws::ElasticTranscoder::Client.new({
        region: $config[:aws_region],
        credentials: Aws::Credentials.new(
          $config[:aws_access_key_id],
          $config[:aws_secret_access_key]
        )
      })
      @iam = Chatanoo::Iam.new(*args)
    end

    desc "create INPUT OUTPUT ROLE", "create transcoder"
    def create(input, output)
      create_presets
      @iam.create_role("transcoder", get_transcoder_role_policy())
      create_pipeline(input, output, $config[:iam]["transcoder"][:role])
    end

    desc "delete", "delete transcoder"
    def delete
      delete_pipeline
      delete_presets
      @iam.delete_role("transcoder")
    end

    desc "create_pipeline INPUT OUTPUT ROLE", "create transcoding pipeline"
    def create_pipeline(input, output, role)
      begin
        resp = @transcoder.create_pipeline({
          name: "Chatanoo - #{$config[:env]} - Pipeline", # required
          input_bucket: "chatanoo-#{$config[:env]}-#{input}", # required
          output_bucket: "chatanoo-#{$config[:env]}-#{output}",
          role: role, # required
        })
      rescue Exception => err
        say Rainbow("Fail to create pipeline!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- Pipeline created!").green

      $config[:transcoder] = {} unless $config[:transcoder]
      $config[:transcoder][:pipeline] = resp.pipeline.id
      save_config
    end

    desc "delete_pipeline", "delete transcoding pipeline"
    def delete_pipeline
      begin
        @transcoder.delete_pipeline({
          id: $config[:transcoder][:pipeline]
        })
      rescue Exception => err
        say Rainbow("Fail to delete pipeline!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- Pipeline deleted!").green

      $config[:transcoder].delete(:pipeline)
      save_config
    end

    desc "create_presets", "create all presets for transcoding"
    def create_presets
      presets = get_presets
      begin
        presets.each do |(type, preset)|
          presets[type] = @transcoder.create_preset(preset).preset.id
        end
      rescue Exception => err
        say Rainbow("Fail to create presets!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- Presets created!").green

      $config[:transcoder] = {} unless $config[:transcoder]
      $config[:transcoder][:presets] = presets
      save_config
    end

    desc "delete_presets", "delete all presets for transcoding"
    def delete_presets
      presets = $config[:transcoder][:presets]
      begin
        presets.each do |(type, id)|
          @transcoder.delete_preset(id: id)
        end
      rescue Exception => err
        say Rainbow("Fail to delete presets!").red
        say Rainbow("Error: #{err}").red
        fail err
      end

      say Rainbow("- Presets deleted!").green

      $config[:transcoder].delete(:presets)
      save_config
    end

    private

    def save_config
      filename = "#{ENV['HOME']}/.chatanoo/#{$config[:env]}.yml"
      File.open(filename, "w") do |f|
        f.write( $config.to_yaml )
      end
    end

    def get_transcoder_role_policy
      policy = {
        "Version" => "2012-10-17",
        "Statement" => [{
            "Sid" => "1",
            "Effect" => "Allow",
            "Action" => [
              "s3:ListBucket",
              "s3:Put*",
              "s3:Get*",
              "s3:*MultipartUpload*"
            ],
            "Resource" => ["*"]
          }, {
            "Sid" => "2",
            "Effect" => "Allow",
            "Action" => ["sns:Publish"],
            "Resource" => ["*"]
          }, {
            "Sid" => "3",
            "Effect" => "Deny",
            "Action" => [
                "s3:*Policy*",
                "sns:*Permission*",
                "sns:*Delete*",
                "s3:*Delete*",
                "sns:*Remove*"
            ],
            "Resource" => ["*"]
          }
        ]
      }
      JSON.pretty_generate( policy )
    end

    def get_presets
      {
        mp4: {
          name: "Chatanoo - #{$config[:env]} - MP4", # required
          description: "",
          container: "mp4", # required
          video: {
            codec: "H.264",
            codec_options: {
              "InterlacedMode" => "Progressive",
              "MaxReferenceFrames" => "3",
              "Level" => "3.1",
              "ColorSpaceConversionMode" => "None",
              "Profile" => "main",
            },
            fixed_gop: "true",
            keyframes_max_dist: "90",
            bit_rate: "2200",
            frame_rate: "30",
            max_width: "1280",
            max_height: "720",
            display_aspect_ratio: "auto",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad"
          },
          audio: {
            codec: "AAC",
            sample_rate: "48000",
            bit_rate: "160",
            channels: "2",
            codec_options: {
              profile: "AAC-LC"
            },
          },
          thumbnails: {
            format: "png",
            interval: "60",
            max_width: "192",
            max_height: "108",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad",
          },
        },
        webm: {
          name: "Chatanoo - #{$config[:env]} - WebM", # required
          description: "",
          container: "webm", # required
          video: {
            codec: "vp8",
            codec_options: {
              "Profile" => "1",
            },
            fixed_gop: "true",
            keyframes_max_dist: "90",
            bit_rate: "2200",
            frame_rate: "30",
            max_width: "1280",
            max_height: "720",
            display_aspect_ratio: "auto",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad"
          },
          audio: {
            codec: "vorbis",
            sample_rate: "48000",
            bit_rate: "160",
            channels: "2"
          },
          thumbnails: {
            format: "png",
            interval: "60",
            max_width: "192",
            max_height: "108",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad",
          },
        },
        flv: {
          name: "Chatanoo - #{$config[:env]} - FLV", # required
          description: "",
          container: "flv", # required
          video: {
            codec: "H.264",
            codec_options: {
              "InterlacedMode" => "Progressive",
              "MaxReferenceFrames" => "3",
              "Level" => "3.1",
              "ColorSpaceConversionMode" => "None",
              "Profile" => "main",
            },
            fixed_gop: "true",
            keyframes_max_dist: "90",
            bit_rate: "2200",
            frame_rate: "30",
            max_width: "1280",
            max_height: "720",
            display_aspect_ratio: "auto",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad"
          },
          audio: {
            codec: "AAC",
            sample_rate: "44100",
            bit_rate: "160",
            channels: "2",
            codec_options: {
              profile: "AAC-LC"
            },
          },
          thumbnails: {
            format: "png",
            interval: "60",
            max_width: "192",
            max_height: "108",
            sizing_policy: "ShrinkToFit",
            padding_policy: "NoPad",
          },
        },
        mp3: {
          name: "Chatanoo - #{$config[:env]} - MP3", # required
          description: "",
          container: "mp3", # required
          audio: {
            codec: "mp3",
            sample_rate: "44100",
            bit_rate: "128",
            channels: "2",
          }
        },
        ogg: {
          name: "Chatanoo - #{$config[:env]} - OGG", # required
          description: "",
          container: "ogg", # required
          audio: {
            codec: "vorbis",
            sample_rate: "44100",
            bit_rate: "128",
            channels: "2",
          }
        }
      }
    end
  end

  class CLI < Thor
    desc "transcoder COMMANDS", "Transcoder Controller"
    subcommand "transcoder", Chatanoo::Transcoder
  end

end
