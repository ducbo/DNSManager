package rt::user;

use v5.14;
use configuration ':all';
use encryption ':all';
use app;
use utf8;
use open qw/:std :utf8/;

use YAML::XS;

use Exporter 'import';
# what we want to export eventually
our @EXPORT_OK = qw/
rt_user_login
rt_user_del
rt_user_toggleadmin
rt_user_subscribe
rt_user_changepasswd
rt_user_add
rt_user_home
/;

# bundle of exports (tags)
our %EXPORT_TAGS = ( all => [qw/
        rt_user_login
        rt_user_del
        rt_user_toggleadmin
        rt_user_subscribe
        rt_user_changepasswd
        rt_user_add
        rt_user_home
        /] ); 

sub rt_user_login {
    my ($session, $param, $request) = @_;
    my $res;

    # Check if user is already logged
    if ( exists $$session{login} && length $$session{login} > 0 ) {
        $$res{deferred}{errmsg} = q{Vous êtes déjà connecté.};
        $$res{route} = '/';
        return $res;
    }

    # Check user login and password
    unless ( exists $$param{login} 
        && exists $$param{password} 
        && length $$param{login} > 0
        && length $$param{password} > 0 ) {
        $$res{deferred}{errmsg} = q{Vous n'avez pas renseigné tous les paramètres.};
        $$res{route} = '/';
        return $res;
    }

    eval {
        my $app = app->new(get_cfg());
        my $pass = encrypt($$param{password});
        my $user = $app->auth($$param{login}, $pass);

        unless( $user ) {
            $$res{deferred}{errmsg} = 
            q{Impossible de se connecter (login ou mot de passe incorrect).};
            $$res{route} = '/';
            return $res;
        }

        $$res{addsession}{login}  = $$param{login};
        $$res{addsession}{passwd} = $pass;
        # TODO adds a freeze feature, not used for now
        # $$res{addsession}{user}     = freeze( $user );

        if( $$user{admin} ) {
            $$res{route} = '/admin';
        }
        else {
            $$res{route} = '/user/home';
        }

        $app->disconnect();
    };

    if( $@ ) {
        $$res{deferred}{errmsg} = q{Impossible de se connecter ! };
        $$res{sessiondestroy} = 1;
        $$res{route} = '/';
    }

    $res
}

sub rt_user_del {
    my ($session, $param, $request) = @_;
    my $res;

    unless ( $$param{user} ) {
        $$res{deferred}{errmsg} = q{Le nom d'utilisateur n'est pas renseigné.};
        return $res;
    }

    eval {
        my $app = app->new(get_cfg());

        my $user = $app->auth($$session{login}, $$session{passwd});

        if ( $user && $$user{admin} || $$session{login} eq $$param{user} ) {
            $app->delete_user($$param{user});
        }
        $app->disconnect();
    };

    if ( $@ ) {
        $$res{deferred}{errmsg} = 
        "L'utilisateur $$res{user} n'a pas pu être supprimé. $@";
    }

    if( $$request{referer} ) {
        $$res{route} = $$request{referer};
    }
    else {
        $$res{route} = '/';
    }

    $res
}

sub rt_user_toggleadmin {
    my ($session, $param, $request) = @_;
    my $res;

    unless( $$param{user} ) {
        $$res{deferred}{errmsg} = q{L'utilisateur n'est pas défini.};
        $$res{route} = $$request{referer};
        return $res;
    }

    eval {
        my $app = app->new(get_cfg());

        my $user = $app->auth($$session{login}, $$session{passwd});

        unless ( $user && $$user{admin} ) {
            $$res{deferred}{errmsg} = q{Vous n'êtes pas administrateur.};
            return $res;
        }

        $app->toggle_admin($$param{user});
        $app->disconnect();
    };

    if( $$request{referer} =~ '/admin' ) {
        $$res{route} = $$request{referer};
    }
    else {
        $$res{route} = '/';
    }

    $res
}

sub rt_user_subscribe {
    my ($session, $param, $request) = @_;
    my $res;

    if( $$session{login} ) {
        $$res{route} = '/user/home';
    }
    else {
        $$res{template} = 'subscribe';
    }

    $res
}

sub rt_user_changepasswd {
    my ($session, $param, $request) = @_;
    my $res;

    unless ( $$session{login} && $$param{password} ) {
        $$res{deferred}{errmsg} = q{Identifiant ou mot de passe non renseigné.};
        $$res{route} = '/user/home';
        return $res;
    }

    eval {
        my $pass = encrypt($$param{password});
        my $app = app->new(get_cfg());

        $app->update_passwd($$session{login}, $pass);
        $app->disconnect();

        $$res{deferred}{succmsg} = q{Changement de mot de passe effectué !};
        $$res{addsession}{passwd} = $pass;
        $$res{route} = '/user/home';
    };

    if($@) {
        $$res{deferred}{errmsg} = q{Changement de mot de passe impossible !.};
        $$res{route} = '/user/subscribe';
        return $res;
    }

    $res
}

sub rt_user_add {
    my ($session, $param, $request) = @_;
    my $res;

    unless ( $$param{login} && $$param{password} && $$param{password2} ) {
        $$res{deferred}{errmsg} = q{Identifiant ou mot de passe non renseigné.};
        $$res{route} = '/user/subscribe';
        return $res;
    }

    unless ( $$param{password} eq $$param{password2} ) {
        $$res{deferred}{errmsg} = q{Les mots de passes ne sont pas identiques.};
        $$res{route} = '/user/subscribe';
        return $res;
    }


    eval {
        my $pass = encrypt($$param{password});

        my $app = app->new(get_cfg());

        $app->register_user($$param{login}, $pass);
        $app->disconnect();

        $$res{addsession}{login} = $$param{login};
        $$res{addsession}{passwd} = $pass;
        $$res{route} = '/user/home';
    };

    if($@) {
        $$res{deferred}{errmsg} = q{Ce pseudo est déjà pris.};
        $$res{route} = '/user/subscribe';
        return $res;
    }

    $res
}

sub rt_user_home {
    my ($session, $param, $request) = @_;
    my $res;

    $$res{template} = 'home';

    eval {
        my $app = app->new(get_cfg());

        my $user = $app->auth($$session{login}, $$session{passwd});

        unless( $user ) {
            $$res{deferred}{errmsg} = q{Problème de connexion à votre compte.};
            $$res{sessiondestroy} = 1;
            $$res{route} = '/';
            return $res;
        }

        my $domains = $app->get_domains($$session{login});

        my $dn = $$session{domainName};

        #$$res{delsession}{domainName};

        $$res{params} = {
            login               => $$session{login}
            , admin             => $$user{admin}
            , domains           => $domains
            , provideddomains   => $$app{tld}
            , domainName        => $dn  
        };

        $app->disconnect();
    };

    if( $@ ) {
        $$res{sessiondestroy} = 1;
        $$res{deferred}{errmsg} = q{Problème d'authentification.} . $@;
        $$res{route} = '/';
    }

    $res
}

1;
