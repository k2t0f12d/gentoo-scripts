#!/usr/bin/env bash

# FILE: compare_versions.sh
#
# Compare semantic version strings

# USAGE
#
# Source this script to load the function, its test harness.
# Testing will be triggered with environment variable ENABLE_TESTS set.
#
# Invoke compare_version with two arguments. Each argument must be a
# string that starts with a numeral, and thereafter only contains numerals
# and full stops.
#
# Function runs silently. To determine the result check the BASH special
# variable `$?` for the return, as follows:
#
# 0   - Arguments are equal
# 1   - Argument $1 is greater than $2
# 2   - Argument $1 is less than $2
# 255 - One or both of the arguments is not a number
#
# EXAMPLE
#
# . /path/to/compare_versions.sh
# compare_versions $VER1 $VER2
# if [[ $? -eq 0 ]]; then
#         echo "Versions are the same"
# elif [[ $? -eq 1 ]]; then
#         echo "VER1 is greater than VER2"
# elif [[ $? -eq 2 ]]; then
#         echo "VER1 is less than VER2"
# elif [[ $? -eq 255]]; then
#         echo "Invalid comparator: arguments must be semantic versions, Eg., 1.0.0"
# else
#         echo "This cannot happen"
# fi

# NOTE: uncomment the following to enable debugging output from BASH
#set -x

compare_versions() {
        # Only accept numerical inputs
        [[ $1 =~ ^[0-9]?[0-9.]+$ ]] || return 255
        [[ $2 =~ ^[0-9]?[0-9.]+$ ]] || return 255

        if [[ $1 == $2 ]]
        then
                return 0
        fi

        local IFS=.
        if [[ $ZSH_VERSION ]]; then
                local i ver1=($=1) ver2=($=2)
        else
                local i ver1=($1) ver2=($2)
        fi

        # Oh-my-ZSH >.<
        INDEX=0
        [[ $ZSH_VERSION ]] && INDEX=1  # ZSH uses 1 based arrays

        # Compare version string lengths; if ver2 has
        # more version places, fill the missing places
        # in ver1 with zeros.
        for ((i=${#ver1[@]}; i<(${#ver2[@]}+$INDEX); i++)); do
                ver1=( ${ver1[@]} 0 )
        done

        for ((i=$INDEX; i<(${#ver1[@]}+$INDEX); i++)); do

                # If ver1 has more version places than ver2
                # fill the extra places in ver2 with zero.
                if [[ -z ${ver2[$i]} ]]; then
                        ver2=( ${ver2[@]} 0 )
                fi

                # Case greater than returns 1
                if ((10#${ver1[i]} > 10#${ver2[i]})); then
                        return 1
                fi

                # Case less than returns 2
                if ((10#${ver1[i]} < 10#${ver2[i]})); then
                        return 2
                fi
        done

        return 0
}

if [[ $ENABLE_TESTS ]]; then
        [[ $ZSH_VERSION ]] && setopt sh_word_split
        test_compare_version() {
                compare_versions $1 $2

                case $? in
                0) operator='=';;
                1) operator='>';;
                2) operator='<';;
                255) operator='NaN';;
                esac

                if [[ $operator != $3 ]] || [[ $operator == 'NaN' ]]; then
                        echo "FAIL: testing for '$3' but received '$operator' while comparing '$1' and '$2'"
                        return 1
                else
                        echo "PASS: tested '$1' and '$2' for '$3'"
                fi
        }

        echo 'Loading `compare_versions()`...'
        echo 'Running the test suite...'
        echo '>>>>>>>>>> These tests should pass'
        while read -r test; do
                test_compare_version $test
        done <<EOF
1            1            =
2.1          2.2          <
3.0.4.10     3.0.4.2      >
4.08         4.08.01      <
3.2.1.9.8144 3.2          >
3.2          3.2.1.9.8144 <
1.2          2.1          <
2.1          1.2          >
5.6.7        5.6.7        =
1.01.1       1.1.1        =
1.1.1        1.01.1       =
1            1.0          =
1.0          1            =
1.0.2.0      1.0.2        =
1..0         1.0          =
1.0          1..0         =
EOF

        echo '>>>>>>>>>> These tests should fail'
        test_compare_version 1 1 '>'
        test_compare_version la la '='
        [[ $ZSH_VERSION ]] && unsetopt sh_word_split
fi

echo 'Finished loading `compare_versions()` :)'
