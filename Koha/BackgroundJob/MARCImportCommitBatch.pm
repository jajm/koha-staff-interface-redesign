package Koha::BackgroundJob::MARCImportCommitBatch;

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
use Try::Tiny;

use base 'Koha::BackgroundJob';

use Koha::Import::Records;
use C4::ImportBatch qw(
    BatchCommitRecords
);

=head1 NAME

Koha::BackgroundJob::MARCImportCommitBatch - Commit records

This is a subclass of Koha::BackgroundJob.

=head1 API

=head2 Class methods

=head3 job_type

Define the job type of this job: marc_import_commit_batch

=cut

sub job_type {
    return 'marc_import_commit_batch';
}

=head3 process

Commit the records

=cut

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my $import_batch_id = $args->{import_batch_id};
    my $frameworkcode = $args->{frameworkcode};

    my @messages;
    my $job_progress = 0;

    my ( $num_added, $num_updated, $num_items_added,
        $num_items_replaced, $num_items_errored, $num_ignored );
    try {
        my $size = Koha::Import::Records->search({ import_batch_id => $import_batch_id })->count;
        $self->size($size)->store;
        (
            $num_added, $num_updated, $num_items_added,
            $num_items_replaced, $num_items_errored, $num_ignored
          )
          = BatchCommitRecords( $import_batch_id, $frameworkcode, 50,
            sub { my $job_progress = shift; $self->progress( $job_progress )->store } );
    }
    catch {
        warn $_;
        die "Something terrible has happened!"
          if ( $_ =~ /Rollback failed/ );    # Rollback failed
    };

    my $report = {
        num_added          => $num_added,
        num_updated        => $num_updated,
        num_items_added    => $num_items_added,
        num_items_replaced => $num_items_replaced,
        num_items_errored  => $num_items_errored,
        num_ignored        => $num_ignored
    };
    my $data = $self->decoded_data;
    $data->{messages} = \@messages;
    $data->{report}   = $report;

    $self->finish($data);
}

=head3 enqueue

Enqueue the new job

=cut

sub enqueue {
    my ( $self, $args) = @_;

    $self->SUPER::enqueue({
        job_size => 0, # unknown for now
        job_args => $args
    });
}

1;