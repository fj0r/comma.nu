export def merge [args tbl --opt: record] {
        let c = $args | gen $tbl
        if $opt.json {
            $c | to json
        } else {
            $c
        }
}

export def gen [tbl] {
    let argv = $in
    let _ = $env.comma_index
    use resolve.nu
    let scope = resolve scope [] (resolve comma 'comma_scope') []
    use tree.nu
    let cb = {|pth, g, node, _|
        let indent = ($pth | length)
        if ($_.desc in $node) and ($node | get $_.desc | str contains '!vscode') {
            []
        } else {
            let label = $g
                | filter {|x| $x | is-not-empty }
                | str join ' | '
            let command = $pth
                | str join ' '
            let args = view source ($node | get $_.act)
                | str replace -ar $'[ \n]' ''
                | parse --regex '\{\|(.+?)\|.+\}'
            let args = if ($args| is-empty) { '' } else { $args.0.capture0 }
            let argid = if ($args | is-empty) { '' } else {
                $"_($args | str replace -ar $'[ ,\n]' '_')"
            }
            let cmp = if $_.cmp in $node { random chars -l 8 }
            {
                label: $label
                command: $command
                cmp: $cmp
                args: $args
                argid: $argid
            }
        }
    }
    let vs = $argv
    | flatten
    | tree select --strict $tbl
    | $in.node
    | reject 'end'
    | tree map $cb 'get_desc' $scope
    let nuc = "nu -c 'use comma *; source ,.nu;"
    let tasks = $vs
    | each {|x|
        let input = if ($x.cmp | is-empty) { '' } else { $" ${input:($x.cmp)}"}
        let input = if ($x.args | is-empty) { $input } else {
            $"($input) ${input:($x.argid)}"
        }
        let label = if ($x.label | is-empty) { '' } else { $" [($x.label)]" }
        {
            type: 'shell'
            label: $"($x.command)"
            command: $"($nuc) , ($x.command)($input)'"
            problemMatcher: []
        }
    }
    let inputs = $vs
    | filter {|x| $x.cmp | is-not-empty }
    | each {|x| {
        id: $x.cmp
        type: 'command'
        command: 'shellCommand.execute'
        args: { command: $"($nuc) , -c --vscode ($x.command)'" }
    } }
    let args = $vs
    | reduce -f {} {|x,a|
        if ($x.args | is-empty) { $a } else {
            if $x.argid in $a { $a } else {
                $a | insert $x.argid {
                    "type": "promptString",
                    "id": $x.argid,
                    "description": $x.args
                }
            }
        }
    }
    | transpose k v
    | get v

    {
        version: "2.0.0"
        tasks: $tasks
        inputs: [...$inputs ...$args]
    }
}
