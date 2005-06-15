# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}

no warnings qw(redefine);

package RT::User;

sub CanonicalizeEmailAddress {
    my $self = shift;
    my $address = shift;

    if ($RT::CanonicalizeEmailAddressMatch && $RT::CanonicalizeEmailAddressReplace ) {
        $address =~ s/$RT::CanonicalizeEmailAddressMatch/$RT::CanonicalizeEmailAddressReplace/gi;
    }

    # get the user whose email address this is
    my $canonical_user = RT::User->new($RT::SystemUser);
    $canonical_user->LoadByCol( "EmailAddress", $address );

    # if we got a user, check for a parent
    if ($canonical_user->Id) {
        my ($effective_id) = $canonical_user->Attributes->Named("EffectiveId");
        if (defined $effective_id) {
            $canonical_user->LoadById($effective_id->Content);
            # is there another parent user above this one?
            return $canonical_user->CanonicalizeEmailAddress($canonical_user->EmailAddress)
              if ($canonical_user->Id);
        }
    }
    # we've hit the primary user
    return $address;
}

sub MergeInto {
    my $self = shift;
    my $user = shift;

    # Load the user objects we were called with
    my $merge;
    if (ref $user) {
        $merge = RT::User->new($RT::SystemUser);
        $merge->Load($user->Id);
    } else {
        $merge = RT::User->new($RT::SystemUser);
        $merge->Load($user);
    }

    return (0, "Could not load @{[$merge->Name]}") unless $merge->Id;

    # Get copies of the canonicalized users
    my $email;
    if (defined $merge->Attributes->Named('EffectiveId')) {
        $email = $merge->CanonicalizeEmailAddress($merge->EmailAddress);
        $merge->LoadByEmail($email);
    }
    return (0, "Could not load user to be merged") unless $merge->Id;

    my $canonical_self = RT::User->new($RT::SystemUser);
    $canonical_self->Load($self->Id);
    if (defined $canonical_self->Attributes->Named('EffectiveId')) {
        $email = $canonical_self->CanonicalizeEmailAddress($canonical_self->EmailAddress);
        $canonical_self->LoadByEmail($email);
    }
    return (0, "Could not load user to merge into") unless $canonical_self->Id;

    # No merging into yourself!
    return (0, "Could not merge @{[$merge->Name]} into itself")
           if $merge->Id == $canonical_self->Id;

    # No merging if the user you're merging into was merged into you
    # (ie. you're the primary address for this user)
    my ($new) = $merge->Attributes->Named("EffectiveId");
    return (0, "User @{[$canonical_self->Name]} has already been merged")
           if defined $new and $new->Content == $canonical_self->Id;

    # do the merge
    $canonical_self->SetAttribute(Name => "EffectiveId",
                        Description => "Primary ID of this email address",
                        Content => $merge->Id,
                       );

    $canonical_self->SetComments(join "\n", grep {/\S/} (
                                               $canonical_self->Comments,
                                               "Merged into ".$merge->EmailAddress." (".$merge->id.")",
                                              )
                      );
    $merge->SetComments(join "\n", grep {/\S/} (
                                                $merge->Comments,
                                                $canonical_self->EmailAddress." (".$canonical_self->Id.") merged into this user",
                                               )
                       );
}

sub UnMerge {
    my $self = shift;
  
    my ($current) = $self->Attributes->Named("EffectiveId");
    return (0, "No parent user") unless $current;
    
    my $merge = RT::User->new($RT::SystemUser);
    $merge->Load($current->Content);

    $current->Delete;
    $self->SetComments(join "\n", grep {/\S/} (
                                               $self->Comments,
                                               "Unmerged from ".$merge->EmailAddress." (".$merge->Id.")",
                                              )
                      );
    
    $merge->SetComments(join "\n", grep {/\S/} (
                                                $merge->Comments,
                                                $self->EmailAddress." (".$self->Id.") unmerged from this user",
                                              )
                      );

    return ($merge->Id, "Unmerged from @{[$merge->EmailAddress]}");
}

1;
