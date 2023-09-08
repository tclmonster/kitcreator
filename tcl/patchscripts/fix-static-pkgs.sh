#! /usr/bin/env bash

for file in pkgs/tdbcodbc*/generic/tdbcodbc.c pkgs/tdbcmysql*/generic/tdbcmysql.c; do
	if [ ! -f "${file}" ]; then
		continue
	fi

	sed 's@const.*LiteralValues@static &@' "${file}" > "${file}.new"
	cat "${file}.new" > "${file}"
	rm -f "${file}.new"
done
