xquery version "3.0";

module namespace docs="http://exist-db.org/xquery/docs";

import module namespace xdb="http://exist-db.org/xquery/xmldb";
import module namespace xqdm="http://exist-db.org/xquery/xqdoc";
import module namespace dbutil="http://exist-db.org/xquery/dbutil" at "dbutils.xql";
import module namespace inspect="http://exist-db.org/xquery/inspection" at "java:org.exist.xquery.functions.inspect.InspectionModule";

declare namespace xqdoc="http://www.xqdoc.org/1.0";
 
declare %private function docs:create-collection($parent as xs:string, $child as xs:string) as empty() {
    let $null := xdb:create-collection($parent, $child)
    return ()
};

declare %private function docs:load-external($uri as xs:string, $store as function(xs:string, element()) as empty()) {
    let $xml := xqdm:scan(xs:anyURI($uri))
    let $moduleURI := $xml//xqdoc:module/xqdoc:uri
    return
        $store($moduleURI, $xml)
};

declare %private function docs:load-stored($path as xs:anyURI, $store as function(xs:string, element()) as empty()) {
    let $xml := docs:generate-xqdoc(inspect:inspect-module($path), $path)
    let $name := replace($path, "^.*/([^/]+)\.[^\.]+$", "$1")
    let $moduleURI := $xml//xqdoc:module/xqdoc:uri
    return
        $store($moduleURI, $xml)
};

declare %private function docs:load-external-modules($store as function(xs:string, element()) as empty()) {
    for $uri in util:mapped-modules()
    return
        docs:load-external($uri, $store),
    for $path in dbutil:find-by-mimetype(xs:anyURI("/db"), "application/xquery")
    return
        try {
            docs:load-stored($path, $store)
        } catch * {
            util:log("DEBUG", "Error: " || $err:description)
        }
};

declare %private function docs:load-internal-modules($store as function(xs:string, element()) as empty()) {
    for $moduleURI in util:registered-modules()
	let $moduleDocs := util:extract-docs($moduleURI)
	return 
	   if ($moduleDocs) then
           $store($moduleURI, $moduleDocs)
	   else
	      ()
};

declare function docs:load-fundocs($target as xs:string) {
    let $dataColl := xdb:create-collection($target, "data")
    let $store := function($moduleURI as xs:string, $data as element()) {
        let $name := util:hash($moduleURI, "md5") || ".xml"
        return
        (
            xdb:store($dataColl, $name, $data),
            sm:chmod(xs:anyURI($dataColl || "/" || $name), "rw-rw-r--")
        )[2]
    }
    return (
    	docs:load-internal-modules($store),
    	docs:load-external-modules($store)
    )
};

declare function docs:generate-xqdoc($module as element(module), $location as xs:anyURI) {
    <xqdoc:xqdoc xmlns:xqdoc="http://www.xqdoc.org/1.0">
        <xqdoc:control>
            <xqdoc:date>{current-dateTime()}</xqdoc:date>
            <xqdoc:location>{$location}</xqdoc:location>
        </xqdoc:control>
        <xqdoc:module type="library">
            <xqdoc:uri>{$module/@uri/string()}</xqdoc:uri>
            <xqdoc:name>{$module/@prefix/string()}</xqdoc:name>
        </xqdoc:module>
        <xqdoc:functions>
        {
            for $func in $module/function
            return
                <xqdoc:function>
                    <xqdoc:name>{$func/@name/string()}</xqdoc:name>
                    <xqdoc:signature>{docs:generate-signature($func)}</xqdoc:signature>
                    <xqdoc:comment>
                        {$func/description}
                        {
                            for $param in $func/argument
                            return
                                <xqdoc:param>${$param/@var/string()}{" "}{$param/text()}</xqdoc:param>
                        }
                        <xqdoc:return>{$func/returns/text()}</xqdoc:return>
                    </xqdoc:comment>
                </xqdoc:function>
        }
        </xqdoc:functions>
    </xqdoc:xqdoc>
};

declare function docs:generate-signature($func as element(function)) {
    $func/@name/string() || "(" ||
    string-join(
        for $param in $func/argument
        return
            "$" || $param/@var/string() || " as " || $param/@type/string(),
        ", "
    ) ||
    ")"
};