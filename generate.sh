#!/bin/bash

USER=${MANTA_USER:-cinsk}
DOCUMENT_ROOT=${DOCUMENT_ROOT:-www}

if [ -n "$MANTA_ENDPOINT" ]; then
    ENDPOINT=$(echo "$MANTA_ENDPOINT" | sed -e 's#^https://\|^http://##' -e 's#:.*##' -e 's#/.*##')
else
    ENDPOINT=us-east.manta.joyent.com
fi

OUTPUT=/etc/varnish/default.vcl

cat >$OUTPUT <<EOF
vcl 4.0;

import directors;

EOF

if which dig >&/dev/null; then
    count=1
    while read address; do
        cat >>$OUTPUT <<EOF
backend server$count {
  .host = "$address";
  .port = "80";
  .probe = {
    .url = "/$USER/public/$DOCUMENT_ROOT";
    .interval = 5s;
    .timeout = 1s;
    .window = 5;
    .threshold = 3;
  }
}

EOF
        count=$((count + 1))
    done < <(dig "$ENDPOINT" a | grep -v '^;' | awk '$4 == "A" { print $5 }')

    echo "sub vcl_init {" >>$OUTPUT
    echo "  new bar = directors.round_robin();" >>$OUTPUT
    for i in $(seq $((count - 1))); do
        echo "bar.add_backend(server$i);" >>$OUTPUT
    done        
    echo "}" >>$OUTPUT

cat >>$OUTPUT <<EOF
sub vcl_recv {
  set req.url = regsub(req.url, "^/", "/$USER/public/$DOCUMENT_ROOT/");
  set req.http.host = "$ENDPOINT";

  if (req.url ~ "/$") {
    set req.url = req.url + "/index.html";
  }

  set req.backend_hint = bar.backend();
}

EOF
fi
