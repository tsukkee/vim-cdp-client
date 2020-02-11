**WIP**

# vim-cdp-client

100% Pure Vim Script implementation of Chrome Debugger Protocol client

# Example

At first, launch Google Chrome with `--remote-debugging-port=9222`. Then, below code will reload an active page.

```
let cdp = cdp#new()
call cdp.send('Page.reload')
```

# References

- https://tools.ietf.org/html/rfc6455
- https://chromedevtools.github.io/devtools-protocol/tot/
