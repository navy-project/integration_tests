require 'navy'

def etcd
  @etcd ||= Navy::Etcd.client(host: ENV['ETCD_PORT_4001_TCP_ADDR'])
end

class EtcExpectation

  class Failed < StandardError
    attr_reader :expected, :watcher
    def initialize(expectation, watcher)
      @expected = expectation
      @watcher = watcher
    end

    def message
      message = []
      message << "Enable to find expected ETCD activity"
      message << " action: #{expected.action}"
      message << " key: #{expected.key}"
      message << "Options:"
      message << expected.options.to_yaml
      message << ""
      message << "Activity Seen:"
      message.concat watcher.activity
      message.join "\n"
    end
  end

  attr_reader :action, :key, :options

  def initialize(action, key)
    @action = action
    @key = key
    @options = {}
  end

  def within(time)
    options[:within] = time
    self
  end

  def json_including(including)
    options[:json_including] = including
    self
  end

  def verify!(watcher)
    within = options[:within] || 2.seconds
    event = nil
    while !event && watcher.within?(within)
      watcher.find_events(action, key) do |possible|
        event = possible if event_matches?(possible)
      end
      sleep 0.1
    end
    raise Failed.new(self, watcher) unless event
  end

  private

  def event_matches?(possible)
    return false unless possible
    match = true
    if desired = options[:json_including]
      json = possible.json
      desired.each do |k, v|
        #puts "#{k}: #{v} vs #{json[k]}"
        match = false unless json[k] == v
      end
    end
    match
  end
end

class EtcdWatcher
  class Event
    def initialize(response)
      @response = response
    end

    def action
      @response.action
    end

    def key
      @response.node.key
    end

    def value
      @response.node.value
    end

    def json
      JSON.parse(value)
    end

    def to_s
      "#{action}: #{key}"
    end
  end

  def expectations
    @expectations ||= []
  end

  def events
    @events ||= []
  end

  def start
    @started = Time.now.to_f * 1000
    @thread = Thread.new do
      init = etcd.get('/')
      last_index = init.etcd_index
      while true do
        begin
          response = etcd.watch("/",
                               :waitIndex => last_index+1,
                               :recursive => true)
          last_index = response.node.modifiedIndex
          events << Event.new(response)
          #putc "e"
          #puts events.last
        rescue => e
          p "Error", e
        end
      end
    end
  end

  def stop
    verify_expectations
    #dump_events
    @thread.kill
  end

  def activity
    return events
    events.map do |event|
        "#{status}: ????"
    end
  end

  def find_events(action, key)
    events.each do |event|
      if event.action == action && event.key == key
        yield event
      end
    end
  end

  def within?(milis)
    now = Time.now.to_f * 1000
    (@started..(@started+milis)).include? now
  end

  def clean_up
    puts 
    puts "Cleaning Up Etcd Keys.."
    keys = events.map do |event|
      File.expand_path('..', event.key)
    end
    keys.uniq!
    threads = []
    keys.each do |key|
      #puts " > #{key}"
      threads << Thread.new do
        etcd.delete key, :recursive => true
        putc '.'
      end
    end
    threads.map &:join
    puts
  end

  private

  def dump_events
    puts "Etcd Events"
    puts "*" * 80
    events.each do |event|
      puts "#{event.action}: #{event.key}"
    end
  end

  def verify_expectations
    expectations.each do |expectation|
      expectation.verify!(self)
    end
  end
end

def expect_etcd_event(action, key, options = {})
  expectation = EtcExpectation.new(action, key)
  @etcd_watcher.expectations << expectation
  expectation
end

RSpec.configure do |config|
  config.around(:each) do |example|
    @etcd_watcher = EtcdWatcher.new
    @etcd_watcher.start
    example.run
    @etcd_watcher.stop
  end

  config.before(:suite) do
    $suite_etcd = EtcdWatcher.new
    $suite_etcd.start
  end

  config.after(:suite) do
    $suite_etcd.clean_up
  end
end
