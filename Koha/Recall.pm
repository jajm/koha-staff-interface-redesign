package Koha::Recall;

# Copyright 2020 Aleisha Amohia <aleisha@catalyst.net.nz>
#
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

use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
use Koha::Patron;
use Koha::Biblio;
use Koha::Item;

use base qw(Koha::Object);

=head1 NAME

Koha::Recall - Koha Recall Object class

=head1 API

=head2 Internal methods

=cut

=head3 biblio

    my $biblio = $recall->biblio;

Returns the related Koha::Biblio object for this recall.

=cut

sub biblio {
    my ( $self ) = @_;
    my $biblio_rs = $self->_result->biblio;
    return unless $biblio_rs;
    return Koha::Biblio->_new_from_dbic( $biblio_rs );
}

=head3 item

    my $item = $recall->item;

Returns the related Koha::Item object for this recall.

=cut

sub item {
    my ( $self ) = @_;
    my $item_rs = $self->_result->item;
    return unless $item_rs;
    return Koha::Item->_new_from_dbic( $item_rs );
}

=head3 patron

    my $patron = $recall->patron;

Returns the related Koha::Patron object for this recall.

=cut

sub patron {
    my ( $self ) = @_;
    my $patron_rs = $self->_result->borrower;
    return unless $patron_rs;
    return Koha::Patron->_new_from_dbic( $patron_rs );
}

=head3 library

    my $library = $recall->library;

Returns the related Koha::Library object for this recall.

=cut

sub library {
    my ( $self ) = @_;
    $self->{_library} = Koha::Libraries->find( $self->branchcode );
    return $self->{_library};
}

=head3 checkout

    my $checkout = $recall->checkout;

Returns the related Koha::Checkout object for this recall.

=cut

sub checkout {
    my ( $self ) = @_;
    $self->{_checkout} ||= Koha::Checkouts->find({ itemnumber => $self->itemnumber });

    unless ( $self->item_level_recall ) {
        # Only look at checkouts of items that are allowed to be recalled, and get the oldest one
        my @items = Koha::Items->search({ biblionumber => $self->biblionumber });
        my @itemnumbers;
        foreach (@items) {
            my $recalls_allowed = Koha::CirculationRules->get_effective_rule({
                branchcode => C4::Context->userenv->{'branch'},
                categorycode => $self->patron->categorycode,
                itemtype => $_->effective_itemtype,
                rule_name => 'recalls_allowed',
            });
            if ( defined $recalls_allowed and $recalls_allowed->rule_value > 0 ) {
                push ( @itemnumbers, $_->itemnumber );
            }
        }
        my $checkouts = Koha::Checkouts->search({ itemnumber => [ @itemnumbers ] }, { order_by => { -asc => 'date_due' } });
        $self->{_checkout} = $checkouts->next;
    }

    return $self->{_checkout};
}

=head3 requested

    if ( $recall->requested )

    [% IF recall.requested %]

Return true if recall status is requested.

=cut

sub requested {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'R';
}

=head3 waiting

    if ( $recall->waiting )

    [% IF recall.waiting %]

Return true if recall is awaiting pickup.

=cut

sub waiting {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'W';
}

=head3 overdue

    if ( $recall->overdue )

    [% IF recall.overdue %]

Return true if recall is overdue to be returned.

=cut

sub overdue {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'O';
}

=head3 in_transit

    if ( $recall->in_transit )

    [% IF recall.in_transit %]

Return true if recall is in transit.

=cut

sub in_transit {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'T';
}

=head3 expired

    if ( $recall->expired )

    [% IF recall.expired %]

Return true if recall has expired.

=cut

sub expired {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'E';
}

=head3 cancelled

    if ( $recall->cancelled )

    [% IF recall.cancelled %]

Return true if recall has been cancelled.

=cut

sub cancelled {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'C';
}

=head3 finished

    if ( $recall->finished )

    [% IF recall.finished %]

Return true if recall is finished and has been fulfilled.

=cut

sub finished {
    my ( $self ) = @_;
    my $status = $self->status;
    return $status && $status eq 'F';
}

=head3 calc_expirationdate

    my $expirationdate = $recall->calc_expirationdate;
    $recall->update({ expirationdate => $expirationdate });

Calculate the expirationdate to set based on circulation rules and system preferences.

=cut

sub calc_expirationdate {
    my ( $self ) = @_;

    my $item;
    if ( $self->item_level_recall ) {
        $item = $self->item;
    } elsif ( $self->checkout ) {
        $item = $self->checkout->item;
    }

    my $branchcode = $self->patron->branchcode;
    if ( $item ) {
        $branchcode = C4::Circulation::_GetCircControlBranch( $item->unblessed, $self->patron->unblessed );
    }

    my $rule = Koha::CirculationRules->get_effective_rule({
        categorycode => $self->patron->categorycode,
        branchcode => $branchcode,
        itemtype => $item ? $item->effective_itemtype : undef,
        rule_name => 'recall_shelf_time'
    });

    my $shelf_time = defined $rule ? $rule->rule_value : C4::Context->preference('RecallsMaxPickUpDelay');

    my $expirationdate = dt_from_string->add( days => $shelf_time );
    return $expirationdate;
}

=head3 start_transfer

    my ( $recall, $dotransfer, $messages ) = $recall->start_transfer({ item => $item_object });

Set the recall as in transit.

=cut

