
packadd vim-cdp-client

let g:cdp = cdp#new()
call g:cdp.send('Page.reload').then({
\   result -> execute('let g:result1 = result')
\})

call g:cdp.send('Hoge').catch({
\   error -> execute('let g:result2 = error')
\})



