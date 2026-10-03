# Fingerprints you confirmed against the vendor's published ones, one per line.
set -g __verify_trusted ~/.local/share/verify/trusted-fingerprints

function verify -d "🔑 Verify a download against its PGP signature and sha256 checksum file"
    if test (count $argv) -ne 1; or not test -f $argv[1]
        echo "usage: verify <file>" >&2
        return 2
    end
    set -l missing
    for t in gpg sha256sum awk
        command -q $t; or set -a missing $t
    end
    if set -q missing[1]
        echo "missing: $missing (install: sudo apt install gnupg coreutils gawk)" >&2
        return 2
    end

    set -l dir (path dirname -- $argv[1])
    set -l name (path basename -- $argv[1])
    pushd $dir; or return 2
    __verify_run $name
    set -l rc $status
    popd
    return $rc
end

function __verify_run
    set -l name $argv[1]
    set -l sig (path filter -f -- $name.asc $name.sig $name.gpg)[1]
    set -l sums (path filter -f -- $name.DIGESTS $name.sha256 $name.sha256sum SHA256SUMS sha256sum.txt)[1]
    set -l signed 0

    if test -n "$sig"
        __verify_sig $sig $name; or return 1
        set signed 1
    end
    if test -n "$sums"
        set -l sumsig (path filter -f -- $sums.asc $sums.sig $sums.gpg $sums.sign)[1]
        if grep -q 'BEGIN PGP SIGNED MESSAGE' $sums
            __verify_sig $sums; or return 1
            set signed 1
        else if test -n "$sumsig"
            __verify_sig $sumsig $sums; or return 1
            set signed 1
        end
        # ponytail: sha256 only; other hash lines are ignored
        echo "== sha256: $sums"
        set -l line (awk -v n=$name '$1 ~ /^[0-9a-f]{64}$/ && ($2 == n || $2 == "*" n)' $sums)
        if not set -q line[1]
            echo "no sha256 for $name in $sums" >&2
            return 1
        end
        printf '%s\n' $line[1] | sha256sum -c; or return 1
    end

    if test -z "$sig$sums"
        echo "nothing to verify: no $name.asc/.sig/.gpg or checksum file next to it" >&2
        return 1
    end
    if test $signed -eq 0
        echo "WARNING: no signature, checksum proves integrity only, not authenticity" >&2
        return 1
    end
    echo "OK: $name is authentic"
end

# __verify_sig <sig> [signed-file]: pass only on a good signature from a key you trust
function __verify_sig
    set -l sig $argv[1]
    set -l issuer (gpg --list-packets $sig 2>/dev/null | string match -rg '(?:issuer fpr v4 |keyid )([0-9A-F]{16,40})')[1]
    if not gpg --list-keys $issuer >/dev/null 2>&1
        __verify_get_key $issuer; or return 1
    end

    echo "== gpg: $sig"
    set -l st (gpg --status-fd 1 --verify $argv)
    set -l valid (string match -r '^\[GNUPG:\] VALIDSIG .*' -- $st)
    if test -z "$valid"; or string match -q '*BADSIG*' -- $st
        echo "BAD SIGNATURE: $sig" >&2
        return 1
    end
    string match -qr 'TRUST_(FULLY|ULTIMATE)' -- $st; and return 0

    set -l fpr (string split ' ' -- $valid)[-1] # primary key fingerprint
    grep -qx $fpr $__verify_trusted 2>/dev/null; and return 0
    echo
    gpg --fingerprint $fpr
    echo "Good signature, but this key is not yet trusted. Compare the fingerprint above with the"
    echo "one the vendor publishes (website, docs, release notes; ideally more than one source)."
    read -P "Does it match? Trust this key for future verifies [y/N] " -l ans; or return 1
    string match -qi y -- $ans; or return 1
    mkdir -p (path dirname $__verify_trusted)
    echo $fpr >>$__verify_trusted
end

function __verify_get_key
    set -l id $argv[1]
    echo "Signing key $id is not in your keyring."
    for f in *.asc *.gpg *.key *.pub
        grep -q 'BEGIN PGP PUBLIC KEY BLOCK' $f 2>/dev/null; or continue
        gpg --show-keys --with-colons $f 2>/dev/null | string match -q "*$id*"; or continue
        read -P "Import it from ./$f? [y/N] " -l ans; or return 1
        string match -qi y -- $ans; or return 1
        gpg --import $f
        return
    end
    read -P "Fetch it from keyserver.ubuntu.com? [y/N] " -l ans; or return 1
    string match -qi y -- $ans; or return 1
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $id
end
