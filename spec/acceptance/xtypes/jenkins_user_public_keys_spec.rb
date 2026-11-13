# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'jenkins_user public_keys' do
  let(:pubkey) { 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXbSfjJUjK03KZG7kYTiOTIKyE6Ud3HUwaw+epqhBjz puppet@example.com' }

  it_behaves_like 'an idempotent resource' do
    let(:manifest) do
      <<~PUPPET
        include jenkins
        include jenkins::cli::config

        jenkins::plugin { [
          'display-url-api',
          'jakarta-activation-api',
          'jakarta-mail-api',
          'mailer',
          'mina-sshd-api-common',
          'mina-sshd-api-core',
          'sshd',
        ]: }

        jenkins_user { 'keyuser':
          ensure      => 'present',
          full_name   => 'key user',
          public_keys => ['#{pubkey}'],
        }
      PUPPET
    end
  end

  describe command('cat /var/lib/jenkins/users/keyuser_*/config.xml') do
    its(:stdout) { is_expected.to include "<authorizedKeys>#{pubkey}</authorizedKeys>" }
  end
end
