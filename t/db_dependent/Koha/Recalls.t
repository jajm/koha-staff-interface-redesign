#!/usr/bin/perl

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

use Test::More tests => 19;
use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::DateUtils qw( dt_from_string );

BEGIN {
    require_ok('Koha::Recall');
    require_ok('Koha::Recalls');
}

# Start transaction

my $database = Koha::Database->new();
my $schema = $database->schema();
$schema->storage->txn_begin();
my $dbh = C4::Context->dbh;

my $builder = t::lib::TestBuilder->new;

# Setup test variables

my $item1 = $builder->build_sample_item();
my $biblio1 = $item1->biblio;
my $branch1 = $item1->holdingbranch;
my $itemtype1 = $item1->effective_itemtype;
my $item2 = $builder->build_sample_item({ biblionumber => $biblio1->biblionumber });
my $biblio2 = $item1->biblio;
my $branch2 = $item1->holdingbranch;
my $itemtype2 = $item1->effective_itemtype;

my $category1 = $builder->build({ source => 'Category' })->{ categorycode };
my $patron1 = $builder->build_object({ class => 'Koha::Patrons', value => { categorycode => $category1, branchcode => $branch1 } });
my $patron2 = $builder->build_object({ class => 'Koha::Patrons', value => { categorycode => $category1, branchcode => $branch2 } });
my $patron3 = $builder->build_object({ class => 'Koha::Patrons', value => { categorycode => $category1, branchcode => $branch1 } });
t::lib::Mocks::mock_userenv({ patron => $patron1 });

Koha::CirculationRules->set_rules({
    branchcode => undef,
    categorycode => undef,
    itemtype => undef,
    rules => {
        'recall_due_date_interval' => undef,
        'recalls_allowed' => 10,
    }
});

C4::Circulation::AddIssue( $patron3->unblessed, $item1->barcode );
C4::Circulation::AddIssue( $patron3->unblessed, $item2->barcode );

my ( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => undef,
    biblio => $biblio1,
    branchcode => $branch1,
    item => $item1,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
ok( !defined $recall, "Can't add a recall without specifying a patron" );

( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron1,
    biblio => undef,
    branchcode => $branch1,
    item => $item1,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
ok( !defined $recall, "Can't add a recall without specifying a biblio" );

( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron1,
    biblio => undef,
    branchcode => $branch1,
    item => $item1,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
ok( !defined $recall, "Can't add a recall without specifying a biblio" );

( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron2,
    biblio => $biblio1,
    branchcode => undef,
    item => $item2,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
is( $recall->branchcode, $branch2, "No pickup branch specified so patron branch used" );
is( $due_interval, 5, "Recall due date interval defaults to 5 if not specified" );

Koha::CirculationRules->set_rule({
    branchcode => undef,
    categorycode => undef,
    itemtype => undef,
    rule_name => 'recall_due_date_interval',
    rule_value => 3,
});
( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron1,
    biblio => $biblio1,
    branchcode => undef,
    item => $item1,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
is( $due_interval, 3, "Recall due date interval is based on circulation rules" );

( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron1,
    biblio => $biblio1,
    branchcode => $branch1,
    item => undef,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
is( $recall->item_level_recall, 0, "No item provided so recall not flagged as item-level" );

my $expected_due_date = dt_from_string->add( days => 3 );
is( dt_from_string( $recall->checkout->date_due ), $expected_due_date, "Checkout due date has correctly been extended by recall_due_date_interval days" );
is( $due_date, $expected_due_date, "Due date correctly returned" );

my $messages_count = Koha::Notice::Messages->search({ borrowernumber => $patron3->borrowernumber, letter_code => 'RETURN_RECALLED_ITEM' })->count;
is( $messages_count, 3, "RETURN_RECALLED_ITEM notice successfully sent to checkout borrower" );

my $message = Koha::Recalls->move_recall;
is( $message, 'no recall_id provided', "Can't move a recall without specifying which recall" );

$message = Koha::Recalls->move_recall({ recall_id => $recall->recall_id });
is( $message, 'no action provided', "No clear action to perform on recall" );
$message = Koha::Recalls->move_recall({ recall_id => $recall->recall_id, action => 'whatever' });
is( $message, 'no action provided', "Legal action not provided to perform on recall" );

$recall->set_waiting({ item => $item1 });
ok( $recall->waiting, "Recall is waiting" );
Koha::Recalls->move_recall({ recall_id => $recall->recall_id, action => 'revert' });
$recall = Koha::Recalls->find( $recall->recall_id );
ok( $recall->requested, "Recall reverted to requested with move_recall" );

Koha::Recalls->move_recall({ recall_id => $recall->recall_id, action => 'cancel' });
$recall = Koha::Recalls->find( $recall->recall_id );
ok( $recall->cancelled, "Recall cancelled with move_recall" );

( $recall, $due_interval, $due_date ) = Koha::Recalls->add_recall({
    patron => $patron1,
    biblio => $biblio1,
    branchcode => $branch1,
    item => $item2,
    expirationdate => undef,
    interface => 'COMMANDLINE',
});
$message = Koha::Recalls->move_recall({ recall_id => $recall->recall_id, item => $item2, borrowernumber => $patron1->borrowernumber });
$recall = Koha::Recalls->find( $recall->recall_id );
ok( $recall->finished, "Recall fulfilled with move_recall" );

$schema->storage->txn_rollback();