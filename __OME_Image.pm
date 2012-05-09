# OME/Web/DBObjRender/__OME_Image.pm
#-------------------------------------------------------------------------------
#
# Copyright (C) 2003 Open Microscopy Environment
#		Massachusetts Institute of Technology,
#		National Institutes of Health,
#		University of Dundee
#
#
#
#	 This library is free software; you can redistribute it and/or
#	 modify it under the terms of the GNU Lesser General Public
#	 License as published by the Free Software Foundation; either
#	 version 2.1 of the License, or (at your option) any later version.
#
#	 This library is distributed in the hope that it will be useful,
#	 but WITHOUT ANY WARRANTY; without even the implied warranty of
#	 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#	 Lesser General Public License for more details.
#
#	 You should have received a copy of the GNU Lesser General Public
#	 License along with this library; if not, write to the Free Software
#	 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#-------------------------------------------------------------------------------




#-------------------------------------------------------------------------------
#
# Written by:  
#	Josiah Johnston <siah@nih.gov>
#
#-------------------------------------------------------------------------------


package OME::Web::DBObjRender::__OME_Image;

=pod

=head1 NAME

OME::Web::DBObjRender::__OME_Image - Specialized rendering for OME::Image

=head1 DESCRIPTION

Provides custom behavior for rendering an OME::Image

=head1 METHODS

=cut

use strict;
use OME;
our $VERSION = $OME::VERSION;

use OME::Tasks::ImageManager;
use OME::Session;
use OME::Tasks::ModuleExecutionManager;
use OME::Web::XMLFileExport;
use Carp 'cluck';
use base qw(OME::Web::DBObjRender);
#ALTERED CODE
use Archive::Zip;
#END ALTERED CODE


=head2 _renderData

makes virtual fields 
	thumb_url: an href to the thumbnail of the Image's default pixels
	export_url: an href to download an ome xml file of this image
	current_annotation: the text contents of the current Image annotation
		according to OME::Tasks::ImageManager->getCurrentAnnotation()
	current_annotation_author: A ref to the author of the current annotation 
		iff it was not written by the user
	annotation_count: The total number of annotations about this image
	original_file: HTML snippet containing one or more links to the image's
		original files (if any exist)

=cut

