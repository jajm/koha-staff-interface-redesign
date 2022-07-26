#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 1;
use Test::Mojo;
use Test::MockModule;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# FIXME: sessionStorage defaults to mysql, but it seems to break transaction handling
# this affects the other REST api tests
t::lib::Mocks::mock_preference( 'SessionStorage', 'tmp' );

my $remote_address = '127.0.0.1';
my $t              = Test::Mojo->new('Koha::REST::V1');

my $mocked_koha_email = Test::MockModule->new('Koha::Email');
$mocked_koha_email->mock( 'send_or_die', sub {
    return 1;
});

subtest 'send_otp_token' => sub {

    plan tests => 11;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value  => {
                flags => 20, # Staff access and Patron info
            }
        }
    );

    my $session = C4::Auth::get_session('');
    $session->param( 'ip',       '127.0.0.1' );
    $session->param( 'lasttime', time() );
    $session->flush;

    my $tx = $t->ua->build_tx( POST => "/api/v1/auth/otp/token_delivery" );
    $tx->req->cookies( { name => 'CGISESSID', value => $session->id } );
    $tx->req->env( { REMOTE_ADDR => $remote_address } );

    # Patron is not authenticated yet
    $t->request_ok($tx)->status_is(401);

    # Patron is partially authenticated (credentials correct)
    $session->param( 'number',   $patron->borrowernumber );
    $session->param( 'id',       $patron->userid );
    $session->param('waiting-for-2FA', 1);
    $session->flush;

    $patron->library->set(
        {
            branchemail      => 'from@example.org',
            branchreturnpath => undef,
            branchreplyto    => undef,
        }
    )->store;
    $patron->auth_method('two-factor');
    $patron->encode_secret("nv4v65dpobpxgzldojsxiii");
    $patron->email(undef);
    $patron->store;

    $tx = $t->ua->build_tx( POST => "/api/v1/auth/otp/token_delivery" );
    $tx->req->cookies( { name => 'CGISESSID', value => $session->id } );
    $tx->req->env( { REMOTE_ADDR => $remote_address } );

    # Invalid email
    $t->request_ok($tx)->status_is(400)->json_is({ error => 'email_not_sent' });

    $patron->email('to@example.org')->store;
    $tx = $t->ua->build_tx( POST => "/api/v1/auth/otp/token_delivery" );
    $tx->req->cookies( { name => 'CGISESSID', value => $session->id } );
    $tx->req->env( { REMOTE_ADDR => $remote_address } );

    # Everything is ok, the email will be sent
    $t->request_ok($tx)->status_is(200);

    # Change flags: not enough authorization anymore
    $patron->flags(16)->store;
    $tx = $t->ua->build_tx( POST => "/api/v1/auth/otp/token_delivery" );
    $tx->req->cookies( { name => 'CGISESSID', value => $session->id } );
    $tx->req->env( { REMOTE_ADDR => $remote_address } );
    $t->request_ok($tx)->status_is(403);
    $patron->flags(20)->store;

    # Patron is fully authenticated, cannot request a token again
    $session->param('waiting-for-2FA', 0);
    $session->flush;
    $tx = $t->ua->build_tx( POST => "/api/v1/auth/otp/token_delivery" );
    $tx->req->cookies( { name => 'CGISESSID', value => $session->id } );
    $tx->req->env( { REMOTE_ADDR => $remote_address } );

    $t->request_ok($tx)->status_is(401);

    $schema->storage->txn_rollback;
};

1;
