require 'spec_helper'

describe "Terminating A Convoy" do
  let(:manifest) do
    <<-YAML
      apps:
        oneapp:
          image: test_daemon
        twoapp:
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
    await_container("create", "#{convoyid}_oneapp_1")
    await_container("create", "#{convoyid}_twoapp_1")
    etcd.queueJSON "/navy/queues/convoys", :request => :destroy,
                                           :name => convoyid
  end

  it "removes the desired container state" do
    expect_etcd_event('delete', "/navy/containers/#{convoyid}_oneapp_1/desired").
      within(6.seconds)
    expect_etcd_event('delete', "/navy/containers/#{convoyid}_twoapp_1/desired").
      within(6.seconds)
  end
  
  it "brings down the containers within that convoy" do
    expect_container("destroy", "#{convoyid}_oneapp_1").within(10.seconds)
    expect_container("destroy", "#{convoyid}_twoapp_1").within(10.seconds)
  end
end
