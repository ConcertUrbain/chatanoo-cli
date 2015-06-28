$config = {}

require 'thor'
require 'highline/import'
require 'rainbow'
require 'yaml'
require 'fileutils'
require 'aws-sdk'

require 'chatanoo/cli'
require 'chatanoo/domain'
require 'chatanoo/s3'
require 'chatanoo/transcoder'
require 'chatanoo/iam'

require 'chatanoo/flow'
