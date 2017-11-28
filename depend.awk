#!/usr/bin/awk -f

# Terminology:
# Set: an awk associative array where only the keys are used, values are empty strings
# Map: an awk associative array
#
# Commandline params (set with -v)
# - install: comma separated list of packages to be installed (MANDATORY)
# - installed: comma separated list of packages already installed (OPTIONAL)
# - mask: comma separated list of packages that shouldn't be installed (OPTIONAL)

# Globals:
# - maskSet: cmdline arg as Set
# - installSet: cmdline arg as Set
# - installedSet: cmdline arg as Set
# - dependencies: Map of package dependencies, key: package name, value: comma separated list of dependencies
# - filename: Map of package filenames, key: package name, value: filename
# - provides: Map of package provided virtuals, key: package name, value: comma separated list of provided virt-packages
# - virtuals: Map of virtuals, key: virt-package name, value: comma-space separated list of real packages providing the virtual in the key


# Some awk WTF's I always forget
# - there are local variables at block scope, only function scope; they must be present in the argument list
# - arrays passed by reference, other types by value (passing semantics determined runtime)


# Resouces
# - Debian package versioning
#   https://www.debian.org/doc/debian-policy/#version
#   https://serverfault.com/questions/604541/debian-packages-version-convention
#   https://www.debian.org/doc/manuals/maint-guide/first.en.html#namever
#   https://readme.phys.ethz.ch/documentation/debian_version_numbers/


# todo:
# - create a parsepackagelist fun for Dep/Provides
# - [low] add support for suggests/recommends
# - [low] add support for versioning
# - print download/installed size

# limitations:
# - install only
# - does not run scripts in .deb, only unpacks them
# - does not track package version constraints
# - does not consider alternatives in dependency list


#####################
# Utility functions #
#####################


# send debug message to stderr (conditional)
function log_debug(msg) {
#    if (debug == 1) {
    if (1) {
        print "DBG " msg > "/dev/stderr"
    }
}

# send error msg to stderr
function log_error(msg) {
        print "ERR " msg > "/dev/stderr"
}

# join a Set into a single comma separated string
function joinSet(set,    i,ret,sep) {
    ret = sep = ""

    for (i in set) {
        ret = ret sep i
        sep = ","
    }
    return ret
}

# split a comma separated list into a Set, args:
#   list(in): comma separated list
#   ret(out): Set containing the list items
function splitSet(list,ret,    i,tmp) {
    split(list, tmp, ",")
    delete ret

    for (i in tmp) {
        ret[ tmp[i] ]
    }
}

# append an item to a string with comma-space separator
function appendWithSep(list, item) {
    if (length(list) == 0) {
        return item
    } else {
        return list ", " item
    }
}

function walk(package,requiredby,    i,tmp) {
    # skip masked packages (normal or virtual)
    if (package in maskSet) {
        return
    }

    # skip already installed packages
    if (package in installedSet) {
        return
    }

    # return if package is already in toBeInstalled (breaks circular dependencies)
    if (package in toBeInstalled) {
        return
    }

    if ( !(package in dependencies) ) {

        if ( package in virtuals ) {
            log_error( "Ambiguous dependency tree! Required virtual package " package ", provided by: " virtuals[package] )
            log_error( "Please explicitly select a provider by adding it to the install list" )
            exit(1)
        } else {
            log_error( "Unknown package: " package )
            exit(1)
        }
    }

    # add current package to installSet
    log_debug("Selecting " package " (required by: " requiredby ")" )
    toBeInstalled[package]

    # recurse for all dependencies
    splitSet( dependencies[package], tmp )
    for (i in tmp) {
        walk(i, package)
    }
}



# right (last) index of needle in haystack (nice and recursive)
# returns a position indexed from 1, or a zero if not found
function rindex(haystack, needle, pos,     i) {
    if (pos == "") {
        pos = 0
    }

    i = index(haystack, needle);
    if (i == 0) {
        return pos;
    }

    return rindex(substr(haystack, i+1), needle, pos+i);
}


# Create ordinal table for debian version string lexical sort rules
# https://www.gnu.org/software/gawk/manual/html_node/Ordinal-Functions.html
function initOrdinalTable(    i) {
    # A-Z
    for (i=65; i<=90; i++) {
        t = sprintf("%c", i)
        ordTable[t] = i;
    }

    # a-z
    for (i=97; i<=122; i++) {
        t = sprintf("%c", i)
        ordTable[t] = i;
    }

    # tilde is the lowest of all
    ordTable["~"] = 0;

    # full stop, plus, hypen are higher than alpha
    ordTable["."] = 46+128;
    ordTable["+"] = 43+128;
    ordTable["-"] = 45+128;
}


