export-env {
    $env.nlog_level = 2
    $env.nlog_file = ''
}

def parse_msg [args] {
    let time = date now | format date '%Y-%m-%dT%H:%M:%S'
    let s = $args
        | reduce -f {tag: {}, txt:[]} {|x, acc|
            if ($x | describe -d).type == 'record' {
                $acc | update tag ($acc.tag | merge $x)
            } else {
                $acc | update txt ($acc.txt | append $x)
            }
        }
    {time: $time, txt: $s.txt, tag: $s.tag }
}

export def --wrapped ll [lv ...args] {
    if $lv < $env.nlog_level {
        return
    }
    let ty = ['TRC' 'DBG' 'INF' 'WRN' 'ERR' 'CRT']
    let msg = parse_msg $args
    if ($env.nlog_file? | is-empty) {
        let c = ['navy' 'teal' 'xgreen' 'xpurplea' 'olive' 'maroon']
        let gray = ansi light_gray
        let dark = ansi grey39
        let l = $"(ansi dark_gray)($ty | get $lv)"
        let t = $"(ansi ($c | get $lv))($msg.time)"
        let g = $msg.tag
        | transpose k v
        | each {|y| $"($dark)($y.k)=($gray)($y.v)"}
        | str join ' '
        | do { if ($in | is-empty) {''} else {$in} }
        let m = $"($gray)($msg.txt | str join ' ')"
        let r = [$t $l $g $m]
        | where { $in | is-not-empty }
        | str join $'($dark)│'
        print -e $r
    } else {
        [
            ''
            $'#($ty | get $lv)# ($msg.txt | str join " ")'
            ...($msg.tag | transpose k v | each {|y| $"($y.k)=($y.v | to nuon)"})
            ''
        ]
        | str join (char newline)
        | save -af ~/.cache/nonstdout
    }
}

export def --wrapped trace    [...args] { ll 0 ...$args }
export def --wrapped debug    [...args] { ll 1 ...$args }
export def --wrapped info     [...args] { ll 2 ...$args }
export def --wrapped warning  [...args] { ll 3 ...$args }
export def --wrapped error    [...args] { ll 4 ...$args }
export def --wrapped critical [...args] { ll 5 ...$args }

export alias l0 = log.ll 0
export alias l1 = log.ll 1
export alias l2 = log.ll 2
export alias l3 = log.ll 3
export alias l4 = log.ll 4
export alias l5 = log.ll 5