sub _renderData {
	my ($self, $obj, $field_requests, $options) = @_;
	my $session = OME::Session->instance();
	my $factory = $session->Factory();
	my $q       = $self->CGI();
	my %record;

	# thumbnail url
	if( exists $field_requests->{ 'thumb_url' } ) {
		foreach my $request ( @{ $field_requests->{ 'thumb_url' } } ) {
			my $request_string = $request->{ 'request_string' };
			$record{ $request_string } = OME::Tasks::ImageManager->getThumbURL( $obj );
		}
	}
	# export url
	if( exists $field_requests->{ 'export_url' } ) {
		foreach my $request ( @{ $field_requests->{ 'export_url' } } ) {
			my $request_string = $request->{ 'request_string' };
			$record{ $request_string } = OME::Web::XMLFileExport->getURLtoExport( $obj->name().'.ome', $obj->id );
		}
	}
	# current_annotation:
	if( exists $field_requests->{ 'current_annotation' } ) {
		foreach my $request ( @{ $field_requests->{ 'current_annotation' } } ) {
			my $request_string = $request->{ 'request_string' };
			my $currentAnnotation = OME::Tasks::ImageManager->
				getCurrentAnnotation( $obj );
			$record{ $request_string } = $currentAnnotation->Content
				if $currentAnnotation;
		}
	}
	# last_data_1
	if( exists $field_requests->{ 'last_data_1' } ) {
		foreach my $request ( @{ $field_requests->{ 'last_data_1' } } ) {
			my $request_string = $request->{ 'request_string' };
			my @mexes = $obj->module_executions( __order => '!timestamp' );
			my $last_module_execution = $mexes[0];
			my @untypedOutputs = $last_module_execution->untypedOutputs();
			my @STs = map( $_->semantic_type, @untypedOutputs );
	    	my $first_ST = $STs[0];
			my $attributes = OME::Tasks::ModuleExecutionManager->
	    		getAttributesForMEX($last_module_execution,$first_ST);
			my $last_data_1 = $attributes->[0];
			$record{ $request_string } = $self->Renderer()->render( $last_data_1, 'ref' );
		}
	}
	# last_data_2
	if( exists $field_requests->{ 'last_data_2' } ) {
		foreach my $request ( @{ $field_requests->{ 'last_data_2' } } ) {
			my $request_string = $request->{ 'request_string' };
			my @mexes = $obj->module_executions( __order => '!timestamp' );
			my $last_module_execution = $mexes[1];
			my $ST;
			if( $last_module_execution->count_formal_outputs() == 0 ) {
				my @untypedOutputs = $last_module_execution->untypedOutputs();
				my @STs = map( $_->semantic_type, @untypedOutputs );
	    		$ST = $STs[0];
	    	} else {
				my @STs = $last_module_execution->formal_outputs();
	    		$ST = $STs[0];
	    	}
			my $attributes = OME::Tasks::ModuleExecutionManager->
	    		getAttributesForMEX($last_module_execution,$ST);
			my $last_data_2 = $attributes->[0];
			$record{ $request_string } = $self->Renderer()->render( $last_data_2, 'ref' );
		}
	}
	
	# current_annotation_author:
	if( exists $field_requests->{ 'current_annotation_author' } ) {
		foreach my $request ( @{ $field_requests->{ 'current_annotation_author' } } ) {
			my $request_string = $request->{ 'request_string' };
			my $currentAnnotation = OME::Tasks::ImageManager->
				getCurrentAnnotation( $obj );
			$record{ $request_string } = $self->Renderer()->
				render( $currentAnnotation->module_execution->experimenter(), 'ref' )
				if( ( defined $currentAnnotation ) && 
# a bug in the ACLs are not always letting the mex come through. so, hack-around
				    ( defined $currentAnnotation->module_execution ) &&
				    ( $currentAnnotation->module_execution->experimenter->id() ne 
				      $session->User()->id() )
				);
		}
	}
	# annotation_count:
	if( exists $field_requests->{ 'annotation_count' } ) {
		foreach my $request ( @{ $field_requests->{ 'annotation_count' } } ) {
			my $request_string = $request->{ 'request_string' };
			$record{ $request_string } = $factory->
				countObjects( '@ImageAnnotation', image => $obj );
		}
	}
	# annotationSTs:
	if( exists $field_requests->{ 'annotationSTs' } ) {
		foreach my $request ( @{ $field_requests->{ 'annotationSTs' } } ) {
			my $request_string = $request->{ 'request_string' };
			my @imageSTs = $factory->findObjects( 'OME::SemanticType',
				granularity => 'I'
			);
			$record{ $request_string } = $q->popup_menu(
				-name     => 'annotateWithST',
				'-values' => [ '', map( '@'.$_->name(), @imageSTs ) ],
				-default  => '',
				-labels   => { 
					'' => '-- Select a Semantic Type --', 
					map{ '@'.$_->name() => $_->name } @imageSTs 
				}
			);
		}
	}	
	# original file
	if( exists $field_requests->{ 'original_file' } ) {

		foreach my $request ( @{ $field_requests->{ 'original_file' } } ) {
		    my $request_string = $request->{ 'request_string' };
			my $original_files = OME::Tasks::ImageManager->getImageOriginalFiles($obj);
			
			if( scalar( @$original_files ) > 1 ) {
				my $more_info_url = 
					$self->getSearchURL( 
 						'@OriginalFile',
 						id   => join( ',', map( $_->id, @$original_files ) ),
					);

				my $zip_url = $self->getDownloadAllURL($obj);

				$record{ $request_string } = 
					scalar( @$original_files )." files found. ".
					"<a href='$more_info_url'>See individual listings</a> or ".
					"<a href='$zip_url'>download them all at once</a>";
			} elsif( scalar( @$original_files ) == 1 ) {
				$record{ $request_string } = 
					$self->render( 
						$original_files->[0], 
						( $request->{ render } or 'ref' ), 
						$request 
					);
			} else {
				$record{ $request_string } = "No original files found";
			}
			my @original_file_links = map( 
				$self->render( $_, ( $request->{ render } or 'ref' ), $request ),
				@$original_files
			);
			
		}
	}
	
	return %record;
}

=head1 Author

Josiah Johnston <siah@nih.gov>

=cut

1;
