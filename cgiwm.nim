import cgi
import httpclient
import httpcore
import json
import os
import ospaths
import osproc
import strtabs
import strutils
import times
import uri

import docopt

let doc = """
cgiwm. CGI-based webmention receiver.

Usage:
  cgiwm cgi <queuedir>
  cgiwm process <queuedir> <htdocs> [--invoke <cmd>]

Commands:
    cgi         Receive webmention requests and queue in a directory
    process     Process the webmention requests stored in a queue directory

Options:
  -h --help     Show this screen.
  --version     Show version
"""


proc errorMessage(status:string, msg:string) =
    writeLine(stdout, "Status: " & status)
    writeContentType()
    writeLine(stdout, "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">")
    writeLine(stdout, "<html><body>")
    writeLine(stdout, msg)
    writeLine(stdout, "</body></html>")


proc findJsonVal(node:JsonNode, target:string):bool =
    if node.kind == JObject:
        for key,val in pairs(node):
            if findJsonVal(val, target):
                return true
    elif node.kind == JArray:
        for childnode in items(node):
            if findJsonVal(childnode, target):
                return true
    else:
        var val = getStr(node)
        if val == target:
            return true
    return false


proc checkSource(source:string, target:string):bool =
    try:
        var client = newHttpClient()
        let response = client.request(source, httpMethod = HttpGet)
        var contentType = response.headers["content-type"]

        if startsWith(contentType, "text/html"):
            var href = "href=\"" & target
            return find(response.body, href) >= 0
        elif startsWith(contentType, "application/json"):
            var j = parseJson(response.body)
            return findJsonVal(j, target)
        elif startsWith(contentType, "text/plain"):
            return find(response.body, target) >= 0
        return false
    except:
        return false


proc validUri(u:string):bool =
    try:
        let _ = parseUri(u)
        return true
    except:
        return false


proc isUriAccessible(u:string):bool =
    var client = newHttpClient()
    let response = client.request(u, httpMethod = HttpHead)
    let c = code(response)
    return is2xx(c) or is3xx(c)


proc cgireceive(queuedir:string) =
    if getRequestMethod() == "GET":
        errorMessage("200 OK", "Webmention endpoint")
        return

    var data = readData({methodPost})
    if not hasKey(data, "source") or not hasKey(data, "target"):
        errorMessage("400 Bad Request", "Invalid or malformed webmention content")
        return

    var remoteAddr = getRemoteAddr()
    var source = data["source"]
    var target = data["target"]

    if source == "" or target == "":
        errorMessage("400 Bad Request", "Invalid or malformed webmention content")
        return
    if not validUri(source) or not validUri(target):
        errorMessage("400 Bad Request", "Invalid or malformed source/target URIs")
        return

    if not checkSource(source, target):
        errorMessage("400 Bad Request", "Invalid webmention, no reference found in source")
        return

    var fname = joinPath(queuedir, remoteAddr & ".webmention")
    if existsFile(fname):
        errorMessage("400 Bad Request", "An existing webmention request has been queued for " & remoteAddr)
        return

    var j = %*
        {
            "source": source,
            "target": target
        }

    var fout = open(fname, fmWrite)
    writeLine(fout, j.`$`)
    close(fout)

    writeLine(stdout, "Status: 202 Accepted")
    var s = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">" & "<html><body>webmention queued<body></html>"
    writeLine(stdout, "Content-Length: " & len(s).`$`)
    writeContentType()
    writeLine(stdout, s)


proc addWebmention(source:string, ctime:Time, target:string, targetdir:string, invokecmd:string) =
    var wmfile = joinPath(targetdir, "webmentions.json")
    var j = %* []
    if existsFile(wmfile):
        j = parseFile(wmfile)

    if findJsonVal(j, source):
        echo "WARNING: already found webmention for " & target & " from source: " & source
        return

    var link = %*
        {
            "source": source,
            "published": ctime.`$`
        }

    add(j, link)

    var fout = open(wmfile, fmWrite)
    writeLine(fout, pretty(j))
    close(fout)

    if invokecmd != nil and invokecmd != "":
        let outp = execProcess(invokecmd & " " & wmfile)
        if outp != "":
            write(stdout, outp)


proc processQueuedWebmentions(queuedir:string, htdocs:string, invokecmd:string) =
    setCurrentDir(queuedir)
    for f in walkFiles("*.webmention"):
        var j = parseFile(f)

        var source = getStr(j["source"])
        var target = getStr(j["target"])
        var ctime = getCreationTime(f)

        removeFile(f)

        var d = parentDir(joinPath(htdocs, parseUri(target).path))
        if not existsDir(d):
            echo "ERROR: cannot find target dir " & d
            continue

        if not checkSource(source, target):
            echo "ERROR: could not find " & target & " at source: " & source
            continue

        addWebmention(source, ctime, target, d, invokecmd)


if isMainModule:
    let args = docopt(doc, version = "0.1")

    if args["cgi"]:
        var queuedir = $args["<queuedir>"]
        cgireceive(queuedir)

    elif args["process"]:
        var queuedir = $args["<queuedir>"]
        var htdocs = $args["<htdocs>"]
        var invokecmd = ""
        if args["<cmd>"]:
            invokecmd = $args["<cmd>"]
        processQueuedWebmentions(queuedir, htdocs, invokecmd)
