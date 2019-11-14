require 'active_record'
require 'byebug'
require 'httparty'
require 'tty-spinner'
require 'yaml'
require 'ziptz'

class ZipCode < ActiveRecord::Base
  self.table_name = 'ZIPCodes'
  self.primary_key = 'ZipCode'
  establish_connection YAML.safe_load(File.open('database.yml'))

  alias_attribute :city, :City
  alias_attribute :day_light_saving, :DayLightSaving
  alias_attribute :latitude, :Latitude
  alias_attribute :longitude, :Longitude
  alias_attribute :state, :State
  alias_attribute :time_zone, :TimeZone
  alias_attribute :zip_code, :ZipCode

  def self.import
    spinner = TTY::Spinner.new('[:spinner] Retrieving zip codes from database')
    spinner.auto_spin

    spinner = TTY::Spinner.new('[:spinner] :message')
    spinner.update message: 'Retrieving zip codes from database'
    data = {}
    ZipCode.distinct(:ZipCode).find_each do |zip|
      next if zip.time_zone.blank? || zip.day_light_saving.blank?

      data[zip.zip_code] ||= {}
      if %w[APO DPO FPO].include?(zip.city) && zip.latitude.zero? && zip.longitude.zero?
        data[zip.zip_code][:tz] = 'APO/FPO (time zone unknown)'
      elsif zip.latitude.zero? && zip.longitude.zero?
        data[zip.zip_code][:tz] = nil
      else
        response = HTTParty.get("http://localhost:3001/?lat=#{zip.latitude}&lng=#{zip.longitude}")
        data[zip.zip_code][:tz] = response['results'].first
      end

      data[zip.zip_code][:dst] = zip.day_light_saving
    end
    spinner.update message: "Retrieving zip codes from database (#{data.size} records)"
    spinner.success

    spinner = TTY::Spinner.new('[:spinner] :message')
    spinner.update message: 'Writing tz.data'
    spinner.auto_spin
    lines = data.map { |k, v| "#{k}=#{v[:tz]}" }
    lines.sort!
    File.open('data/tz.data', 'w') do |f|
      lines.each { |line| f.puts line }
    end
    spinner.update message: "Writing tz.data (#{File.size('data/tz.data')} bytes)"
    spinner.success
    # puts File.size('data/tz.data').to_s

    spinner = TTY::Spinner.new('[:spinner] :message')
    spinner.update message: 'Writing dst.data'
    spinner.auto_spin
    lines = data.map { |k, v| "#{k}=#{v[:dst] =~ /y/i ? 1 : 0}" }
    lines.sort!

    File.open('data/dst.data', 'w') do |f|
      lines.each { |line| f.puts line }
    end
    spinner.update message: "Writing dst.data (#{File.size('data/dst.data')} bytes)"
    spinner.success
  rescue StandardError
    spinner && spinner.error
    raise
  end
end
