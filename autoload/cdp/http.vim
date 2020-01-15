scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:CRLF = "\r\n"

" very simple HTTP GET (sync)
function! cdp#http#get(url) abort
    let matches = matchlist(a:url, '^\(\l\+://\)\([^/]\+\)\(\S*\)$')
    if empty(matches)
        throw a:url . ' is not valid url'
    endif
    let [scheme, host, path] = matches[1:3]

    if scheme !=# 'http://'
        throw scheme . ' is not supported'
    endif

    let opt = #{
    \   mode: 'raw',
    \   drop: 'never',
    \   callback: {ch, msg -> s:http_get_callback(ch, msg)}
    \}
    let ch = ch_open(host, opt)

    let req = 'GET ' . path . ' HTTP/1.1' . s:CRLF .
    \         'Host: ' . host . s:CRLF .
    \         s:CRLF

    let s:body = ''
    let s:headers = []
    call ch_sendraw(ch, req)

    while empty(s:body)
        sleep 10ms
    endwhile

    if s:headers[0] !=# 'HTTP/1.1 200 OK'
        throw 'HTTP GET fails: ' . s:headers[0]
    endif

    return s:body
endfunction

function! s:http_get_callback(ch, msg) abort
    call ch_close(a:ch)

    const separator = s:CRLF . s:CRLF
    let [headers; body] = split(a:msg, separator)

    let s:headers = split(headers, s:CRLF)
    let s:body = join(body, separator)
endfunction

let &cpo = s:save_cpo
