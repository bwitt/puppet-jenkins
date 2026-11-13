# frozen_string_literal: true

require 'spec_helper_acceptance'

# Exercises the authenticated CLI code paths: the native types (via
# jenkins::cli::config) and the jenkins::cli based defines (via the jenkins
# class cli_* params) against a jenkins with security enabled.
describe 'jenkins with security enabled', order: :defined do
  cli = 'java -jar /usr/share/java/jenkins-cli.jar -http -s http://localhost:8080'

  let(:test_build_job) do
    <<~EOS.gsub("'", %q(\\\'))
      <?xml version='1.1' encoding='UTF-8'?>
      <project>
        <actions/>
        <description>secured job</description>
        <keepDependencies>false</keepDependencies>
        <properties/>
        <scm class="hudson.scm.NullSCM"/>
        <canRoam>true</canRoam>
        <disabled>false</disabled>
        <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
        <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
        <triggers/>
        <concurrentBuild>false</concurrentBuild>
        <builders>
          <hudson.tasks.Shell>
            <command>/usr/bin/true</command>
            <configuredLocalRules/>
          </hudson.tasks.Shell>
        </builders>
        <publishers/>
        <buildWrappers/>
      </project>
    EOS
  end

  let(:security) do
    lambda do |model|
      <<~PUPPET
        class { 'jenkins':
          cli_username => 'admin',
          cli_password => 'hunter2',
        }

        class { 'jenkins::cli::config':
          cli_username => 'admin',
          cli_password => 'hunter2',
        }

        # jenkins_user requires mailer and sshd
        jenkins::plugin { [
          'display-url-api',
          'jakarta-activation-api',
          'jakarta-mail-api',
          'mailer',
          'mina-sshd-api-common',
          'mina-sshd-api-core',
          'sshd',
        ]: }

        # bcrypt hash of 'hunter2'
        jenkins_user { 'admin':
          ensure        => 'present',
          email_address => 'admin@example.org',
          full_name     => 'admin',
          password      => '#jbcrypt:$2a$10$QiROEodyzg1oqvxYGGZPUuC01WIUjeb5LJB84hhTjRJTCcYHg95JS',
        }

        class { 'jenkins::security':
          security_model => '#{model}',
        }

        Jenkins_user['admin'] -> Class['jenkins::security']
      PUPPET
    end
  end

  context 'enable security' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { security.call('full_control') }
    end

    # anonymous read is allowed by default, the helper needs administer
    describe command("echo 'println 1' | #{cli} groovy =") do
      its(:exit_status) { is_expected.not_to eq 0 }
      its(:stderr) { is_expected.to match %r{anonymous is missing the Overall/Administer permission} }
    end

    describe command("#{cli} -auth admin:hunter2 who-am-i") do
      its(:exit_status) { is_expected.to eq 0 }
      its(:stdout) { is_expected.to match %r{Authenticated as: admin} }
    end
  end

  context 'native types' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{security.call('full_control')}

          jenkins::plugin { 'plain-credentials': }

          jenkins_credentials { 'c6d2e3b4-1f2a-4b5c-8d9e-0a1b2c3d4e5f':
            ensure      => 'present',
            description => 'secured',
            domain      => undef,
            impl        => 'StringCredentialsImpl',
            scope       => 'GLOBAL',
            secret      => 'shh',
          }

          jenkins_slaveagent_port { '44445':
            ensure => 'present',
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/credentials.xml') do
      it { is_expected.to contain '<id>c6d2e3b4-1f2a-4b5c-8d9e-0a1b2c3d4e5f</id>' }
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<slaveAgentPort>44445</slaveAgentPort>' }
    end
  end

  context 'jenkins::cli based defines' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{security.call('full_control')}

          jenkins::cli::exec { 'set_num_executors':
            command => ['set_num_executors', 5],
            unless  => '[ $($HELPER_CMD get_num_executors) -eq 5 ]',
          }

          jenkins::job { 'secured-job':
            config => '#{test_build_job}',
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<numExecutors>5</numExecutors>' }
    end

    describe file('/var/lib/jenkins/jobs/secured-job/config.xml') do
      it { is_expected.to contain '<description>secured job</description>' }
    end
  end

  # leave jenkins unsecured for the specs that follow
  context 'disable security' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { security.call('unsecured') }
    end

    describe command("echo 'println 1' | #{cli} groovy =") do
      its(:exit_status) { is_expected.to eq 0 }
    end
  end
end
