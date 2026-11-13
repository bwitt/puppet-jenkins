# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'jenkins_security_realm', order: :defined do
  let(:base) do
    <<~PUPPET
      include jenkins

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
        ensure   => 'present',
        password => '#jbcrypt:$2a$10$QiROEodyzg1oqvxYGGZPUuC01WIUjeb5LJB84hhTjRJTCcYHg95JS',
      }
    PUPPET
  end

  context 'HudsonPrivateSecurityRealm' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{base}

          jenkins_security_realm { 'hudson.security.HudsonPrivateSecurityRealm':
            ensure    => 'present',
            arguments => [false, false, undef],
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<securityRealm class="hudson.security.HudsonPrivateSecurityRealm">' }
    end
  end

  context 'ensure => absent' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<~PUPPET
          #{base}

          jenkins_security_realm { 'hudson.security.HudsonPrivateSecurityRealm':
            ensure => 'absent',
          }
        PUPPET
      end
    end

    describe file('/var/lib/jenkins/config.xml') do
      it { is_expected.to contain '<securityRealm class="hudson.security.SecurityRealm$None"/>' }
    end
  end
end
