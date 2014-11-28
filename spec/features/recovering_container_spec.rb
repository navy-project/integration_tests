require 'spec_helper'

describe "Recovering a container" do
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

  context "When a container vanishes" do
    before :each do
      etcd.queueJSON "/navy/queues/convoys", :request => :create,
        :name => convoyid,
        :manifest => manifest
      await_container("start", "#{convoyid}_oneapp_1")
      await_container("start", "#{convoyid}_twoapp_1")
      kill_container("#{convoyid}_twoapp_1")
    end

    it "updates the actual container state to be missing" do
      expect_etcd_event('delete', "/navy/containers/#{convoyid}_twoapp_1/actual").
      within(10.seconds)
    end

    it "brings the container back up" do
      reset_docker_events
      expect_container("create", "#{convoyid}_twoapp_1").within(10.seconds)
    end
  end

  context "When a task container is removed" do
    let(:manifest) do
      <<-YAML
      apps:
        oneapp:
          image: test_daemon
      environments:
        development:
          pre:
            oneapp:
            - echo 'atask'
      YAML
    end

    before :each do
      etcd.queueJSON "/navy/queues/convoys", :request => :create,
        :name => convoyid,
        :manifest => manifest
      await_container("start", "#{convoyid}_oneapp_pretasks")
    end

    it "does not try and restore it" do
      reset_docker_events
      expect_container("create", "#{convoyid}_oneapp_pretasks").never.within(10.seconds)
    end
  end
end
