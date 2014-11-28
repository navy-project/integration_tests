These present integration tests to run against the navy host.  This should allow you to check the host is operating properly.

    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock --link=etcd:etcd navyproject/integration_tests bundle exec rspec
