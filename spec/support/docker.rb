require 'open3'
require 'yaml'

DOCKERSOCKET = "/var/run/docker.sock"

def docker_get_chunked(path)
  sock = Net::BufferedIO.new(UNIXSocket.new(DOCKERSOCKET))
  request = Net::HTTP::Get.new(path)
  request.exec(sock, "1.1", path)
  response = Net::HTTPResponse.read_new(sock)
  while(line = sock.readline) do
    size = line.to_i
    body = sock.readline
    yield body
  end 
end

def docker_get(path)
  sock = Net::BufferedIO.new(UNIXSocket.new(DOCKERSOCKET))
  request = Net::HTTP::Get.new(path)
  request.exec(sock, "1.1", path)
  response = Net::HTTPResponse.read_new(sock)
  body = sock.readline
  yield body
end

def docker_events
  docker_get_chunked('/events') do |body|
    yield JSON.parse(body)
  end
end

class DockerExpectation
  class Failed < StandardError
    attr_reader :expected, :watcher
    def initialize(expectation, watcher)
      @expected = expectation
      @watcher = watcher
    end

    def message
      message = []
      message << "Enable to find expected Docker activity"
      message << " action: #{expected.action}"
      message << " name: #{expected.name}"
      message << "Options:"
      message << expected.options.to_yaml
      message << ""
      message << "Activity Seen:"
      message.concat watcher.activity
      message.join "\n"
    end
  end

  class FailedNegative < StandardError
    attr_reader :expected, :watcher
    def initialize(expectation, watcher)
      @expected = expectation
      @watcher = watcher
    end

    def message
      message = []
      message << "Unxpected Docker activity"
      message << " action: #{expected.action}"
      message << " name: #{expected.name}"
      message << "Options:"
      message << expected.options.to_yaml
      message.join "\n"
    end
  end

  attr_reader :action, :name, :options

  def initialize(action, name)
    @action = action
    @name = name
    @options = {}
  end

  def within(time)
    options[:within] = time
    self
  end

  def never
    options[:never] = true
    self
  end

  def verify!(watcher)
    within = options[:within] || 2.seconds
    event = nil
    while !event && watcher.within?(within)
      watcher.find_events(action, name) do |possible|
        event = possible if event_matches?(possible)
      end
      sleep 0.1
    end
    if options[:never]
      raise FailedNegative.new(self, watcher) if event
    else
      raise Failed.new(self, watcher) unless event
    end
  end

  def env_including(env)
    options[:env] ||= []
    options[:env] << env
    self
  end

  def event_matches?(possible)
    return false unless possible
    match = true
    if envs = options[:env]
      envs.each do |env|
        match = false unless possible.env.include? env
      end
    end
    match
  end

end

def docker_tail(name, cmd, lines=20)
  puts "Tailing #{name}"
  output = `docker logs #{cmd}`
  output = output.split /\n/
  output = output.slice (-1 * lines), lines
  return unless output
  output.each do |line|
    puts ">  #{line}"
  end
end


class DockerWatcher

  class Container
    def initialize(json)
      @json = json
    end

    def name
      name = @json["Name"]
      name.slice 1, name.length
    end

    def config
      @json["Config"]
    end

    def env
      config["Env"]
    end
  end

  def events
    @events ||= []
  end

  def containers
    @containers ||= {}
  end

  def expectations
    @expectations ||= []
  end

  def clear!
    @events.clear
  end

  def start
    @started = Time.now.to_f * 1000
    @thread = Thread.new do
      while true do
        begin
          docker_events do |event|
            events << event
            id = event["id"]
            fetch_container(id)
          end
        rescue => e
          p e
          puts e.backtrace.join("\n>>")
        end
      end
    end
  end

  def stop
    verify_expectations
    @thread.kill
  end

  def activity
    events.map do |event|
      status = event["status"]
      container = containers[event["id"]]
      if container
        "#{status}: #{container.name}"
      else
        "#{status}: ????"
      end
    end
  end

  def await(status, name)
    #puts "Waiting For #{status}: #{name}"
    found = false
    while !found do
      events.each do |event|
        if status == event["status"]
          container = containers[event["id"]]
          if container && container.name == name
            found =true
          end
        end
      end
      sleep 0.1 if !found
    end
  end

  def clean_up
    puts 
    puts "Cleaning Up Created Containers.."
    threads = []
    events.each do |event|
      status = event["status"]
      if status == "create"
        #puts " > #{event["id"]}"
        threads << Thread.new do
          Open3.capture3("docker rm -f #{event["id"]}")
          putc '.'
        end
      end
    end
    threads.map &:join
    puts
  end

  def dump_events
    puts "Events Seen"
    puts "***************"
    events.each do |event|
      status = event["status"]
      container = containers[event["id"]]
      if container
        puts "#{status}: #{container.name}"
      else
        puts "#{status}: ????"
      end
    end
  end

  def fetch_container(id)
    return if containers[id]
    docker_get("/containers/#{id}/json") do |body|
      begin
        ctr = Container.new(JSON.parse(body))
        containers[id] = ctr
      rescue
      end
    end
  end

  def within?(milis)
    now = Time.now.to_f * 1000
    (@started..(@started+milis)).include? now
  end

  def find_events(action, name)
    events.each do |event|
      if event["status"] == action
        id = event["id"]
        container = containers[id]
        if container && container.name == name 
          yield container
        end
      end
    end
  end
  
  private

  def verify_expectations
    expectations.each do |expectation|
      expectation.verify!(self)
    end
  end
end

def expect_container(action, name)
  expectation = DockerExpectation.new(action, name)
  @docker_watcher.expectations << expectation
  expectation
end

def reset_docker_events
  @docker_watcher.clear!
end

def await_container(action, name)
  @docker_watcher.await(action, name)
end

def kill_container(name)
  Open3.capture3("docker rm -f #{name}")
end

RSpec.configure do |config|
  config.around(:each) do |example|
    @docker_watcher = DockerWatcher.new
    @docker_watcher.start
    example.run
    @docker_watcher.stop
  end

  config.before(:suite) do
    $suite_docker = DockerWatcher.new
    $suite_docker.start
  end

  config.after(:suite) do
    $suite_docker.clean_up
  end

  #config.after(:each) do |example|
  #  if example.exception != nil
  #    puts "Failed: Tailing Docker Logs.."
  #    docker_tail('Commodore', 'commodore')
  #    docker_tail('Harbourmaster', 'harbourmaster')
  #  end
  #end
end
