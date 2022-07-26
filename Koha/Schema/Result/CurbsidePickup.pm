use utf8;
package Koha::Schema::Result::CurbsidePickup;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::CurbsidePickup

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<curbside_pickups>

=cut

__PACKAGE__->table("curbside_pickups");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 borrowernumber

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 branchcode

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 10

=head2 scheduled_pickup_datetime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 staged_datetime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 staged_by

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 arrival_datetime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 delivered_datetime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 delivered_by

  data_type: 'integer'
  is_nullable: 1

=head2 notes

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "borrowernumber",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "branchcode",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 10 },
  "scheduled_pickup_datetime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "staged_datetime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "staged_by",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "arrival_datetime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "delivered_datetime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "delivered_by",
  { data_type => "integer", is_nullable => 1 },
  "notes",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 borrowernumber

Type: belongs_to

Related object: L<Koha::Schema::Result::Borrower>

=cut

__PACKAGE__->belongs_to(
  "borrowernumber",
  "Koha::Schema::Result::Borrower",
  { borrowernumber => "borrowernumber" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 branchcode

Type: belongs_to

Related object: L<Koha::Schema::Result::Branch>

=cut

__PACKAGE__->belongs_to(
  "branchcode",
  "Koha::Schema::Result::Branch",
  { branchcode => "branchcode" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 curbside_pickup_issues

Type: has_many

Related object: L<Koha::Schema::Result::CurbsidePickupIssue>

=cut

__PACKAGE__->has_many(
  "curbside_pickup_issues",
  "Koha::Schema::Result::CurbsidePickupIssue",
  { "foreign.curbside_pickup_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 staged_by

Type: belongs_to

Related object: L<Koha::Schema::Result::Borrower>

=cut

__PACKAGE__->belongs_to(
  "staged_by",
  "Koha::Schema::Result::Borrower",
  { borrowernumber => "staged_by" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-06-27 11:58:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8gt7Vqurdid0rwmBMPI5yg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
