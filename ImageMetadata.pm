# OME/Web/ImageMetadata.pm

#-------------------------------------------------------------------------------
#
# Copyright (C) 2003 Open Microscopy Environment
#       Massachusetts Institute of Technology,
#       National Institutes of Health,
#       University of Dundee
#
#
#
#    This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser General Public
#    License as published by the Free Software Foundation; either
#    version 2.1 of the License, or (at your option) any later version.
#
#    This library is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser General Public License for more details.
#
#    You should have received a copy of the GNU Lesser General Public
#    License along with this library; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#-------------------------------------------------------------------------------




#-------------------------------------------------------------------------------
#
# Written by:    Michael Hlavenka <mthlavenka@wisc.edu>
#
#-------------------------------------------------------------------------------


package OME::Web::ImageMetadata;

=pod

=head1 NAME

OME::Web::ImageMetaData

=head1 DESCRIPTION


=cut

#*********
#********* INCLUDES
#*********

use strict;
use OME;
our $VERSION = $OME::VERSION;
use Log::Agent;
use Carp;
use Carp 'cluck';
use OME::Web::DBObjTable;

use base qw(OME::Web);

sub getPageTitle {
	my $self = shift;
	my $q    = $self->CGI();
	my $factory = $self->Session()->Factory();
	my $id = $q->param( 'ID' )
	    or die "ID not specified";
	my $image = $factory->loadObject( 'OME::Image', $id);

	if ($image) {
	    return $image->name()." (ID = ".$id.") Metadata\n";
	}
	else {
	    return "Image Metadata";
	}
    }

sub getPageBody {
    my $self = shift;
    my $q = $self->CGI();
    my $factory = $self->Session()->Factory();
    my $type = '@LogicalChannel';
    open STUFF, ">/home/mike/logs/metadata.txt";
    my $html;

    my $id = $q->param( 'ID' )
	or die "ID not specified";

    # Retrieving the Logical Channel and Image objects
    my ($package_name, $common_name, $formal_name, $ST) = $self->_loadTypeAndGetInfo( $type );
    my @objects = $factory->findObjects( $formal_name, {image_id => $id});
    my $image = $factory->loadObject( 'OME::Image', $id);

    my %uniqueHash;
    my %fieldHash;

    # Loading the Template
    my $tmpl_path = $self->Session()->Configuration()->template_dir();
    $tmpl_path .= '/System/Display/One/metadata.tmpl';
    my $tmpl = HTML::Template->new( filename => $tmpl_path, case_sensitive => 1 );
    my %tmpl_data;

    my @objInfo;

    while (my $obj = pop @objects) { 
	if (!$uniqueHash{$obj->getFormalName().$obj->id()}) {

	    %fieldHash = %{$obj->getDataHash()};
	    my @datums;
	    
	    while (my ($field_key, $field_val) = each %fieldHash) {
		if ($field_val) {
		    if (ref($field_val)) {
			push( @objects, $field_val );
			push( @datums, { name => $field_key, 
					 value => $q->a( {-href => $self->pageURL( "OME::Web::DBObjDetail", { ID => $field_val->id(), Type => $field_val->getFormalName() } )},
					 $field_val->id())
				     } );
		    } else {
			push( @datums, { name => $field_key, value => $field_val } );
		    }
		}
	    }
	    $uniqueHash{$obj->getFormalName().$obj->id()}++;

	    push( @objInfo, { '/title' => $obj->semantic_type->name(), '/datum' => \@datums, '/id' => $obj->id() } );
	}
    }
    
    $tmpl_data{ '/objInfo' } = \@objInfo;
    $tmpl_data{ '/img_name' } = $image->name() unless !$image;
    $tmpl_data{ '/img_id' } = $id;
    
    $tmpl->param(%tmpl_data);

    $html = $tmpl->output();

    close STUFF;
    return ('HTML',$html);
}

