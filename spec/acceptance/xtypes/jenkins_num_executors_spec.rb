# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'jenkins_num_executors' do
  it_behaves_like 'an idempotent resource' do
    let(:manifest) do
      <<~PUPPET
        include jenkins
        include jenkins::cli::config

        jenkins_num_executors { '3':
          ensure => 'present',
        }
      PUPPET
    end
  end

  describe file('/var/lib/jenkins/config.xml') do
    it { is_expected.to contain '<numExecutors>3</numExecutors>' }
  end
end
