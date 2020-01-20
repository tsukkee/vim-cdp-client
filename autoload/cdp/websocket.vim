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

    if ch_status(ch) ==# 'fail'
        throw 'Feiled to open a channlel with ' . a:url
    endif

    let key = s:Base64.encode(s:randomString(16))
    let req = 'GET ' . path . ' HTTP/1.1' . s:CRLF .
    \         'Host: ' . host . s:CRLF .
    \         'Upgrade: websocket' . s:CRLF .
    \         'Connection: Upgrade' . s:CRLF .
    \         'Sec-WebSocket-Key: ' . key . s:CRLF .
    \         'Sec-WebSocket-Version: 13' . s:CRLF .
    \         s:CRLF

    let this = #{
    \   send: function('s:WebSocket_send'),
    \   close: function('s:WebSocket_close'),
    \   on: function('s:WebSocket_on'),
    \   off: function('s:WebSocket_off'),
    \   _invokeListeners: function('s:WebSocket_invokeListeners'),
    \   _upgradeCallback: function('s:WebSocket_upgradeCallback'),
    \   _onMessage: function('s:WebSocket_onMessage'),
    \   _ch: ch,
    \   _listeners: {},
    \   _timer: v:none
    \}

    call ch_sendraw(ch, req, #{
    \   callback: {ch, msg -> this._upgradeCallback(msg, key)}
    \})

    return this
endfunction

function! s:WebSocket_send(data) dict abort
    " FIN: 0x1 RSV1-3: 0x0
    " Opcode: 0x01
    let req = 0z81

    " MASK: 0x1
    " Payload Length: len(a:data)
    " TODO: len() > 127
    let req = add(req, or(0x80, len(a:data)))

    " Masking Key: 0z12345678
    " TODO: use rand()
    let mask = 0z12345678
    let req += mask

    " str -> blob
    " TODO: find the proper way to do this
    let tmp = tempname()
    call writefile([command], tmp, 'bs')
    let payload = readfile(tmp, 'B')

    " masking
    for i in range(len(command))
        let payload[i] = xor(payload[i], mask[i % 4])
    endfor
    let req += payload

    call ch_sendraw(a:ch, req)
endfunction

function! s:WebSocket_close() dict abort
    call ch_close(self._ch)
    call self._invokeListeners(cdp#websocket#CLOSE)
endfunction

function! s:WebSocket_on(eventName, handler) dict abort
    if !has_key(self._listeners, a:eventName)
        let self._listeners[a:eventName] = []
    endif
    call add(self._listeners[a:eventName], a:handler)
endfunction

function! s:WebSocket_off(eventName, handler) dict abort
    if !has_key(self._listeners, a:eventName)
        return
    endif
    let idx = index(self._listeners, a:handler)
    if idx >= 0
        call remove(self._listeners[a:eventName], idx)
    endif
endfunction

function! s:WebSocket_upgradeCallback(msg, key) dict abort
    if match(a:msg, 'HTTP/1.1 101') != 0
        call ch_close(self._ch)
        call self._invokeCallback(cdp#websocket#ERROR, 'HTTP GET Upgrade failed')
        return
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
        call ch_close(self._ch)
        call self._invokeCallback(cdp#websocket#ERROR, 'Sec-WebSocket-Accept is not match')
        return
    endif

    call self._invokeCallback(cdp#websocket#OPEN)
    let self._timer = timer_start(100, {timer -> self._onMessage()}, {'repeat': -1})
endfunction

function! s:WebSocket_invokeListeners(eventName, ...) dict abort
    if !has_key(self._listeners, a:eventName)
        return
    endif

    for listener in self._listeners
        call call(listener, a:000)
    endfor
endfunction

function! s:WebSocket_onMessage(msg) dict abort
    if !ch_canread(self._ch)
        return
    endif

    let blob = ch_readblob(self._ch)

    let fin = and(0b10000000, blob[0]) / 128
    if fin != 1
        echoerr 'Not Supported when fin is not 1'
    endif

    let opcode = and(0b00001111, blob[0])
    if opcode != 1
        echoerr 'Only text frame is supported'
    endif

    let mask = and(0b10000000, blob[1])
    if mask != 0
        echoerr 'The message is not from server'
    endif

    let len = and(0b01111111, blob[1])
    let idx = 2
    if len == 126
        let len = blob[2] * 256 + blob[3]
        let idx = 4
    elseif len == 127
        let len = blob[2] * 256 * 256 * 256 + blob[3] * 256 * 256 + blob[4] * 256 + blob[5]
        let idx = 6
    endif

    let payload = blob[idx:idx+len]
    let tmp = tempname()
    call writefile(payload, tmp, "bs")
    let response = join(readfile(tmp), '')

    call self._invokeListeners(cdp#websocket#MESSAGE, response)
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
