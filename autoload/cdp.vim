scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

function! cdp#new(port=9222) abort
    let body = cdp#http#get('http://localhost:' . a:port . '/json')
    let json = json_decode(body)

    let page = v:none
    for info in json
        if info.type ==# 'page'
            let page = info
            break
        endif
    endfor
    if empty(page)
        echoerr 'No page found'
    endif

    let websocket = cdp#websocket#new(page.webSocketDebuggerUrl)
    call websocket.on(g:cdp#websocket#MESSAGE, function('s:onMessage'))

    return #{
    \   _websocket: websocket,
    \   send: function('s:CDPClient_send')
    \}
endfunction

function! s:CDPClient_send(method, params={}) abort dict
    let request = #{
    \   id: s:uniqueId(),
    \   method: a:method,
    \   params: a:params
    \}

    call self._websocket.send(json_encode(request))
endfunction

function! s:onMessage(msg) abort
    echom a:msg
endfunction

let s:messageId = 0
function! s:uniqueId() abort
    let s:messageId += 1
    return s:messageId
endfunction

let &cpo = s:save_cpo
