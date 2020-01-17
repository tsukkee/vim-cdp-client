scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#cdp#new()
let s:SHA1 = s:V.import('Hash.SHA1')
let s:Base64 = s:V.import('Data.Base64')
let s:Byte = s:V.import('Data.List.Byte')

let s:CRLF = "\r\n"

let cdp#websocket#OPEN = 'open'
let cdp#websocket#CLOSE = 'clsoe'
let cdp#websocket#MESSAGE = 'message'
let cdp#websocket#ERROR = 'error'

function! cdp#websocket#new(url) abort
    let matches = matchlist(a:url, '^\(\l\+://\)\([^/]\+\)\(\S*\)$')
    if empty(matches)
        throw a:url . ' is not valid url'
    endif
    let [scheme, host, path] = matches[1:3]

    if scheme !=# 'ws://'
        throw scheme . ' is not supported'
    endif

    let opt = #{
    \   mode: 'raw',
    \   drop: 'never'
    \}
    let ch = ch_open(host, opt)

    let key = s:Base64.encode(s:randomString(16))
    let req = 'GET ' . path . ' HTTP/1.1' . s:CRLF .
    \         'Host: ' . host . s:CRLF .
    \         'Upgrade: websocket' . s:CRLF .
    \         'Connection: Upgrade' . s:CRLF .
    \         'Sec-WebSocket-Key: ' . key . s:CRLF .
    \         'Sec-WebSocket-Version: 13' . s:CRLF .
    \         s:CRLF

    call ch_sendraw(ch, req, #{
    \   callback: {ch, msg -> s:upgradeCallback(ch, msg, key)}
    \})

    let this = #{
    \   send: function('s:WebSocket_send'),
    \   close: function('s:WebSocket_close'),
    \   on: function('s:WebSocket_on'),
    \   off: function('s:WebSocket_off'),
    \   ch: ch,
    \   listeners: {}
    \}

    return this
endfunction

function! s:upgradeCallback(ch, msg, key) abort
    if match(a:msg, 'HTTP/1.1 101') != 0
        call ch_close(a:ch)
        throw 'HTTP GET Upgrade failed'
    endif

    const separator = s:CRLF . s:CRLF
    let [headers; body] = split(a:msg, separator)

    let isValid = v:false
    for header in split(headers, s:CRLF)
        let match = matchlist(header, '^Sec-WebSocket-Accept: \(\S\+\)$')
        if !empty(match)
            let isValid = (match[1] ==# s:getSecWebSocketAcceptFromKey(a:key))
        endif
    endfor

    if !isValid
        " TODO: call error callback
        call ch_close(a:ch)
        throw 'Sec-WebSocket-Accept is not match'
    endif

    " TODO: call open callback
endfunction

function! s:WebSocket_send(data) dict abort

endfunction

function! s:WebSocket_close() dict abort
    call ch_close(self.ch)
endfunction


function! s:WebSocket_on(eventName, handler) dict abort
    if !has_key(self.listeners, a:eventName)
        let self.listeners[a:eventName] = []
    endif
    call add(self.listeners[a:eventName], a:handler)
endfunction

function! s:WebSocket_off(eventName, handler) dict abort
    if !has_key(self.listeners, a:eventName)
        return
    endif
    let idx = index(self.listeners, a:handler)
    if idx >= 0
        call remove(self.listeners[a:eventName], idx)
    endif
endfunction

function! s:invokeCallback(self, eventHandler) abort

endfunction

function! s:getSecWebSocketAcceptFromKey(key)
    const magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    let sha1 = s:SHA1.sum(a:key . magic)
    let bytes = s:Byte.from_hexstring(sha1)
    retur s:Base64.encodebytes(bytes)
endfunction
" echo s:getSecWebSocketAcceptFromKey('dGhlIHNhbXBsZSBub25jZQ==')
" -> s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
" echo s:getSecWebSocketAcceptFromKey('x3JJHMbDL1EzLkh9GBhXDw==')
" -> HSmrc0sMlYUkAGmm5OPpG2HaGWk=

function! s:randomString(length)
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    const size = len(chars)

    let result = ''
    for i in range(a:length)
        let result .= chars[rand() % size]
    endfor
    return result
endfunction

let &cpo = s:save_cpo