function ord(c) {
    if (! (c in ordTable)) {
        log_error("Char " c " not found in ordinal table!");
        exit(1)
    }

    #print "Ord " c " " ordTable[c]

    return ordTable[c]
}

function modifiedLexicalSort(str1, str2,     i, len, c1, c2) {
    # get the shorter length
    len = length(str1)
    if (length(str2) < len) {
        len = length(str2)
    }

    # compare char by char
    for (i=1; i<=len; i++) {
        c1 = ord(substr(str1, i, 1));
        c2 = ord(substr(str2, i, 1));

        if (c1 > c2) {
            return 1
        }

        if (c1 < c2) {
            return -1
        }
    }

    # return equal if strings have the same length
    if (length(str1) == length(str2)) {
        return 0
    }

    # get the char past the common length
    if (length(str1) > length(str2)) {
        c1 = substr(str1, len+1, 1)
        #print "past1: " c1
        return (c1 == "~") ? -1 : 1;
    } else {
        c2 = substr(str2, len+1, 1)
        #print "past2: " c2
        return (c2 == "~") ? 1 : -1;
    }
}


# Split Debian version string into epoch, upstream, debian version tuple
function splitVer(verStr, ret,     i) {
    # find epoch separator
    i = index(verStr, ":")
    if (i == 0) {
        # no epoch defined, defaulting to zero
        ret["epoch"] = "0"
    } else {
        ret["epoch"] = substr(verStr, 0, i)
        verStr = substr(verStr, i+1);
    }

    # find upstream<->debian separator
    i = rindex(verStr, "-");
    if (i==0) {
        ret["upstream"] = verStr
        ret["debian"] = "0"
    } else {
        ret["upstream"] = substr(verStr, 0, i)
        ret["debian"] = substr(verStr, i+1)
    }

    #print "Epoch: " ret["epoch"]
    #print "Upstream: " ret["upstream"]
    #print "Debian: " ret["debian"]
}

function compareSectionAlpha(ver1, ver2,    sub1, sub2, r) {
    if (length(ver1)==0 && length(ver2)==0) {
        return 0
    }

    match(ver1, /^[a-zA-Z+~\.]+/)
    sub1 = substr(ver1, 1, RLENGTH)
    ver1 = substr(ver1, RLENGTH+1)
    #print("amatch1 " sub1 " " ver1)

    match(ver2, /^[a-zA-Z+~\.]+/)
    sub2 = substr(ver2, 1, RLENGTH)
    ver2 = substr(ver2, RLENGTH+1)
    #print("amatch2 " sub2 " " ver2)

    r = modifiedLexicalSort(sub1, sub2)
    if (r != 0) {
        return r
    }

    return compareSectionNum(ver1, ver2)
}


function compareSectionNum(ver1, ver2,    num1, num2) {
    if (length(ver1)==0 && length(ver2)==0) {
        return 0
    }

    if (match(ver1, /^[0-9]+/) == 0) {
        log_error("Numeric block expected in: " ver1)
        exit(1)
    }
    # add zero to force conversion to number type
    num1 = substr(ver1, 1, RLENGTH) + 0
    ver1 = substr(ver1, RLENGTH+1)
    #print("nmatch1 " num1 " " ver1)

    if (match(ver2, /^[0-9]+/) == 0) {
        log_error("Numeric block expected in: " ver2)
        exit(1)
    }
    # add zero to force conversion to number type
    num2 = substr(ver2, 1, RLENGTH) + 0
    ver2 = substr(ver2, RLENGTH+1)
    #print("nmatch2 " num2 " " ver2)

    if ( num1 > num2 ) {
        return 1;
    }
    if ( num1 < num2 ) {
        return -1;
    }

    return compareSectionAlpha(ver1, ver2)
}


function compareVer(ver1, ver2,    verArr1, verArr2, r) {
    splitVer(ver1, verArr1);
    splitVer(ver2, verArr2);

    if (verArr1["epoch"] > verArr2["epoch"]) {
        return 1;
    }

    if (verArr1["epoch"] < verArr2["epoch"]) {
        return -1;
    }

    r = compareSectionNum(verArr1["upstream"], verArr2["upstream"]);
    if (r != 0) {
        return r;
    }

    return compareSectionNum(verArr1["debian"], verArr2["debian"]);
}

