require 'spec_helper'
require 'webmock/rspec'

describe Service::YouTrack do
  it 'should have a title' do
    Service::YouTrack.title.should == 'YouTrack'
  end

  def stub_successful_login_for(config)
    stub_request(:post, "#{config[:base_url]}/rest/user/login")
      .with({:login => config[:username], :password => config[:password]})
      .to_return(status: 200, body: {}, headers: { 'Set-Cookie' => 'cookie-string' })
  end

  def stub_failed_login_for(config)
    stub_request(:post, "#{config[:base_url]}/rest/user/login")
      .with({:login => config[:username], :password => config[:password]})
      .to_return(status: 500, body: {})
  end

  let(:service) { described_class.new('event_name', {}, {}) }
  let(:config) do
    {
        :base_url => 'http://example-project.youtrack.com',
        :project_id  => 'foo_project_id',
        :username => 'username',
        :password => 'password'
    }
  end

  def issue_payload(options = {})
    {
        :title                  => 'foo_title',
        :method                 => 'method name',
        :impact_level           => 1,
        :impacted_devices_count => 1,
        :crashes_count          => 1,
        :app                    => {
            :name              => 'foo name',
            :bundle_identifier => 'foo.bar.baz'
        },
        :url                    => 'http://foo.com/bar'
    }.merge(options)
  end

  describe '#login' do
    it 'should return cookie string on success' do
      stub_successful_login_for(config)
      resp = service.send :login, config[:base_url], config[:username], config[:password]
      resp.should == 'cookie-string'
    end

    it 'should return false on failure' do
      stub_failed_login_for(config)
      resp = service.send :login, config[:base_url], config[:username], config[:password]
      resp.should == false
    end
  end


  describe '#receive_verification' do
    it 'should succeed if login is successful and project exists' do
      stub_successful_login_for(config)
      stub_request(:get, "#{config[:base_url]}/rest/admin/project/foo_project_id")
        .with({:headers => { 'Cookie' => 'cookie-string' }})
        .to_return(status: 200, body: {})

      response = service.receive_verification(config, nil)
      response.should == [true, 'Successfully connected to your YouTrack project!']
    end

    it 'should fail if login is successful but project does not exist' do
      stub_successful_login_for(config)
      stub_request(:get, "#{config[:base_url]}/rest/admin/project/foo_project_id")
        .with({:headers => { 'Cookie' => 'cookie-string' }})
        .to_return(status: 500, body: {})

      response = service.receive_verification(config, nil)
      response.should == [false, 'Oops! Please check your YouTrack settings again.']
    end

    it 'should fail on unhandled exception' do
      response = service.receive_verification({}, nil)
      response.should == [false, 'Oops! Please check your settings again.']
    end
  end

  describe '#receive_issue_impact_change' do
    it 'should succeed if login is successful and PUT succeeds' do
      stub_successful_login_for(config)
      service.stub(:issue_description_text).with(issue_payload).and_return 'foo_issue_description'
      stub_request(:put, "#{config[:base_url]}/rest/issue")
        .with({
          :headers => { 'Cookie' => 'cookie-string' },
          :query => {
            :project => 'foo_project_id',
            :summary => '[Crashlytics] foo_title',
            :description => 'foo_issue_description'
          }
        })
        .to_return(status: 201, body: {}, :headers => { 'Location' => 'foo_youtrack_issue_url' })

      response = service.receive_issue_impact_change(config, issue_payload)
      response.should == { :youtrack_issue_url => 'foo_youtrack_issue_url' }
    end

    it 'should fail if login is successful but PUT fails' do
      stub_successful_login_for(config)
      service.stub(:issue_description_text).with(issue_payload).and_return 'foo_issue_description'
      stub_request(:put, "#{config[:base_url]}/rest/issue")
        .with({
          :headers => { 'Cookie' => 'cookie-string' },
          :query => {
            :project => 'foo_project_id',
            :summary => '[Crashlytics] foo_title',
            :description => 'foo_issue_description'
          }
        })
        .to_return(status: 500, body: {})

      expect { service.receive_issue_impact_change(config, issue_payload) }.to raise_exception
    end

    it 'should fail if login fails' do
      stub_failed_login_for(config)
      expect { service.receive_issue_impact_change(config, issue_payload) }.to raise_exception
    end
  end

  describe '#issue_description_text' do
    it 'displays a singular message when only one device is impacted' do
      result = service.send(:issue_description_text,
          issue_payload(:impacted_devices_count => 1))

      result.should =~ /at least 1 user/
    end

    it 'displays a pluralized message when multiple devices are impacted' do
      result = service.send(:issue_description_text,
          issue_payload(:impacted_devices_count => 2))

      result.should =~ /at least 2 users/
    end

    it 'displays a singular message only one crash occurred' do
      result = service.send(:issue_description_text,
          issue_payload(:crashes_count => 1))

      result.should =~ /at least 1 time/
    end

    it 'displays a pluralized message whem multiple crashes occurred' do
      result = service.send(:issue_description_text,
          issue_payload(:crashes_count => 2))

      result.should =~ /at least 2 times/
    end

    it 'displays payload information' do
      result = service.send(:issue_description_text,
        issue_payload(:title => 'fake_title',
          :method => 'fake_method',
          :url => 'http://example.com/foobar'))

      result.should =~ /fake_title/
      result.should =~ /fake_method/
      result.should =~ /#{Regexp.escape('http://example.com/foobar')}/
    end
  end
end
