require 'spec_helper'
require 'net/http'
require 'socket'

describe "Linked Applications" do
  let(:manifest) do
    <<-YAML
      apps:
        oneapp:
          image: test_daemon
        second:
          image: test_daemon
          links:
            - oneapp
    YAML
  end

  let(:convoyid) do
    runid = SecureRandom.hex
    "example_#{runid}"
  end

  let(:cluster) { "dev.lvh.me" }

  before :each do
    etcd.queueJSON "/navy/queues/convoys", :request => :create,
                                           :name => convoyid,
                                           :manifest => manifest
  end

  it "has launches both containers" do
    expect_container("create", "#{convoyid}_oneapp_1").within(2.seconds)
    expect_container("create", "#{convoyid}_second_1").within(2.seconds)
  end

  it "sets appropriate links to the host proxy" do
    expect_container("create", "#{convoyid}_second_1").
      within(2.seconds).
      env_including("ONEAPP_HOST_ADDR=https://#{convoyid}-oneapp-#{cluster}")
  end
end