function testVerCompare() {

    # 0.0 < 0.5 < 0.10 < 0.99 < 1 < 1.0~rc1 < 1.0 < 1.0+b1 < 1.0+nmu1 < 1.1 < 2.0
    print compareVer("0.0", "0.5") == -1
    print compareVer("0.5", "0.10") == -1
    print compareVer("0.10", "0.99") == -1
    print compareVer("0.99", "1") == -1
    print compareVer("1", "1.0~rc1") == -1
    print compareVer("1.0~rc1", "1.0") == -1
    print compareVer("1.0", "1.0+b1") == -1
    print compareVer("1.0+b1", "1.0+nmu1") == -1
    print compareVer("1.0+nmu1", "1.1") == -1
    print compareVer("1.1", "1.2") == -1

    # the same backwards
    print compareVer("0.5", "0.0") == 1
    print compareVer("0.10", "0.5") == 1
    print compareVer("0.99", "0.10") == 1
    print compareVer("1", "0.99") == 1
    print compareVer("1.0~rc1", "0.99") == 1
    print compareVer("1.0", "1.0~rc1") == 1
    print compareVer("1.0+b1", "1.0") == 1
    print compareVer("1.0+nmu1", "1.0+b1") == 1
    print compareVer("1.1", "1.0+nmu1") == 1
    print compareVer("1.2", "1.1") == 1

    # 1~~ < 1~~a < 1~ < 1 < 1a
    print compareVer("1~~", "1~~a") == -1
    print compareVer("1~~a", "1~") == -1
    print compareVer("1~", "1") == -1
    print compareVer("1", "1a") == -1

    # the same backwards
    print compareVer("1~~a", "1~~") == 1
    print compareVer("1~", "1~~a") == 1
    print compareVer("1", "1~") == 1
    print compareVer("1a", "1") == 1

    # 0:1.0-1 < 1:1.0-1 < 1:1.0-2 < 1:1.1-1
    print compareVer("0:1.0-1", "1:1.0-1") == -1
    print compareVer("1:1.0-1", "1:1.0-2") == -1
    print compareVer("1:1.0-2", "1:1.1-1") == -1

    # the same backwards
    print compareVer("1:1.0-1", "0:1.0-1") == 1
    print compareVer("1:1.0-2", "1:1.0-1") == 1
    print compareVer("1:1.1-1", "1:1.0-2") == 1

    exit(0)
}


###################
# Pre-parse setup #
###################


BEGIN {
    FS = ": "
    initOrdinalTable()
}


##########################
# Package parse matchers #
##########################


# match on a package name
/^Package:/ {
    packageName = $2
}


# match on filename tag
/^Filename:/ {
    packageFile = $2
}


# match on a dependency tags
/^Depends:/ || /^Pre-Depends:/  {
    # Split colon separated dependency list
    split($2, deps, ", ");

    for (i in deps) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(deps[i], depClean, " ")

        packageDepSet[ depClean[1] ]
    }
}

# match on provided virtual packages
/^Provides:/ {
    # Split colon separated virtual package list
    split($2, vpkg, ", ");


    for (i in vpkg) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(vpkg[i], vpkgClean, " ")

        packageProvides[ vpkgClean[1] ]
    }
}

# match on a package separator newline
/^$/ {
    if (packageName != "") {
        dependencies[packageName] = joinSet(packageDepSet)
        filename[packageName] = packageFile
        provides[packageName] = joinSet(packageProvides)

        # create a virtual package provider map for user messages
        for (i in packageProvides) {
            virtuals[i] = appendWithSep( virtuals[i], packageName )
        }
    }

    # blank state
    delete packageDepSet
    delete packageProvides
    # mawk doesn't support deleting ordinary variables
    #delete packageName
    #delete packageFile
    
}

#########################
# Post parse processing #
#########################


END {

    testVerCompare()

    # quit if install argument is not present
    if (install == "") {
        log_error( "Error: install list is missing" )
        exit(1)
    }


    ######
    # process package mask if present (no validity check on items)
    splitSet(mask, maskSet)

    ######
    # process installed packages if present (no validity check on items)
    splitSet(installed, installedSet)
    
    # mark all virtual packages as installed if an already installed package provides them
    for (i in installedSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            log_debug( "Adding virtual package to installedSet: " j " (provided by installed: " i ")" )
            installedSet[j]
        }
    }


    ######
    # process install request
    splitSet(install, installSet)
    
    # add virtual packages provided by the installSet to the maskSet to
    # avoid dependency tracking on them (no validity check on items)
    # eg: install=bash,gawk (bash depends on awk, which is provided by gawk)
    # NOTE: the item could be added to installedSet instead of maskSet, or a new virtInstallSet
    # The point is to break the processing of this virtual dependency in walk()
    for (i in installSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            log_debug( "Adding virtual package to maskSet: " j " (provided by install req: " i ")" )
            maskSet[j]
        }
    }
    
    # walk dependecy tree (die on invalid items)
    for (i in installSet) {
        walk(i, "<user>")
    }

    OFS=","
    for (i in toBeInstalled) {
        print i, filename[i]
    }
}
