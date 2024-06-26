'crawl dbfile'
| comma val null 'status.db'

'crawl db init'
| comma fun {|a,s|
   '
    create table titles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title text not null unique,
        timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    create table pages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title_id integer references titles(id),
        url text not null,
        status text,
        timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        unique(title_id, url)
    );
    create table elements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        page_id integer references pages(id),
        uri text not null,
        payload text,
        status text,
        timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        unique(page_id, uri)
    );
   '
   | sqlite3 $s.crawl.dbfile
} {
    d: {|a,s| $'init `($env.PWD)/($s.crawl.dbfile)`' }
}

def list-titles [s] {
    'select id, title from titles;'
    | sqlite3 -json $s.crawl.dbfile
    | from json
    | rename value description
}

'crawl db reset'
| comma fun {|a,s|
    let tid = $a.0
    $"
    update pages set status = null where title_id = ($tid);
    update elements set status = null where page_id in \(select id from pages where title_id = ($tid)\);
    "
    | sqlite3 $s.crawl.dbfile
} {
    cmp: {|a,s|
        match ($a | length) {
            1 => { list-titles $s }
        }
    }
}

'crawl db list'
| comma fun {|a,s|
    let obj = $a.0
    let tid = $a.1
    match $obj {
        pages => $"select title, title_id as tid, url, p.id, status, p.timestamp from pages as p join titles as t on p.title_id = t.id where title_id = ($tid);"
        elements => $"select title_id as tid, page_id as pid, e.uri, e.status, e.timestamp  from elements as e join pages as p on e.page_id = p.id where p.title_id = ($tid);"
    }
    | sqlite3 -json $s.crawl.dbfile
    | from json
} {
    cmp: {|a,s|
        match ($a | length) {
            1 => [pages elements]
            2 => { list-titles $s }
        }
    }
}

def quote [...s] {
    let s = $s | str join '' | str replace -a "'" "''"
    $"'($s)'"
}

def handler-page [
    s
    url
    --selector (-s): record
    --handler (-s): record
] {
    let url = $url | str trim
    lg level 4 {url: $url} start

    let getter = $handler.getter? | default {|u| http get $u}
    let html = do $getter $url

    let links = if ($selector.nav? | is-not-empty) {
        $html
        | query web -q $selector.nav.q -m
        | do -i $selector.nav.e $in
        | filter { $in | is-not-empty }
    }

    let title = $html
    | query web -q $selector.title.q
    let title = if ($selector.title.e? | is-empty) { $title } else { do $selector.title.e $title }

    lg level 4 get { title: $title }

    do $handler.title $title

    $"insert into titles \(title\) values \((quote $title)\) on conflict \(title\) do nothing;"
    | sqlite3 $s.crawl.dbfile

    let tid = $"select id from titles where title = (quote $title)"
    | sqlite3 $s.crawl.dbfile

    $"insert into pages \(title_id, url\) values \(($tid), (quote $url)\) on conflict \(title_id, url\) do nothing;"
    | sqlite3 $s.crawl.dbfile

    let pid = $"select id from pages where title_id = ($tid) and url = (quote $url)"
    | sqlite3 $s.crawl.dbfile
    lg level 4 query { title: $title, tid: $tid, page: $url, pid: $pid }

    for i in $links {
        $"insert into pages \(title_id, url\) values \(($tid), (quote $i)\) on conflict \(title_id, url\) do nothing;"
        | sqlite3 $s.crawl.dbfile
    }

    lg level 4 get elements
    let el = $html
    | query web -q $selector.elm.q -m
    for i in $el {
        let uri = do $selector.elm.e $i
        $"insert into elements \(page_id, uri, payload\) values \(($pid), (quote $uri), (quote $i)\) on conflict  do nothing;
        update elements set payload = (quote $i) where page_id = ($pid) and uri = (quote $uri)
        "
        | sqlite3 $s.crawl.dbfile
    }

    let ps = $"select uri, payload from elements where page_id = ($pid) and status is null;"
    | sqlite3 -json $s.crawl.dbfile
    | from json
    for i in $ps {
        lg level 3 extract { title: $title, page: $url, element: $i.uri? }
        let r = do $handler.elm $title $url $i $handler
        if ($r | is-not-empty) {
            $"update elements set status = (quote $r) where page_id = ($pid) and uri = (quote $i.uri?);"
            | sqlite3 $s.crawl.dbfile
        } else {
            lg level 5 {title: $title, page: $url, element: $i.uri? } err
        }
    }

    $"update pages set status = 1 where title_id = ($tid) and url = (quote $url)"
    | sqlite3 $s.crawl.dbfile

    let ns = $"select url from pages where title_id = ($tid) and status is null;"
    | sqlite3 $s.crawl.dbfile
    | lines

    for x in $ns {
        handler-page $s $x --selector $selector --handler $handler
    }
}

'crawl fetch'
| comma fun {|a,s,_|
    let sl = $s.crawl.selector | get $a.0
    let hl = $s.crawl.handler | get $a.0
    let url = $a.1
    handler-page $s $url --selector $sl --handler $hl
} {
    d: '<template> <url>'
    cmp: {|a,s|
        match ($a | length) {
            1 => { $s.crawl.selector | columns }
        }
    }
}

'crawl selector foo'
| comma val null {
    nav: {
        q: '.pgntn-page-pagination-block'
        e: {|e| $e | first | query web -q 'a' -a 'href'}
    }
    title: {
        q: 'header > h1'
        e: {|e| $e | first | first | str trim }
    }
    elm: {
        q: 'div.bialty-container > p > a'
        e: {|e| $e | query web -q 'a' -a 'href' | first }
    }
}

'crawl handler foo'
| comma val null {
    title: {|t| mkdir $t }
    elm: {|t,p,e,h|
        if ($e.uri? | is-empty) {
            return
        }
        lg level 5 'elm handler' {t: $t, p: $p, e: $e.uri?}
        let n = $e.uri | path parse | $"($in.stem).($in.extension)"
        let t = [$t $n] | path join
        lg level 3 save { file: $t }
        let cfg = if ($h.wgetrc? | is-empty) {[]} else {[ $"--config=($h.wgetrc)"]}
        wget ...$cfg -c $e.uri -O $t --content-on-error
        return 'succ'
    }
    wgetrc: ''
}


'crawl selector bar'
| comma val null {
    nav: {
        q: '.paginate-container > div:nth-child(1) > div:nth-child(1)'
        e: {|e| $e | first | query web -q 'a' -a 'href'}
    }
    title: {
        q: 'strong.mr-2 > a:nth-child(1)'
        e: {|e| $e | first | first }
    }
    elm: {
        q: '#partial-actions-workflow-runs .d-table-cell'
        e: {|e| $e | do -i { query web -q ' a.flex-items-center' -a 'href' | first } }
    }
}

'crawl handler bar'
| comma val null {
    #getter: {|u| open gha.html }
    title: {|t| mkdir $t }
    elm: {|t,p,e|
        if ($e.uri? | is-empty) {
            return
        }
        lg level 5 'elm handler' {t: $t, p: $p, e: $e.uri?}
        let n = $e.uri | path parse | $"($in.stem).html"
        let t = [$t $n] | path join
        lg level 3 save { file: $n }
        $e.payload | save -f $t
        return 'succ'
    }
}

