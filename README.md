* compile with
`zig build-exe test.zig`
* run `./test` and press ctrl-c after a while
* you should see the following
```
$ ./test 
Hi! I am 'TEST-EDSM'. Press ^C to stop me.
{ 1, 0, 0, 0, 0, 0, 0, 0 }
tick #1
{ 1, 0, 0, 0, 0, 0, 0, 0 }
tick #2
{ 1, 0, 0, 0, 0, 0, 0, 0 }
tick #3
^Cgot SIGINT after 3 ticks
Bye! It was 'TEST-EDSM'
```
