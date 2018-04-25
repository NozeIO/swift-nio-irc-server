# miniircd

A small IRC demo server for SwiftNIO IRC.



## Configuring Clients

### irssi

On macOS you can install [irssi](http://www.irssi.org)
using:
```
brew install irssi
```

Register a new network and connect to the server:
```
/NETWORK ADD NIO
/SERVER  ADD -auto -network NIO localhost 6667
/CHANNEL ADD -auto #nio NIO
/CONNECT localhost
```


### Who

Brought to you by
[ZeeZide](http://zeezide.de).
We like
[feedback](https://twitter.com/ar_institute),
GitHub stars,
cool [contract work](http://zeezide.com/en/services/services.html),
presumably any form of praise you can think of.
