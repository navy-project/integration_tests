require 'spec_helper'

describe "Launching A Convoy" do
  #TODO: Setup should launch clean etcd, commodore, harbourmaster etc..
  #
  let(:manifest) do
    <<-YAML
      apps:
        oneapp:
          image: test_daemon
    YAML
  end

  let(:convoyid) do
    runid = SecureRandom.hex
    "example_#{runid}"
  end


  before :each do
    etcd.queueJSON "/navy/queues/convoys", :request => :create,
                                           :name => convoyid,
                                           :manifest => manifest
  end

  it "sets the desired launch state in etcd" do
    expect_etcd_event('set', "/navy/containers/#{convoyid}_oneapp_1/desired")
  end

  it "has launched a container for the application" do
    expect_container("start", "#{convoyid}_oneapp_1")
  end
end
