require 'spec_helper'

describe "Waiting for dependencies" do
  let(:manifest) do
    <<-YAML
      apps:
        oneapp:
          image: test_daemon
          links:
            - dep
      environments:
        development:
          dependencies:
            dep:
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

  it "marks the container as waiting" do
    expect_etcd_event('set', "/navy/containers/#{convoyid}_oneapp_1/actual").
      within(1.seconds).
      json_including("state" => "waiting")
  end

  it "launches the container onces the dependency is up" do
    expect_etcd_event('set', "/navy/containers/#{convoyid}_oneapp_1/actual").
      within(3.seconds).
      json_including("state" => "running")
  end

  context "when a dependency fails to start" do
    let(:manifest) do
      <<-YAML
        apps:
          oneapp:
            image: test_daemon
            links:
              - dep
        environments:
          development:
            dependencies:
              dep:
                image: bad_item
      YAML
    end

    it "marks the dependent as errored too" do
      expect_etcd_event('set', "/navy/containers/#{convoyid}_dep/actual").
        within(4.seconds).
        json_including("state" => "error")
      expect_etcd_event('set', "/navy/containers/#{convoyid}_oneapp_1/actual").
        within(10.seconds).
        json_including("state" => "error")
    end
  end
end
