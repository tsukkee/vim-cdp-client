scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:CRLF = "\r\n"

function! cdp#util#throw(message) abort
    throw 'CDPERROR: ' . a:message
endfunction

function! cdp#util#parse_url(url) abort
    let matches = matchlist(a:url, '^\(\l\+://\)\([^/]\+\)\(\S*\)$')
    if empty(matches)
        call cdp#uril#throw(a:url . ' is not valid url')
    else
        return matches[1:3]
    endif
endfunction

function! cdp#util#ch_open(host) abort
    let ch = ch_open(a:host, #{mode: 'raw', drop: 'never'})
    if ch_status(ch) ==# 'fail'
        call cdp#util#throw('Fail to open a channel with ' . a:host)
    endif
    return ch
endfunction

function! cdp#util#build_http_request(method, host, path, header = {}, body = '') abort
    let req = a:method . ' ' . a:path . ' HTTP/1.1' . s:CRLF .
    \         'Host: ' . a:host . s:CRLF

    for [key, value] in items(a:header)
        let req .= key . ': ' . value . s:CRLF
    endfor
    let req .= s:CRLF
    let req .= a:body
    return req
endfunction

function! cdp#util#parse_http_response(response) abort


endfunction

let &cpo = s:save_cpo
