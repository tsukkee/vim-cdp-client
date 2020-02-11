
packadd vim-cdp-client

let g:cdp = cdp#new()
call g:cdp.send('Page.reload')