sub start_transfer {
    my ( $self, $params ) = @_;

    if ( $self->item_level_recall ) {
        # already has an itemnumber
        $self->update({ status => 'T' });
    } else {
        my $itemnumber = $params->{item}->itemnumber;
        $self->update({ status => 'T', itemnumber => $itemnumber });
    }

    my ( $dotransfer, $messages ) = C4::Circulation::transferbook({ to_branch => $self->branchcode, from_branch => $self->item->holdingbranch, barcode => $self->item->barcode, trigger => 'Recall' });

    return ( $self, $dotransfer, $messages );
}

=head3 revert_transfer

    $recall->revert_transfer;

If a transfer is cancelled, revert the recall to requested.

=cut

sub revert_transfer {
    my ( $self ) = @_;

    if ( $self->item_level_recall ) {
        $self->update({ status => 'R' });
    } else {
        $self->update({ status => 'R', itemnumber => undef });
    }

    return $self;
}

=head3 set_waiting

    $recall->set_waiting({
        expirationdate => $expirationdate,
        item => $item_object
    });

Set the recall as waiting and update expiration date.
Notify the recall requester.

=cut

sub set_waiting {
    my ( $self, $params ) = @_;

    my $itemnumber;
    if ( $self->item_level_recall ) {
        $itemnumber = $self->itemnumber;
        $self->update({ status => 'W', waitingdate => dt_from_string, expirationdate => $params->{expirationdate} });
    } else {
        # biblio-level recall with no itemnumber. need to set itemnumber
        $itemnumber = $params->{item}->itemnumber;
        $self->update({ status => 'W', waitingdate => dt_from_string, expirationdate => $params->{expirationdate}, itemnumber => $itemnumber });
    }

    # send notice to recaller to pick up item
    my $letter = C4::Letters::GetPreparedLetter(
        module => 'circulation',
        letter_code => 'PICKUP_RECALLED_ITEM',
        branchcode => $self->branchcode,
        want_librarian => 0,
        tables => {
            biblio => $self->biblionumber,
            borrowers => $self->borrowernumber,
            items => $itemnumber,
            recalls => $self->recall_id,
        },
    );

    C4::Message->enqueue($letter, $self->patron->unblessed, 'email');

    return $self;
}

=head3 revert_waiting

    $recall->revert_waiting;

Revert recall waiting status.

=cut

sub revert_waiting {
    my ( $self ) = @_;
    if ( $self->item_level_recall ){
        $self->update({ status => 'R', waitingdate => undef });
    } else {
        $self->update({ status => 'R', waitingdate => undef, itemnumber => undef });
    }
    return $self;
}

=head3 should_be_overdue

    if ( $recall->should_be_overdue ) {
        $recall->set_overdue;
    }

Return true if this recall should be marked overdue

=cut

sub should_be_overdue {
    my ( $self ) = @_;
    if ( $self->requested and $self->checkout and dt_from_string( $self->checkout->date_due ) <= dt_from_string ) {
        return 1;
    }
    return 0;
}

=head3 set_overdue

    $recall->set_overdue;

Set a recall as overdue when the recall has been requested and the borrower who has checked out the recalled item is late to return it. This can be done manually by the library or by cronjob. The interface is either 'INTRANET' or 'COMMANDLINE' for logging purposes.

=cut

sub set_overdue {
    my ( $self, $params ) = @_;
    my $interface = $params->{interface} || 'COMMANDLINE';
    $self->update({ status => 'O' });
    C4::Log::logaction( 'RECALLS', 'OVERDUE', $self->recall_id, "Recall status set to overdue", $interface ) if ( C4::Context->preference('RecallsLog') );
    return $self;
}

=head3 set_expired

    $recall->set_expired({ interface => 'INTRANET' });

Set a recall as expired. This may be done manually or by a cronjob, either when the borrower that placed the recall takes more than RecallsMaxPickUpDelay number of days to collect their item, or if the specified expirationdate passes. The interface is either 'INTRANET' or 'COMMANDLINE' for logging purposes.

=cut

sub set_expired {
    my ( $self, $params ) = @_;
    my $interface = $params->{interface} || 'COMMANDLINE';
    $self->update({ status => 'E', old => 1, expirationdate => dt_from_string });
    C4::Log::logaction( 'RECALLS', 'EXPIRE', $self->recall_id, "Recall expired", $interface ) if ( C4::Context->preference('RecallsLog') );
    return $self;
}

=head3 set_cancelled

    $recall->set_cancelled;

Set a recall as cancelled. This may be done manually, either by the borrower that placed the recall, or by the library.

=cut

sub set_cancelled {
    my ( $self ) = @_;
    $self->update({ status => 'C', old => 1, cancellationdate => dt_from_string });
    C4::Log::logaction( 'RECALLS', 'CANCEL', $self->recall_id, "Recall cancelled", 'INTRANET' ) if ( C4::Context->preference('RecallsLog') );
    return $self;
}

=head3 set_finished

    $recall->set_finished;

Set a recall as finished. This should only be called when the item allocated to a recall is checked out to the borrower who requested the recall.

=cut

sub set_finished {
    my ( $self ) = @_;
    $self->update({ status => 'F', old => 1 });
    C4::Log::logaction( 'RECALLS', 'FULFILL', $self->recall_id, "Recall fulfilled", 'INTRANET' ) if ( C4::Context->preference('RecallsLog') );
    return $self;
}

=head3 _type

=cut

sub _type {
    return 'Recall';
}

1;