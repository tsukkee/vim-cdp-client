scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#cdp#new()
let s:SHA1 = s:V.import('Hash.SHA1')
let s:Base64 = s:V.import('Data.Base64')
let s:Byte = s:V.import('Data.List.Byte')

let s:CRLF = "\r\n"

let g:cdp#websocket#OPEN = 'open'
let g:cdp#websocket#CLOSE = 'close'
let g:cdp#websocket#MESSAGE = 'message'
let g:cdp#websocket#ERROR = 'error'

function! cdp#websocket#new(url) abort
    let [scheme, host, path] = cdp#util#parse_url(a:url)
    if scheme !=# 'ws://'
        throw scheme . ' is not supported'
    endif

    let ch = cdp#util#ch_open(host)
    let key = s:Base64.encode(s:randomString(16))
    let req = cdp#util#build_http_request('GET', host, path, {
    \   'Upgrade': 'websocket',
    \   'Connection': 'Upgrade',
    \   'Sec-WebSocket-Key': key,
    \   'Sec-WebSocket-Version': '13'
    \})

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
    call writefile([a:data], tmp, 'bs')
    let payload = readfile(tmp, 'B')

    " masking
    for i in range(len(a:data))
        let payload[i] = xor(payload[i], mask[i % 4])
    endfor
    let req += payload

    call ch_sendraw(self._ch, req)
endfunction

function! s:WebSocket_close() dict abort
    call ch_close(self._ch)
    call self._invokeListeners(g:cdp#websocket#CLOSE)
endfunction

function! s:WebSocket_on(eventName, listner) dict abort
    if !has_key(self._listeners, a:eventName)
        let self._listeners[a:eventName] = []
    endif
    call add(self._listeners[a:eventName], a:listner)
endfunction

function! s:WebSocket_off(eventName, listner) dict abort
    if !has_key(self._listeners, a:eventName)
        return
    endif
    let idx = index(self._listeners, a:listner)
    if idx >= 0
        call remove(self._listeners[a:eventName], idx)
    endif
endfunction

function! s:WebSocket_upgradeCallback(msg, key) dict abort
    if match(a:msg, 'HTTP/1.1 101') != 0
        call ch_close(self._ch)
        call self._invokeListeners(g:cdp#websocket#ERROR, 'HTTP GET Upgrade failed')
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
        call self._invokeListeners(g:cdp#websocket#ERROR, 'Sec-WebSocket-Accept is not match')
        return
    endif

    call self._invokeListeners(g:cdp#websocket#OPEN)
    let self._timer = timer_start(100, {timer -> self._onMessage()}, {'repeat': -1})
endfunction

function! s:WebSocket_invokeListeners(eventName, ...) dict abort
    if !has_key(self._listeners, a:eventName)
        return
    endif

    for Listener in self._listeners[a:eventName]
        call call(Listener, a:000)
    endfor
endfunction

function! s:WebSocket_onMessage() dict abort
    if !ch_canread(self._ch)
        return
    endif

    let blob = ch_readblob(self._ch)

    " TODO: support when fin is not 1
    let fin = and(0b10000000, blob[0]) / 128
    if fin != 1
        echoerr 'Not Supported when fin is not 1'
    endif

    " TODO: support binary frame
    let opcode = and(0b00001111, blob[0])
    if opcode != 1
        echoerr 'Only text frame is supported'
    endif

    let mask = and(0b10000000, blob[1])
    if mask != 0
        echoerr 'The message is not from a server'
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

    " blob -> str
    " TODO: find the proper way to do this
    let tmp = tempname()
    call writefile(payload, tmp, "bs")
    let response = join(readfile(tmp), '')

    call self._invokeListeners(g:cdp#websocket#MESSAGE, response)
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
