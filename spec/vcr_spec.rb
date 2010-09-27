require 'spec_helper'

describe VCR do
  def insert_cassette
    VCR.insert_cassette(:cassette_test)
  end

  before(:each) do
    # clear out any caching between test runs
    described_class.instance_eval do
      instance_variables.each { |ivar| remove_instance_variable(ivar) }
    end
  end

  describe '.insert_cassette' do
    it 'creates a new cassette' do
      insert_cassette.should be_instance_of(VCR::Cassette)
    end

    it 'takes over as the #current_cassette' do
      orig_cassette = VCR.current_cassette
      new_cassette = insert_cassette
      new_cassette.should_not == orig_cassette
      VCR.current_cassette.should == new_cassette
    end
  end

  describe '.eject_cassette' do
    it 'ejects the current cassette' do
      cassette = insert_cassette
      cassette.should_receive(:eject)
      VCR.eject_cassette
    end

    it 'returns the ejected cassette' do
      cassette = insert_cassette
      VCR.eject_cassette.should == cassette
    end

    it 'returns the #current_cassette to the previous one' do
      cassette1, cassette2 = insert_cassette, insert_cassette
      lambda { VCR.eject_cassette }.should change(VCR, :current_cassette).from(cassette2).to(cassette1)
    end
  end

  describe '.use_cassette' do
    it 'inserts a new cassette' do
      new_cassette = VCR::Cassette.new(:use_cassette_test)
      VCR.should_receive(:insert_cassette).and_return(new_cassette)
      VCR.use_cassette(:cassette_test) { }
    end

    it 'yields' do
      yielded = false
      VCR.use_cassette(:cassette_test) { yielded = true }
      yielded.should be_true
    end

    it 'ejects the cassette' do
      VCR.should_receive(:eject_cassette)
      VCR.use_cassette(:cassette_test) { }
    end

    it 'ejects the cassette even if there is an error' do
      VCR.should_receive(:eject_cassette)
      lambda { VCR.use_cassette(:cassette_test) { raise StandardError } }.should raise_error
    end

    it 'does not eject a cassette if there was an error inserting it' do
      VCR.should_receive(:insert_cassette).and_raise(StandardError.new('Boom!'))
      VCR.should_not_receive(:eject_cassette)
      lambda { VCR.use_cassette(:test) { } }.should raise_error(StandardError, 'Boom!')
    end
  end

  describe '.config' do
    it 'yields the configuration object' do
      yielded_object = nil
      VCR.config do |obj|
        yielded_object = obj
      end
      yielded_object.should == VCR::Config
    end

    it "disallows http connections" do
      VCR.http_stubbing_adapter.should respond_to(:http_connections_allowed=)
      VCR.http_stubbing_adapter.should_receive(:http_connections_allowed=).with(false)
      VCR.config { }
    end

    it "checks the adapted library's version to make sure it's compatible with VCR" do
      VCR.http_stubbing_adapter.should respond_to(:check_version!)
      VCR.http_stubbing_adapter.should_receive(:check_version!)
      VCR.config { }
    end

    [true, false].each do |val|
      it "sets http_stubbing_adapter.ignore_localhost to #{val} when so configured" do
        VCR.config do |c|
          c.ignore_localhost = val

          # this is mocked at this point since it should be set when the block completes.
          VCR.http_stubbing_adapter.should_receive(:ignore_localhost=).with(val)
        end
      end
    end
  end

  describe '.cucumber_tags' do
    it 'yields a cucumber tags object' do
      yielded_object = nil
      VCR.cucumber_tags do |obj|
        yielded_object = obj
      end
      yielded_object.should be_instance_of(VCR::CucumberTags)
    end
  end

  describe '.http_stubbing_adapter' do
    subject { VCR.http_stubbing_adapter }
    before(:each) do
      VCR.instance_variable_set(:@http_stubbing_adapter, nil)
    end

    {
      :fakeweb => VCR::HttpStubbingAdapters::FakeWeb,
      :webmock => VCR::HttpStubbingAdapters::WebMock
    }.each do |setting, adapter|
      context "when config http_stubbing_library = :#{setting.to_s}" do
        before(:each) { VCR::Config.http_stubbing_library = setting }

        it "returns #{adapter}" do
          subject.should == adapter
        end
      end
    end

    it 'raises an error when library is not set' do
      VCR::Config.http_stubbing_library = nil
      lambda { subject }.should raise_error(/The http stubbing library is not configured correctly/)
    end
  end

  describe '.record_http_interaction' do
    before(:each) { VCR.stub!(:current_cassette).and_return(current_cassette) }

    def self.with_ignore_localhost_set_to(value, &block)
      context "when http_stubbing_adapter.ignore_localhost is #{value}" do
        before(:each) { VCR.http_stubbing_adapter.stub!(:ignore_localhost?).and_return(value) }

        instance_eval(&block)
      end
    end

    def self.it_records_requests_to(host)
      it "records requests to #{host}" do
        interaction = stub(:uri => "http://#{host}/")
        current_cassette.should_receive(:record_http_interaction).with(interaction).once
        VCR.record_http_interaction(interaction)
      end
    end

    def self.it_does_not_record_requests_to(host)
      it "does not record requests to #{host}" do
        interaction = stub(:uri => "http://#{host}/")
        current_cassette.should_receive(:record_http_interaction).never unless current_cassette.nil?
        VCR.record_http_interaction(interaction)
      end
    end

    context 'when there is a current cassette' do
      let(:current_cassette) { mock('current casette') }

      with_ignore_localhost_set_to(true) do
        it_records_requests_to "example.com"

        VCR::LOCALHOST_ALIASES.each do |host|
          it_does_not_record_requests_to host
        end
      end

      with_ignore_localhost_set_to(false) do
        (VCR::LOCALHOST_ALIASES + ['example.com']).each do |host|
          it_records_requests_to host
        end
      end
    end

    context 'when there is not a current cassette' do
      let(:current_cassette) { nil }

      with_ignore_localhost_set_to(true) do
        (VCR::LOCALHOST_ALIASES + ['example.com']).each do |host|
          it_does_not_record_requests_to host
        end
      end

      with_ignore_localhost_set_to(false) do
        (VCR::LOCALHOST_ALIASES + ['example.com']).each do |host|
          it_does_not_record_requests_to host
        end
      end
    end
  end

  #describe '.log_http_to' do
    #logging_dir = 'tmp/logging_dir'
    #temp_dir logging_dir

    #let(:main_file) { File.join(logging_dir, 'http_interactions.yml') }
    #let(:timestamped_file) { main_file.gsub('.yml', '.2010-09-21_12-00-00.yml') }
    #let(:example_http_interaction) { VCR::HTTPInteraction.new("request 1", "response 2") }

    #around(:each) do |example|
      #Timecop.freeze(Time.local(2010, 9, 21, 12), &example)
    #end

    #define_method(:setup_logging) do
      #described_class.log_http_to(logging_dir)
    #end

    #it 'creates the log directory' do
      #expect { setup_logging }.to change { File.exist?(logging_dir) }.from(false).to(true)
      #File.should be_directory(logging_dir)
    #end

    #it 'causes recorded http interactions to be written directly to a timestamped yaml file' do
      #setup_logging
      #File.zero?(timestamped_file).should be_true
      #described_class.record_http_interaction(example_http_interaction)
      #YAML.load(File.read(timestamped_file)).should == [example_http_interaction]
    #end

    #it 'symlinks http_interactions.yml to the timestamped yaml file' do
      #setup_logging
      #File.readlink(main_file).should == timestamped_file
    #end
  #end
end
