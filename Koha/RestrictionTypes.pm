package Koha::RestrictionTypes;

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

use Carp;

use C4::Context;

use Koha::Database;
use Koha::RestrictionType;

use base qw(Koha::Objects);

=head1 NAME

Koha::RestrictionTypes - Koha Restriction Types Object set class

=head1 API

=head2 Class Methods

=cut

=head3 keyed_on_code

Return all restriction types as a hashref keyed on the code

=cut

sub keyed_on_code {
    my ( $self ) = @_;

    my @all = $self->_resultset()->search();
    my $out = {};
    for my $r( @all ) {
        my %col = $r->get_columns;
        $out->{$r->code} = \%col;
    }
    return $out;
}

=head3 _type

=cut

sub _type {
    return 'DebarmentType';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::RestrictionType';
}

1;