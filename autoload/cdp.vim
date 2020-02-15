scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#cdp#new()
let s:Promise = s:V.import('Async.Promise')

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
    let id = s:uniqueId()
    let request = #{
    \   id: id,
    \   method: a:method,
    \   params: a:params
    \}

    call self._websocket.send(json_encode(request))
    return s:Promise.new({resolve, reject ->
    \   execute('let s:requests['. id . '] = #{resolve: resolve, reject: reject}')})
endfunction

let s:requests = {}

function! s:onMessage(msg) abort
    let response = json_decode(a:msg)

    if has_key(s:requests, response.id)
        let id = response.id
        if has_key(response, 'result')
            call s:requests[id].resolve(response['result'])
        elseif has_key(response, 'error')
            call s:requests[id].reject(response['error'])
        else
            call s:requests[id].reject('Unknown error')
        endif
        unlet s:requests[id]
    endif
endfunction

let s:messageId = 0
function! s:uniqueId() abort
    let s:messageId += 1
    return s:messageId
endfunction

let &cpo = s:save_cpo
