scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:CRLF = "\r\n"

" very simple HTTP GET (sync)
function! cdp#http#get(url) abort
    let [scheme, host, path] = cdp#util#parse_url(a:url)
    if scheme !=# 'http://'
        throw scheme . ' is not supported'
    endif

    let ch = cdp#util#ch_open(host)
    let req = cdp#util#build_http_request('GET', host, path)

    let s:body = ''
    let s:headers = []
    call ch_sendraw(ch, req, #{
    \   callback: {ch, msg -> s:http_get_callback(ch, msg)}
    \})

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
