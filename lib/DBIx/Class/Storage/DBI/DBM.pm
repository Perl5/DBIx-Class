package DBIx::Class::Storage::DBI::DBM;

use base 'DBIx::Class::Storage::DBI::SQL::Statement';
use mro 'c3';
use namespace::clean;

sub insert {
   my ($self, $source, $to_insert) = @_;

   my $col_infos = $source->columns_info;
   
   foreach my $col (keys %$col_infos) {
      # this will naturally fall into undef/NULL if default_value doesn't exist
      $to_insert->{$col} = $col_infos->{$col}{default_value}
         unless (exists $to_insert->{$col});
   }
   
   $self->next::method($source, $to_insert);
}

sub insert_bulk {
   my ($self, $source, $cols, $data) = @_;
   
   my $col_infos = $source->columns_info;

   foreach my $col (keys %$col_infos) {
      unless (grep { $_ eq $col } @$cols) {
         push @$cols, $col;
         for my $r (0 .. $#$data) {
            # this will naturally fall into undef/NULL if default_value doesn't exist
            $data->[$r][$#$cols] = $col_infos->{$col}{default_value};
         }
      }
   }
   
   $self->next::method($source, $cols, $data);
}
   
1;

=head1 NAME

DBIx::Class::Storage::DBI::SNMP - Support for DBM & MLDBM files via DBD::DBM

=head1 SYNOPSIS

This subclass supports DBM & MLDBM files via L<DBD::DBM>.

=head1 DESCRIPTION

This subclass is essentially just a stub that uses the super class
L<DBIx::Class::Storage::DBI::SQL::Statement>.

=head1 IMPLEMENTATION NOTES

=head2 Missing fields on INSERTs

L<DBD::DBM> will balk at missing columns on INSERTs.  This storage engine will
add them in with either the default_value attribute or NULL.

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut