package Koha::Plugin::Com::ByWaterSolutions::PrintHolds;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Auth;
use C4::Letters;

use YAML::XS;

## Here we set our plugin version
our $VERSION         = "{VERSION}";
our $MINIMUM_VERSION = "{MINIMUM_VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Auto-Print Holds',
    author          => 'Kyle M Hall',
    date_authored   => '2009-01-27',
    date_updated    => "1900-01-01",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Plugin to automatically print hold slips to printers as holds are placed',
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub after_hold_create {
    my ( $self, $hold ) = @_;

    my $printers = Load( $self->retrieve_data('printers_configuration') );

    my $letter = C4::Letters::GetPreparedLetter(
        module      => 'reserves',
        letter_code => 'HOLD_PLACED_PRINT',
        branchcode  => $hold->{branchcode},
        tables      => {
            'branches'    => $hold->branchcode,
            'biblio'      => $hold->biblionumber,
            'biblioitems' => $hold->biblionumber,
            'items'       => $hold->itemnumber,
            'borrowers'   => $hold->borrowernumber,
        }
    );

    if ( defined $printers->{ $hold->branchcode } ) {
        my ( $success, $error ) = $self->print(
            {
                printer => $printers->{ $hold->branchcode },
                data    => $letter->{content},
                is_html => $letter->{is_html},
            }
        );

        warn "PrintHolds Plugin Error: $error" if $error;
    }
}

sub print {
    my ( $self, $params ) = @_;

    my $printer = $params->{printer};
    my $data    = $params->{data};
    my $is_html = $params->{is_html};

    return unless ($data);

    if ($is_html) {
        require HTML::HTMLDoc;
        my $htmldoc = new HTML::HTMLDoc('mode'=>'file');
        $htmldoc->set_output_format('ps');
        $htmldoc->set_html_content($data);
        my $doc = $htmldoc->generate_pdf();
        $data = $doc->to_string();
    }

    my ( $result, $error );

    if ( $printer->{queue} ) {

        # Printer has a server:port address, use Net::Printer
        require Net::Printer;

        my ( $server, $port ) = split( /:/, $printer->{queue} );

        my $p = new Net::Printer(
            printer     => $printer->{name},
            server      => $server,
            port        => $port,
            lineconvert => "YES"
        );

        $result = $p->printstring($data);

        $error = $p->printerror();
    }
    else {
        require Printer;

        my $name = $printer->{name};

        my $p = new Printer( 'linux' => 'lp' );
        $p->print_command(
            linux => {
                type    => 'pipe',
                command => "lp -d $name",
            }
        );

        $result = $p->print($data);
    }

    return ( $result eq '1', $error );
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        eval "use Net::Printer; 1"  or $template->param( no_net_printer  => 1 );
        eval "use Printer; 1"       or $template->param( no_printer      => 1 );
        eval "use HTML::HTMLDoc; 1" or $template->param( no_html_htmldoc => 1 );

        ## Grab the values we already have for our settings, if any exist
        $template->param( printers_configuration =>
              $self->retrieve_data('printers_configuration') );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                printers_configuration => $cgi->param('printers_configuration'),
            }
        );
        $self->go_home();
    }
}

sub install() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('mytable');

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

sub uninstall() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('mytable');

    return 1;
}

1;
