require 'fileutils'
require 'vcr/cassette'
require 'vcr/config'
require 'vcr/cucumber_tags' # TODO: only require this when cucumber tags are used...
require 'vcr/deprecations'
require 'vcr/internet_connection'
require 'vcr/request_matcher'
require 'vcr/structs'
require 'vcr/version'

require 'vcr/extensions/net_http_response'

require 'vcr/http_stubbing_adapters/common'

module VCR
  extend self

  LOCALHOST_ALIASES = %w( localhost 127.0.0.1 )

  def current_cassette
    cassettes.last
  end

  def insert_cassette(*args)
    cassette = Cassette.new(*args)
    cassettes.push(cassette)
    cassette
  end

  def eject_cassette
    cassette = cassettes.pop
    cassette.eject if cassette
    cassette
  end

  def use_cassette(*args)
    insert_cassette(*args)

    begin
      yield
    ensure
      eject_cassette
    end
  end

  def config
    yield VCR::Config
    http_stubbing_adapter.check_version!
    http_stubbing_adapter.http_connections_allowed = false
    http_stubbing_adapter.ignore_localhost = VCR::Config.ignore_localhost?
  end

  def cucumber_tags(&block)
    main_object = eval('self', block.binding)
    yield VCR::CucumberTags.new(main_object)
  end

  def http_stubbing_adapter
    @http_stubbing_adapter ||= case VCR::Config.http_stubbing_library
      when :fakeweb
        VCR::HttpStubbingAdapters::FakeWeb
      when :webmock
        VCR::HttpStubbingAdapters::WebMock
      else
        raise ArgumentError.new("The http stubbing library is not configured correctly.  You should set it to :webmock or :fakeweb.")
    end
  end

  def record_http_interaction(interaction)
    if @development_logger
      @development_logger.log(interaction) and return
    end

    return unless cassette = current_cassette
    return if http_stubbing_adapter.ignore_localhost? &&
      LOCALHOST_ALIASES.include?(URI.parse(interaction.uri).host)

    cassette.record_http_interaction(interaction)
  end

  def log_http_to(dir)
    require 'vcr/development_logger'
    @development_logger = DevelopmentLogger.new(dir)
  end

  private

  def cassettes
    @cassettes ||= []
  end
end
