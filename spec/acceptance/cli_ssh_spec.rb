# frozen_string_literal: true

require 'spec_helper_acceptance'

# Exercises SSH authentication for the native types (via jenkins::cli::config)
# and the jenkins::cli based defines (via the jenkins class cli_* params).
describe 'jenkins cli over ssh', order: :defined do
  before(:context) do
    shell("test -f /root/jenkins_cli_key || ssh-keygen -q -t ed25519 -N '' -f /root/jenkins_cli_key")
  end

  let(:cli) { 'java -jar /usr/share/java/jenkins-cli.jar -s http://localhost:8080' }
  let(:pubkey) { shell('cat /root/jenkins_cli_key.pub').stdout.strip }

  let(:ssh) do
    lambda do |model|
      <<~PUPPET
        class { 'jenkins':
          cli_username    => 'admin',
          cli_ssh_keyfile => '/root/jenkins_cli_key',
        }

        class { 'jenkins::cli::config':
          cli_username    => 'admin',
          ssh_private_key => '/root/jenkins_cli_key',
        }

        jenkins::plugin { [
          'display-url-api',
          'jakarta-activation-api',
          'jakarta-mail-api',
          'mailer',
          'mina-sshd-api-common',
          'mina-sshd-api-core',
          'sshd',
        ]: }

        # the sshd server is disabled by default
        file { '/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml':
          ensure  => file,
          owner   => 'jenkins',
          group   => 'jenkins',
          replace => false,
          content => "<?xml version='1.1' encoding='UTF-8'?>\\n<org.jenkinsci.main.modules.sshd.SSHD>\\n  <port>2222</port>\\n</org.jenkinsci.main.modules.sshd.SSHD>",
          require => Class['jenkins::plugins'],
          notify  => Class['jenkins::service'],
        }

        # bcrypt hash of 'hunter2'
        jenkins_user { 'admin':
          ensure        => 'present',
          email_address => 'admin@example.org',
          full_name     => 'admin',
          password      => '#jbcrypt:$2a$10$QiROEodyzg1oqvxYGGZPUuC01WIUjeb5LJB84hhTjRJTCcYHg95JS',
          public_keys   => ['#{pubkey}'],
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
      let(:manifest) { ssh.call('full_control') }
    end

    describe 'cli' do
      # anonymous read is allowed by default, the helper needs administer
      it 'rejects anonymous access' do
        result = shell("echo 'println 1' | #{cli} -http groovy =", acceptable_exit_codes: (0..255))
        expect(result.stderr).to match %r{anonymous is missing the Overall/Administer permission}
      end

      it 'authenticates over ssh' do
        expect(shell("#{cli} -i /root/jenkins_cli_key -ssh -user admin who-am-i").stdout).to match %r{Authenticated as: admin}
      end
    end
  end

  context 'native types' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{ssh.call('full_control')}

          jenkins_slaveagent_port { '44446':
            ensure => 'present',
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<slaveAgentPort>44446</slaveAgentPort>' }
    end
  end

  context 'jenkins::cli based defines' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{ssh.call('full_control')}

          jenkins::cli::exec { 'set_num_executors':
            command => ['set_num_executors', 6],
            unless  => '[ $($HELPER_CMD get_num_executors) -eq 6 ]',
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<numExecutors>6</numExecutors>' }
    end
  end

  # leave jenkins unsecured for the specs that follow
  context 'disable security' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { ssh.call('unsecured') }
    end

    describe 'cli' do
      it 'allows anonymous access' do
        shell("echo 'println 1' | #{cli} -http groovy =")
      end
    end
  end
end
