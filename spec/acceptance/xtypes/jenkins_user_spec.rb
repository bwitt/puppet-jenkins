# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'jenkins_user', order: :defined do
  # purge_plugins ensures the mailer and sshd plugins are not installed
  context 'without the mailer and sshd plugins' do
    context 'ensure => present' do
      it_behaves_like 'an idempotent resource' do
        let(:manifest) do
          <<~PUPPET
            class { 'jenkins':
              purge_plugins => true,
            }
            include jenkins::cli::config

            # bcrypt hash of 'hunter2'
            jenkins_user { 'puppet':
              ensure    => 'present',
              full_name => 'puppet user',
              password  => '#jbcrypt:$2a$10$QiROEodyzg1oqvxYGGZPUuC01WIUjeb5LJB84hhTjRJTCcYHg95JS',
            }
          PUPPET
        end
      end

      describe command('grep -rl "<fullName>puppet user</fullName>" /var/lib/jenkins/users') do
        its(:exit_status) { is_expected.to eq 0 }
      end
    end

    context 'ensure => absent' do
      it_behaves_like 'an idempotent resource' do
        let(:manifest) do
          <<~PUPPET
            class { 'jenkins':
              purge_plugins => true,
            }
            include jenkins::cli::config

            jenkins_user { 'puppet':
              ensure => 'absent',
            }
          PUPPET
        end
      end

      describe command('grep -rl "<fullName>puppet user</fullName>" /var/lib/jenkins/users') do
        its(:exit_status) { is_expected.not_to eq 0 }
      end
    end
  end
end
