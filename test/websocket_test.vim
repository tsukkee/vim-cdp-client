" let path = expand('<sfile>:h:h')
" let &rtp += ',' . path
packadd vim-cdp-client

let g:websocket = cdp#websocket#new('ws://localhost:8080/echo')

function! s:onOpen() abort
    echom 'Open!'
    call g:websocket.send('hogeああああああああああああああ')
    " call g:websocket.send('hogeああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああああ')
endfunction

function! s:onClose() abort
    echom 'Close!'
endfunction

function! s:onMessage(msg) abort
    echom a:msg
endfunction

function! s:onError(msg) abort
    echoerr a:msg
endfunction

call g:websocket.on(g:cdp#websocket#OPEN, function('s:onOpen'))
call g:websocket.on(g:cdp#websocket#CLOSE, function('s:onClose'))
call g:websocket.on(g:cdp#websocket#MESSAGE, function('s:onMessage'))
call g:websocket.on(g:cdp#websocket#ERROR, function('s:onError'))

