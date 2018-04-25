# cgiwm

An extremely simple CGI-based webmention receiver. Stores each notification as a json snippet in a "queue" directory, which can then be processed separately and the resulting webmentions.json file is copied into the target path in the htdocs dir (i.e. the target directory of the webmention notification). Compliant with receiver test #1 and #2 of the webmention [test suite](https://webmention.rocks/).
See [https://www.w3.org/TR/webmention/](https://www.w3.org/TR/webmention/) for more information.

Usage:

* `cgiwm cgi <queuedir>` to provide a CGI-based webmention end point
* `cgiwm process <queuedir> <htdocs> [--invoke <cmd>]` to process webmention json snippets in the queuedir, and write the results into the correct place in htdocs (optionally invoke a command for each webmention.json file created/updated)


Example Apache2 configuration for CGI:
```
ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
<Directory "/usr/lib/cgi-bin">
    AllowOverride None
    Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
    Order allow,deny
    Allow from all
</Directory>

RewriteEngine On
RewriteRule /webmention-endpoint /cgi-bin/cgiwm.cgi [NC,PT]
```

(obviously, in this example, install the cgiwm executable and associated cgiwm.cgi script in /usr/lib/cgi-bin)

An example crontab entry for converting webmention snippets and producing webmention.json files in the target dir is:

```
*/5 * * * * cronic /usr/lib/cgi-bin/cgiwm process /tmp/ /var/www/
```
