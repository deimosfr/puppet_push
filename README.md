puppet_push
===========

Ask Puppet to synchronize from a master node

```
Usage : puppet_push [-h] [-l|-s] [-pca puppetca_path] [-n nodes] [-e nodes] [-t tag] [-y] [-mt threads] [-v] [-d]

Options :
-h, --help
	Print this help screen
-l, --list
	List registered nodes
-s, --sync
	Send a request on Puppet clients for sync
-pca
	Set puppetca binary full path (default is /usr/sbin/puppetca)
-n
	Nodes to be synchronized from master
-e
	Nodes to exclude from synchronisation
-t
	Set tags (Puppet class) to sync (default all)
-y, --yesall
	Always answer yes to any questions
-mt, --simultanous
	Number of maximum simultanous clients sync requests (Default is 2)
-v, --verbose
	Verbose output
-d, --debug
	Debug mode

Examples :
puppet_push -l
puppet_push -s -n puppet_fr_client-\d+ -n puppet_us_client-\d+ -e puppet_client-2.mydomain.com -t ntp -t ldapclient -mt 4
```

License
-------

GPL

Author Information
------------------

Pierre Mavro / deimosfr
