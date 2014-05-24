if (typeof JSON !== 'object') {
    JSON = {};
}

(function () {
    'use strict';

    function f(n) {
        // Format integers to have at least two digits.
        return n < 10 ? '0' + n : n;
    }

    if (typeof Date.prototype.toJSON !== 'function') {

        Date.prototype.toJSON = function () {

            return isFinite(this.valueOf())
                ? this.getUTCFullYear()     + '-' +
                    f(this.getUTCMonth() + 1) + '-' +
                    f(this.getUTCDate())      + 'T' +
                    f(this.getUTCHours())     + ':' +
                    f(this.getUTCMinutes())   + ':' +
                    f(this.getUTCSeconds())   + 'Z'
                : null;
        };

        String.prototype.toJSON      =
            Number.prototype.toJSON  =
            Boolean.prototype.toJSON = function () {
                return this.valueOf();
            };
    }

    var cx = /[\u0000\u00ad\u0600-\u0604\u070f\u17b4\u17b5\u200c-\u200f\u2028-\u202f\u2060-\u206f\ufeff\ufff0-\uffff]/g,
        escapable = /[\\\"\x00-\x1f\x7f-\x9f\u00ad\u0600-\u0604\u070f\u17b4\u17b5\u200c-\u200f\u2028-\u202f\u2060-\u206f\ufeff\ufff0-\uffff]/g,
        gap,
        indent,
        meta = {    // table of character substitutions
            '\b': '\\b',
            '\t': '\\t',
            '\n': '\\n',
            '\f': '\\f',
            '\r': '\\r',
            '"' : '\\"',
            '\\': '\\\\'
        },
        rep;


    function quote(string) {

// If the string contains no control characters, no quote characters, and no
// backslash characters, then we can safely slap some quotes around it.
// Otherwise we must also replace the offending characters with safe escape
// sequences.

        escapable.lastIndex = 0;
        return escapable.test(string) ? '"' + string.replace(escapable, function (a) {
            var c = meta[a];
            return typeof c === 'string'
                ? c
                : '\\u' + ('0000' + a.charCodeAt(0).toString(16)).slice(-4);
        }) + '"' : '"' + string + '"';
    }


    function str(key, holder) {

// Produce a string from holder[key].

        var i,          // The loop counter.
            k,          // The member key.
            v,          // The member value.
            length,
            mind = gap,
            partial,
            value = holder[key];

// If the value has a toJSON method, call it to obtain a replacement value.

        if (value && typeof value === 'object' &&
                typeof value.toJSON === 'function') {
            value = value.toJSON(key);
        }

// If we were called with a replacer function, then call the replacer to
// obtain a replacement value.

        if (typeof rep === 'function') {
            value = rep.call(holder, key, value);
        }

// What happens next depends on the value's type.

        switch (typeof value) {
        case 'string':
            return quote(value);

        case 'number':

// JSON numbers must be finite. Encode non-finite numbers as null.

            return isFinite(value) ? String(value) : 'null';

        case 'boolean':
        case 'null':

// If the value is a boolean or null, convert it to a string. Note:
// typeof null does not produce 'null'. The case is included here in
// the remote chance that this gets fixed someday.

            return String(value);

// If the type is 'object', we might be dealing with an object or an array or
// null.

        case 'object':

// Due to a specification blunder in ECMAScript, typeof null is 'object',
// so watch out for that case.

            if (!value) {
                return 'null';
            }

// Make an array to hold the partial results of stringifying this object value.

            gap += indent;
            partial = [];

// Is the value an array?

            if (Object.prototype.toString.apply(value) === '[object Array]') {

// The value is an array. Stringify every element. Use null as a placeholder
// for non-JSON values.

                length = value.length;
                for (i = 0; i < length; i += 1) {
                    partial[i] = str(i, value) || 'null';
                }

// Join all of the elements together, separated with commas, and wrap them in
// brackets.

                v = partial.length === 0
                    ? '[]'
                    : gap
                    ? '[\n' + gap + partial.join(',\n' + gap) + '\n' + mind + ']'
                    : '[' + partial.join(',') + ']';
                gap = mind;
                return v;
            }

// If the replacer is an array, use it to select the members to be stringified.

            if (rep && typeof rep === 'object') {
                length = rep.length;
                for (i = 0; i < length; i += 1) {
                    if (typeof rep[i] === 'string') {
                        k = rep[i];
                        v = str(k, value);
                        if (v) {
                            partial.push(quote(k) + (gap ? ': ' : ':') + v);
                        }
                    }
                }
            } else {

// Otherwise, iterate through all of the keys in the object.

                for (k in value) {
                    if (Object.prototype.hasOwnProperty.call(value, k)) {
                        v = str(k, value);
                        if (v) {
                            partial.push(quote(k) + (gap ? ': ' : ':') + v);
                        }
                    }
                }
            }

// Join all of the member texts together, separated with commas,
// and wrap them in braces.

            v = partial.length === 0
                ? '{}'
                : gap
                ? '{\n' + gap + partial.join(',\n' + gap) + '\n' + mind + '}'
                : '{' + partial.join(',') + '}';
            gap = mind;
            return v;
        }
    }

// If the JSON object does not yet have a stringify method, give it one.

    if (typeof JSON.stringify !== 'function') {
        JSON.stringify = function (value, replacer, space) {

// The stringify method takes a value and an optional replacer, and an optional
// space parameter, and returns a JSON text. The replacer can be a function
// that can replace values, or an array of strings that will select the keys.
// A default replacer method can be provided. Use of the space parameter can
// produce text that is more easily readable.

            var i;
            gap = '';
            indent = '';

// If the space parameter is a number, make an indent string containing that
// many spaces.

            if (typeof space === 'number') {
                for (i = 0; i < space; i += 1) {
                    indent += ' ';
                }

// If the space parameter is a string, it will be used as the indent string.

            } else if (typeof space === 'string') {
                indent = space;
            }

// If there is a replacer, it must be a function or an array.
// Otherwise, throw an error.

            rep = replacer;
            if (replacer && typeof replacer !== 'function' &&
                    (typeof replacer !== 'object' ||
                    typeof replacer.length !== 'number')) {
                throw new Error('JSON.stringify');
            }

// Make a fake root object containing our value under the key of ''.
// Return the result of stringifying the value.

            return str('', {'': value});
        };
    }


// If the JSON object does not yet have a parse method, give it one.

    if (typeof JSON.parse !== 'function') {
        JSON.parse = function (text, reviver) {

// The parse method takes a text and an optional reviver function, and returns
// a JavaScript value if the text is a valid JSON text.

            var j;

            function walk(holder, key) {

// The walk method is used to recursively walk the resulting structure so
// that modifications can be made.

                var k, v, value = holder[key];
                if (value && typeof value === 'object') {
                    for (k in value) {
                        if (Object.prototype.hasOwnProperty.call(value, k)) {
                            v = walk(value, k);
                            if (v !== undefined) {
                                value[k] = v;
                            } else {
                                delete value[k];
                            }
                        }
                    }
                }
                return reviver.call(holder, key, value);
            }


// Parsing happens in four stages. In the first stage, we replace certain
// Unicode characters with escape sequences. JavaScript handles many characters
// incorrectly, either silently deleting them, or treating them as line endings.

            text = String(text);
            cx.lastIndex = 0;
            if (cx.test(text)) {
                text = text.replace(cx, function (a) {
                    return '\\u' +
                        ('0000' + a.charCodeAt(0).toString(16)).slice(-4);
                });
            }

// In the second stage, we run the text against regular expressions that look
// for non-JSON patterns. We are especially concerned with '()' and 'new'
// because they can cause invocation, and '=' because it can cause mutation.
// But just to be safe, we want to reject all unexpected forms.

// We split the second stage into 4 regexp operations in order to work around
// crippling inefficiencies in IE's and Safari's regexp engines. First we
// replace the JSON backslash pairs with '@' (a non-JSON character). Second, we
// replace all simple value tokens with ']' characters. Third, we delete all
// open brackets that follow a colon or comma or that begin the text. Finally,
// we look to see that the remaining characters are only whitespace or ']' or
// ',' or ':' or '{' or '}'. If that is so, then the text is safe for eval.

            if (/^[\],:{}\s]*$/
                    .test(text.replace(/\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})/g, '@')
                        .replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, ']')
                        .replace(/(?:^|:|,)(?:\s*\[)+/g, ''))) {

// In the third stage we use the eval function to compile the text into a
// JavaScript structure. The '{' operator is subject to a syntactic ambiguity
// in JavaScript: it can begin a block or an object literal. We wrap the text
// in parens to eliminate the ambiguity.

                j = eval('(' + text + ')');

// In the optional fourth stage, we recursively walk the new structure, passing
// each name/value pair to a reviver function for possible transformation.

                return typeof reviver === 'function'
                    ? walk({'': j}, '')
                    : j;
            }

// If the text is not JSON parseable, then a SyntaxError is thrown.

            throw new SyntaxError('JSON.parse');
        };
    }
}());

qx.Class.define("myproject.Application", {
/*
#asset(qx/icon/Tango/32/actions/dialog-close.png)
#asset(qx/icon/Tango/32/actions/help-faq.png)
#asset(qx/icon/Tango/32/actions/document-save.png)
#asset(qx/icon/Tango/32/actions/dialog-apply.png)
#asset(qx/icon/Tango/32/status/dialog-information.png)
#asset(qx/icon/Tango/32/actions/list-remove.png)
#asset(qx/icon/Tango/32/actions/list-add.png)
#asset(qx/icon/Tango/16/actions/list-add.png)
#asset(qx/icon/Tango/16/actions/list-remove.png)
#asset(qx/icon/Tango/16/actions/document-open.png)
#asset(qx/icon/Tango/16/places/folder.png)
#asset(qx/icon/Tango/16/mimetypes/office-document.png)
#asset(qx/icon/Tango/32/actions/document-save-as.png)
*/
// TODO:XXX:FIXME: Die Bilderliste ist derzeit nicht von anderen Modulen erweiterbar!

   extend : qx.application.Standalone,
   members : {
      main : function() {
         this.base(arguments);
         this.randomnumber=Math.floor(Math.random()*9999999999999);
         //qx.debug = "on";
         //qx.disposerDebugLevel = 1;
         //if (qx.core.Variant.isSet("qx.debug", "on")) {
            // support native logging capabilities, e.g. Firebug for Firefox
            qx.log.appender.Native;
            // support additional cross-browser console. Press F7 to toggle visibility
            qx.log.appender.Console;
         //}
         qx.locale.Manager.getInstance().setLocale("de");

         this.running = 1;
         this.objects = new Hash();
         this.tablelisteners = new Hash();
         this.menuobjects = new Hash();
         this.ioreqs = new Array();
         this.iodata = new Array();
         this.ionum = 1;

         function div(n1, n2) {
            return ( n1 - (n1 % n2) ) / n2;
         }

         this.canCloseForm = function (myself, tree) {
            myself.main.debug("canClose: " + myself.id); 
            if (myself.changed) {
               for (var j = 0; j < tree.length; j++) {
                  myself.main.debug("canClose: Found " + tree[j].id + " (" + tree[j].constructor + ")" );
                  if ((tree[j].constructor   == "[Class myproject.myTabViewPage]") &&
                      (tree[j-1].constructor == "[Class qx.ui.tabview.TabView]")) {
                     myself.main.debug("canClose: Switching tab on " + tree[j-1].id + " to " + tree[j].id);
                     tree[j-1].setSelection([tree[j]]);
                  }
               }
               myself.main.processCommands("showmessage " + escape("Ungespeicherte Änderungen") + " 320 210 " + escape("Diese Seite beinhaltet ungespeicherte Änderungen.<br><br>Wenn Sie diese Speichern möchten, so klicken Sie<br>einfach auf Speichern.<br><br>Erneutes Schließen verwirft alle Änderungen."));
               myself.changed = 0;
               return 1;
            }
            return 0;
         };

         ///////////////// MENU

         this.scroller = new qx.ui.container.Composite(new qx.ui.layout.Grow);
         this.root = new qx.ui.container.Composite(new qx.ui.layout.VBox).set({
            allowGrowX: true,
            allowGrowY: true
         });
         this.scroller.add(this.root);
         this.getRoot().add(this.scroller, {edge: 0});
         //this.getRoot().add(this.root);
         this.desktop = new qx.ui.window.Desktop(new qx.ui.window.Manager());
         this.desktop.set({decorator: "main", backgroundColor: "background-pane"});
         this.desktop.childs = new Hash();
         this.root.add(this.desktop, { flex : 1 });         

         /* --- Sprachenauswahl ----
         var localeManager = qx.locale.Manager.getInstance();
         var locales = localeManager.getAvailableLocales().sort();
         var currentLocale = localeManager.getLocale();

         var select = new qx.ui.form.SelectBox();
         var defaultListItem = null;

         for (var i=0; i<locales.length; i++) {
            var listItem =new qx.ui.form.ListItem(locales[i]);
            select.add(listItem);
            if ((!defaultListItem && locales[i] == "en") || locales[i] == currentLocale) {
               defaultListItem = listItem;
            }
         }

         select.addListener("changeSelection", function(e) {
            var locale = e.getData()[0].getLabel();
            qx.locale.Manager.getInstance().setLocale(locale);
         });

         if (defaultListItem) {
            select.setSelection([defaultListItem]);
         }

         this.desktop.add(select); */

         ///////////////// MENU

         /////////////////////////////// LoginWindow Begin

/*         var menuwin = new qx.ui.window.Window("Auswahl");
         menuwin.setWidth(250);
         menuwin.setHeight(150);
         menuwin.setShowMinimize(false);
         menuwin.setShowMaximize(false);
         menuwin.setShowClose(false);

         var menuwinlayout = new qx.ui.layout.VBox();
         menuwin.setLayout(menuwinlayout); */

         this.loginwin = new qx.ui.window.Window("ADBGUI Login");
         this.loginwin.setWidth(300);
         //this.loginwin.setHeight(150);
         this.loginwin.setShowMinimize(false);
         this.loginwin.setShowMaximize(false);
         this.loginwin.setShowClose(true);
         
         this.loginwin.layout = new qx.ui.layout.VBox();
         this.loginwin.setLayout(this.loginwin.layout);
         
         this.loginwin.usernamelabel = new qx.ui.basic.Label("Benutzername:");
         this.loginwin.add(this.loginwin.usernamelabel);
         
         this.loginwin.username = new qx.ui.form.TextField("");
         this.loginwin.username.setNativeContextMenu(true);
         this.loginwin.add(this.loginwin.username);

         this.loginwin.passwordlabel = new qx.ui.basic.Label("Passwort:");
         this.loginwin.add(this.loginwin.passwordlabel);
         
         this.loginwin.password = new qx.ui.form.PasswordField("");
         this.loginwin.password.setNativeContextMenu(true);
         this.loginwin.add(this.loginwin.password);
         
         this.loginwin.nothing = new qx.ui.basic.Label("");
         this.loginwin.add(this.loginwin.nothing);
         
         this.loginwin.button = new qx.ui.form.Button();
         
         this.resetButton = function(action) {
            this.loginwin.button.setEnabled(action);
            this.loginwin.password.setEnabled(action);
            this.loginwin.passwordlabel.setEnabled(action);
            if (action) {
               this.loginwin.password.setValue("");
            }
            this.loginwin.username.setEnabled(action);
            this.loginwin.usernamelabel.setEnabled(action);
         }
         this.loginwin.loginhandler = function(e) {
            this.sendRequest("job=auth,user=" + this.loginwin.username.getValue() + ",pass=" + this.loginwin.password.getValue());
            this.resetButton(false);
         };
         this.loginwin.keyhandler = function(e) {
            if (e.getKeyIdentifier() == 'Enter') {
               this.sendRequest("job=auth,user=" + this.loginwin.username.getValue() + ",pass=" + this.loginwin.password.getValue());
               this.resetButton(false);
            }
         };
         this.loginwin.button.addListener("execute", this.loginwin.loginhandler, this)
         this.loginwin.addListener("keydown", this.loginwin.keyhandler, this);
         this.loginwin.button.setLabel("Login");
         this.loginwin.button.setFont(qx.bom.Font.fromString("24px serif bold"));
         this.loginwin.add(this.loginwin.button);
         
         this.root.addListener("resize", function(e) {
            this.loginwin.center();
         }, this);
         
         this.desktop.add(this.loginwin);

         /////////////////////////////// LoginWindow End

         function get_url_parameter( param ) {
            param = param.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]");
            var r1 = "[\\?&]"+param+"=([^&#]*)";
            var r2 = new RegExp( r1 );
            var r3 = r2.exec( window.location.href );
            if( r3 == null ) { return ""; } else { return r3[1]; }
         }
     
         this.handleRequestEvent = function (eventtext) {
            this.running--;
            if (eventtext != "") {
               this.debug(eventtext + "ID: " + this.running.toString());
            }
            if (this.running == 0) {
               var param = "job=poll";
               if (get_url_parameter("job") != '') {
                  param += ",phpjob=" + escape(get_url_parameter("job"));
               }
               if (get_url_parameter("phpid") != '') {
                  param += ",phpid=" + escape(get_url_parameter("phpid"));
               }
               if (get_url_parameter("id") != '') {
                  param += ",id=" + escape(get_url_parameter("id"));
               }
               this.sendRequest(param, 1);
            } else {
               this.debug("The ID is: " + this.running.toString() + ":" + this);
            }
         }

         this.unRegisterAndClose = function (myself) {
            this.debug("GotFire: " + myself.id);
            if (typeof(myself.assignedTo) != 'undefined') {
               this.debug("Removed myself from parent " + myself.assignedTo.id);
               if (!(myself.fireDataEvent('delobject', myself.assignedTo.id))) {
                  this.debug(myself.assignedTo.id + " has no delobject!");
               }
               myself.assignedTo.remove(myself);
               myself.assignedTo.childs.removeItem(myself.id);
               delete myself.assignedTo;
            }
            if (typeof(myself.childs) != 'undefined') {
               if (myself.childs.length > 0) {
                  var j = 0;
                  for (var i in myself.childs.items) {
                     if (myself.childs.hasItem(i) && (typeof(myself.childs.items[i]) == 'object')) {
                        this.debug("Fireing: " + i);
                        this.unRegisterAndClose(myself.childs.items[i]);
                     }
                  }
               }
            }
            this.objects.removeItem(myself.id);
            myself.destroy();
         }

         this.canClose = function (myself, tree) {
            if ((typeof(myself.canClose) != 'undefined') && myself.canClose(myself, tree)) {
               this.debug("canClose: Blocked by " + myself.id);
               return 1;
            }
            tree.push(myself);
            if (typeof(myself.childs) != 'undefined') {
               if (myself.childs.length > 0) {
                  var j = 0;
                  for (var i in myself.childs.items) {
                     if (myself.childs.hasItem(i) && (typeof(myself.childs.items[i]) == 'object')) {
                        var tmp = this.canClose(myself.childs.items[i], tree);
                        if (tmp) {
                           //this.debug("canClose:        via " + myself.id);
                           tree.pop();
                           return 1;
                        }
                     }
                  }
               }
            }
            tree.pop();
            return 0;
         }

         this.createMenu = function() {
            this.menuscroller = new qx.ui.container.Scroll().set({
               allowGrowX: true,
               allowGrowY: true,
               allowShrinkX: true,
               allowShrinkY: false,
               width: 1,
               height: 52
            });
            this.menuroot = new qx.ui.container.Composite(new qx.ui.layout.HBox).set({
               allowGrowX: true,
               allowGrowY: true,
               allowShrinkX: true,
               allowShrinkY: false,
               height: 50,
               width: 1
            });
            this.menuscroller.add(this.menuroot);
            this.root.add(this.menuscroller);
         }

         this.sendRequest = function(runcmd, polling) {
            var req = new qx.io.remote.Request("/ajax", "POST", "text/plain");
            var params = runcmd.split(",");
            var param;
            while (param = params.shift()) {
               var tmp = param.split("=");
               var paramkey = tmp.shift();
               var paramval = tmp.join("=");
               req.setParameter(paramkey, paramval, true);
            }
            //this.debug("type is: " + this);
            //this.debug("randon muber is: " + this.randomnumber.toString());
            req.setParameter("sessionid", this.randomnumber, true);
            req.setTimeout(120000);
            if (polling) {
               this.running++;
               req.addListener("completed", function(e) {
                  var commands = e.getContent();
                  if (commands == "") {
                  } else {
                     this.processCommands(commands);
                  }
                  this.handleRequestEvent("");
               }, this);
               req.addListener("failed",  function (e) { var _this = this; window.setTimeout(function () { _this.handleRequestEvent(""); }, 1000, this); }, this);
               req.addListener("timeout", function (e) { var _this = this; window.setTimeout(function () { _this.handleRequestEvent(""); }, 1000, this); }, this);
               req.addListener("aborted", function (e) { var _this = this; window.setTimeout(function () { _this.handleRequestEvent(""); }, 1000, this); }, this);
            } else {
               req.addListener("failed", function () {
                  this.processCommands("reset"); 
                  //this.debug("onlySend: failed");
               }, this);
               req.addListener("timeout", function () {
                  this.debug("onlySend: timeout");
               }, this);
               req.addListener("aborted", function () {
                  this.debug("onlySend: aborted");
               }, this);
               req.addListener("completed", function(e) {
                  //this.debug(e.getContent());
                  this.debug("OnlySend: Done");
               }, this);
            }
            req.send();
         }
         
         this.handleRequestEvent("");
         
         this.onEntryChanged = function(table, id) {
            this.debug("onEntryChanged " + table + ':' + id);
            if (this.tablelisteners.hasItem(table)) {
               var objects = this.tablelisteners.getItem(table);
               for (var loop = 0; loop < objects.length; loop++) {
                  var params = new Hash();
                  params.setItem("table", table);
                  params.setItem("id", id);
                  objects[loop].fireDataEvent('reloadData', params);
               }
            }
         }
         
         this.processCommands = function(commands, action, actionparent) {
            var curcmdarray = commands.split("\n");
            var curcmd;
            while (typeof(curcmd = curcmdarray.shift()) != 'undefined') {
               this.processing++;
               var cmdparam = curcmd.split(" ");
               var cmd = cmdparam.shift().toLowerCase();
               var json;
               if (cmd == "json") {
                  var tmp = unescape(cmdparam.shift());
                  json = eval("(" + tmp + ")");
                  //this.debug("JSONFOUND: " + tmp + ":" + json);
                  cmd = json.job;
               } else {
                  json = undefined;
               }
               if (cmd == "showloginwin") {
                  this.loginwin.setCaption(unescape(cmdparam.shift()));
                  this.resetButton(true);
                  this.loginwin.open();
                  var username = cmdparam.shift();
                  if (typeof(username) != 'undefined') {
                     this.loginwin.username.setValue(unescape(username));
                     this.loginwin.password.focus();
                     this.loginwin.password.activate();
                  } else {
                     this.loginwin.username.focus();
                     this.loginwin.username.activate();
                  }
                  // TODO:XXX:FIXME: Alle bereits offenene Fenster zu machen... oder updaten...
               } else if (cmd == "closeloginwin") {
                  this.loginwin.close();
               } else if (cmd == "reset") {
                  this.loginwin.close();
                  for (var id in this.objects.items) {
                     if (typeof(this.objects.getItem(id)) == "object") {
                        this.unRegisterAndClose(this.objects.getItem(id));
                     }
                  }
                  if (typeof(this.menuscroller) != 'undefined') {
                     this.menuscroller.remove(this.menuroot);
                     this.menuroot.destroy();
                     delete this.menuroot;
                     this.root.remove(this.menuscroller);
                     this.menuscroller.destroy();
                     delete this.menuscroller;
                  }
               } else if (cmd == "resetmenu") {
                  if (typeof(this.menuscroller) != 'undefined') {
                     this.menuscroller.remove(this.menuroot);
                     this.menuroot.destroy();
                     delete this.menuroot;
                     this.root.remove(this.menuscroller);
                     this.menuscroller.destroy();
                     delete this.menuscroller;
                  }
               } else if (cmd == "dumpids") {
                  for (var obj in this.objects.items) {
                     this.debug("Name: " + obj);
                  }
                  this.debug("Anzahl Objekte: " + this.objects.length);


                     /////////////
                     // Windows //
                     /////////////

               } else if (cmd == "createwin") {
                  var id = unescape(cmdparam.shift());
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATEWIN: Object already existing: " + id);
                  } else {
                     var width = parseInt(cmdparam.shift(), 10);
                     var height = parseInt(cmdparam.shift(), 10);
                     var title = unescape(cmdparam.shift());
                     var image = unescape(cmdparam.shift());
                     //var layout = unescape(cmdparam.shift());
                     if (this.objects.hasItem(id)) {
                        this.debug("CREATEWIN: Object already existing: " + id);
                     } else {
                        var mywindow = new qx.ui.window.Window(title, image).set({
                           width: width,
                           height: height,
                           contentPadding : [ 0, 0, 0, 0 ]
                        });
                        mywindow.id = id;
                        mywindow.main = this;
                        mywindow.setShowMinimize(false);
                        //var mylayout;
                        //if (layout == "hbox") {
                        //   mylayout = new qx.ui.layout.HBox();
                        //} else {
                        //   mylayout = new qx.ui.layout.VBox();
                        //}
                        mywindow.setLayout(new qx.ui.layout.VBox());
                        mywindow.addListener("close", function() {
                           this.main.unRegisterAndClose(this);
                        }, mywindow);
                        mywindow.addListener("beforeClose", function(e) {
                           var tmp = new Array();
                           if (this.main.canClose(this, tmp)) {
                              e.preventDefault();
                              this.main.debug("beforeClose: prevented Close");
                           }
                        }, mywindow);
                        mywindow.childs = new Hash();
                        this.objects.setItem(mywindow.id, mywindow);
                        this.desktop.add(mywindow);
                     }
                  }
               } else if (cmd == "show") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id     = unescape(cmdparam.shift());
                     json.open   = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     if (json.open != "") {
                        this.objects.getItem(json.id).show();
                     }
                  } else {
                     this.debug("SHOW: Object not found: " + json.id);
                  }
               } else if (cmd == "open") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id     = unescape(cmdparam.shift());
                     json.open   = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     if (json.open != "") {
                        this.objects.getItem(json.id).open();
                        this.objects.getItem(json.id).center();
                     } else {
                        this.objects.getItem(json.id).close();
                     }
                  } else {
                     this.debug("OPEN: Object not found: " + json.id);
                  }
               } else if (cmd == "maximize") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     if (cmdparam.shift() != "") {
                        this.objects.getItem(id).maximize();
                     } else {
                        this.objects.getItem(id).restore();
                     }
                  } else {
                     this.debug("MAXIMIZE: Object not found: " + id);
                  }
               } else if (cmd == "modal") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     this.objects.getItem(id).setModal(cmdparam.shift() != "");
                  } else {
                     this.debug("MODAL: Object not found: " + id);
                  }
               } else if (cmd == "delobject") {
                  var id = cmdparam.shift();
                  var dstid = cmdparam.shift();
                  if ((this.objects.hasItem(id)) &&
                      (this.objects.hasItem(dstid))) {
                     if (this.objects.getItem(id).childs.hasItem(dstid)) {
                        var item = this.objects.getItem(id);
                        var dstitem = this.objects.getItem(dstid);
                        if (!(dstitem.fireDataEvent('delobject', id))) {
                           this.debug(id + " has no delobject!");
                        }
                        item.remove(dstitem); 
                        item.childs.removeItem(dstid);
                        delete dstitem.assignedTo;
                     } else {
                        this.debug("DELOBJECT: Object " + dstid + " is not a child of " + id + "!");
                     }
                  } else {
                     if (!(this.objects.hasItem(id))) {
                        this.debug("DELOBJECT: Object not existing: " + id);
                     }
                     if (!(this.objects.hasItem(dstid))) {
                        this.debug("DELOBJECT: Subobject not existing: " + dstid);
                     }
                  }
               } else if (cmd == "destroy") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     this.unRegisterAndClose(this.objects.getItem(json.id));
                  } else {
                     this.debug("DESTROY: Object not existing: " + json.id);
                  }
               } else if (cmd == "unlock") {
                  var id = cmdparam.shift();
                  if (!(this.objects.getItem(id).fireDataEvent('unlock', this.objects.getItem(id)))) {
                     this.debug(id + " has no unlock event!");
                  }
               } else if (cmd == "setactive") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     item.setEnabled(cmdparam.shift() != '');
                  } else {
                     this.debug("ADDOBJECT: Object not existing: " + id);
                  }
               } else if (cmd == "addobject") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id               = unescape(cmdparam.shift());
                     json.to               = unescape(cmdparam.shift());
                     json.insertbeforeitem = unescape(cmdparam.shift());
                     json.overrideflex     = unescape(cmdparam.shift());
                  }
                  var myobj;
                  if (json.id == 'desktop') {
                     myobj = this.desktop;
                  } else {
                     if (this.objects.hasItem(json.id)) {
                        myobj = this.objects.getItem(json.id);
                     }
                  }
                  if (myobj &&
                               (this.objects.hasItem(json.to))) {
                     if (typeof(this.objects.getItem(json.to).assignedTo) != 'undefined') {
                       this.debug("ADDOBJECT: The object " +  json.id + " is already assigned to " + this.objects.getItem(json.to).assignedTo.id + "! Aborting!");
                     } else {
                        var item = myobj;
                        var dstitem = this.objects.getItem(json.to);
                        var insertbeforeitem = this.objects.getItem(json.insertbeforeitem);
                        if (json.id != 'desktop') {
                           if (!(dstitem.fireDataEvent('addobject', json.id))) {
                              this.debug(json.id + " has no addobject!");
                           }
                        }
                        dstitem.assignedTo = item;
                        var myflex = dstitem.flex;
                        if (json.overrideflex == 'noflex') {
                           myflex = 0;
                        } else if (json.overrideflex == 'flex') {
                           myflex = 1;
                        }
                        if (typeof(insertbeforeitem) != 'undefined') {
                           item.addBefore(dstitem, insertbeforeitem, {flex: myflex});
                        } else {
                           item.add(dstitem, {flex: myflex});
                        }
                        item.childs.setItem(json.to, dstitem);
                        dstitem.assignedTo = item;
                     }
                  } else {
                     if (!(this.objects.hasItem(json.id))) {
                        this.debug("ADDOBJECT: Object not existing: " + json.id);
                     }
                     if (!(this.objects.hasItem(json.to))) {
                        this.debug("ADDOBJECT: Subobject not existing: " + json.to);
                     }
                  }
               } else if (cmd == "cleareditlist") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var dbname = unescape(cmdparam.shift());
                     if (typeof(item.formular) != 'undefined') {
                        if (typeof(item.form[dbname]) != 'undefined') {
                           item.form[dbname].removeAll();
                        } else {
                           this.debug("CLEAREDITLIST: Column " + dbname + " on form " + id + " not found!");
                        }
                     } else {
                        this.debug("CLEAREDITLIST: Object " + id + " is without form element!");
                     }
                  } else {
                     this.debug("CLEAREDITLIST: Object not existing: " + id);
                  }
               } else if (cmd == "selectoneditlist") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var dbname = unescape(cmdparam.shift());
                     if (typeof(item.formular) != 'undefined') {
                        if (typeof(item.form[dbname]) != 'undefined') {
                           var listid = unescape(cmdparam.shift());
                           item.form[dbname].selected = listid;
                           var curitems = item.form[dbname].getSelectables(true);
                           for (var i = 0; i < curitems.length; ++i) {
                           //for (var mylistitem in item.form[dbname].getSelectables(true)) { kkk
                              var mylistitem = curitems[i];
                              //this.debug("PRE:" + mylistitem + ";" + typeof(mylistitem) + ";ID=" + mylistitem.id);
                              if (mylistitem && (typeof(mylistitem) == 'object') && (mylistitem.id == listid)) {
                                 item.form[dbname].setSelection([mylistitem]);
                              } else {
                                 this.debug("BAD:" + mylistitem + ";" + typeof(mylistitem));
                              }
                           }
                        } else {
                           this.debug("SELECTONEDITLIST: Column " + dbname + " on form " + id + " not found!");
                        }
                     } else {
                        this.debug("SELECTONEDITLIST: Object " + id + " is without form element!");
                     }
                  } else {
                     this.debug("SELECTONEDITLIST: Object not existing: " + id);
                  }
               } else if (cmd == "addtoeditlist") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var dbname = unescape(cmdparam.shift());
                     if (typeof(item.formular) != 'undefined') {
                        if (typeof(item.form[dbname]) != 'undefined') {
                           var curitems = item.form[dbname].getSelectables(true);
                           var mylistitem = undefined;
                           var text = unescape(cmdparam.shift());
                           var listid = unescape(cmdparam.shift());
                           for (var i = 0; i < curitems.length; ++i) {
                           //for (var mylistitem in item.form[dbname].getSelectables(true)) { kkk
                              var curmylistitem = curitems[i];
                              //this.debug("PRE:" + curmylistitem + ";" + typeof(curmylistitem) + ";ID=" + curmylistitem.id);
                              if (curmylistitem && (typeof(curmylistitem) == 'object') && (curmylistitem.id == listid)) {
                                 mylistitem = curmylistitem;
                                 break;
                              }
                           }
                           if (typeof(mylistitem) != 'object') {
                              mylistitem = new qx.ui.form.ListItem(text);
                              mylistitem.setNativeContextMenu(true);
                              mylistitem.setModel(listid);
                              mylistitem.id = listid;
                              item.form[dbname].add(mylistitem);
                           }
                           mylistitem.setLabel(text);
                           if (item.form[dbname].selected == mylistitem.id) {
                              if (typeof((item.form[dbname].getSelection())[0]) == 'object') {
                                 if (((item.form[dbname].getSelection())[0]).id != mylistitem.id) {
                                    this.debug("changed " + item.form[dbname] + " " + id + " " + item.form[dbname].firstTouch + "->" + (item.form[dbname].firstTouch-1) + " addtoeditlist");
                                    item.form[dbname].firstTouch--;
                                    item.form[dbname].setSelection([mylistitem]);
                                 } 
                              }
                           }
                        } else {
                           this.debug("ADDTOEDITLIST: Column " + dbname + " on form " + id + " not found!");
                        }
                     } else {
                        this.debug("ADDTOEDITLIST: Object " + id + " is without form element!");
                     }
                  } else {
                     this.debug("ADDTOEDITLIST: Object not existing: " + id);
                  }
               } else if (cmd == "addtab") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var newid = unescape(cmdparam.shift());
                     if (this.objects.hasItem(newid)) {
                        this.debug("ADDTAB: Object already existing: " + id);
                     } else {
                        var newtab = new myproject.myTabViewPage(unescape(cmdparam.shift()));
                        newtab.setLayout(new qx.ui.layout.VBox());
                        newtab.childs = new Hash();
                        newtab.id = newid;
                        newtab.main = this;
                        item.childs.setItem(newtab.id, newtab);
                        this.objects.setItem(newtab.id, newtab);
                        this.processCommands("addobject " + id + " " + newid);
                     }
                  } else {
                     this.debug("ADDTAB: Object not existing: " + id);
                  }
               } else if (cmd == "createtabview") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATETABVIEW: Object already existing: " + id);
                  } else {
                     var align = cmdparam.shift();
                     var tabview = new qx.ui.tabview.TabView();
                     tabview.flex = 1;
                     tabview.setContentPadding(0, 0, 0, 0);
                     tabview.childs = new Hash();
                     if (align) {
                        tabview.setBarPosition(align);
                     };
                     tabview.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        //item.setContentPadding(10, 10, 10, 10);
                     });
                     tabview.id = id;
                     tabview.main = this;
                     this.objects.setItem(tabview.id, tabview);
                     //if (typeof(cmdparam.shift()) != 'undefined') {
                     //   this.debug("WARNING: You have to migrate your createtabview with id '" + id + "'");
                     //}
                  }
               } else if (cmd == "createtree") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     this.debug("ADDTEXTEDIT: Object already existing: " + id);
                  } else {
                     var tree = new myproject.myTree();
                     tree.flex = 1;
                     tree.id = id;
                     tree.main = this;
                     //tree.setHideRoot(1);
                     var root = new qx.ui.tree.TreeFolder(unescape(cmdparam.shift()));
                     tree.urlappend = unescape(cmdparam.shift());
                     tree.elements = new Hash();
                     tree.entries = new Hash();
                     tree.elements.setItem("", root);
                     root.entries = new Hash();
                     root.elements = new Hash();
                     root.setOpen(true);
                     tree.setRoot(root);
                     this.objects.setItem(tree.id, tree);
                     tree.addListener("delobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        dstitem.resetRoot();
                        this.main.processCommands("deltreefolder " + escape(dstid) + " ");
                        delete dstitem.elements;
                        delete dstitem.entries;
                     });
                     tree.addListener("changeSelection", function(e) {
                        var data = e.getData();
                        if (data.length > 0) {
                           //this.debug(data[0].id + "/" + data[0].getLabel() + "/" + data[0].getTree().id);
                           this.main.sendRequest("job=treechange,oid=" + escape(this.id) + ",id=" + escape(data[0].id) + ",entry=" + ((typeof(data[0].entries) == 'undefined') ? 1 : 0) + this.urlappend);
                        }
                     });
                  }
               } else if (cmd == "addtreefolder") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var parentid = unescape(cmdparam.shift());
                     // TODO:FIXME:XXX: Es sollte ueberprueft werden ob das ein createtree ist.
                     if (item.elements.hasItem(parentid)) {
                        var parent = item.elements.getItem(parentid);
                        var folderid = unescape(cmdparam.shift());
                        if (item.elements.hasItem(folderid) ||
                          parent.elements.hasItem(folderid)) {
                           this.debug("ADDTREEFOLDER: Folder " + folderid + " already exists.");
                        } else {
                           var folder = new qx.ui.tree.TreeFolder(unescape(cmdparam.shift()));
                           folder.elements = new Hash();
                           folder.entries = new Hash();
                           folder.id = folderid;
                           //if (parentid == "") {
                           //   folder.setOpen(true);
                           //}
                           parent.add(folder);
                           folder.parent = parent;
                           parent.elements.setItem(folderid, folder);
                           item.elements.setItem(folderid, folder);
                        }
                     } else {
                        this.debug("ADDTREEFOLDER: Object " + id + " is without form element!");
                     }
                  } else {
                     this.debug("ADDTREEFOLDER: Object not existing: " + id);
                  }
               } else if (cmd == "addtreeentry") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id       = unescape(cmdparam.shift());
                     json.parentid = unescape(cmdparam.shift());
                     json.entryid  = unescape(cmdparam.shift());
                     json.label    = unescape(cmdparam.shift());
                     json.icon     = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     var item = this.objects.getItem(json.id);
                     if (item.elements.hasItem(json.parentid)) {
                        var parent = item.elements.getItem(json.parentid);
                        if (item.entries.hasItem(json.entryid) ||
                          parent.entries.hasItem(json.entryid)) {
                           this.debug("ADDTREEENTRY: Entry " + json.entryid + " already exists.");
                        } else {
                           var entry = new qx.ui.tree.TreeFile(json.label);
                           if ((typeof(json.icon) != 'undefined') && (json.icon != "undefined") && (json.icon != "")) entry.setIcon(json.icon);
                           //alert(json.icon);
                           parent.add(entry);
                           entry.id = json.entryid;
                           parent.entries.setItem(json.entryid, entry);
                           item.entries.setItem(json.entryid, entry);
                        }
                     } else {
                        this.debug("ADDTREEENTRY: Object " + id + " is without form element!");
                     }
                  } else {
                     this.debug("ADDTREEENTRY: Object not existing: " + id);
                  }
               } else if (cmd == "deltreeentry") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var folderid = unescape(cmdparam.shift());
                     if (item.elements.hasItem(folderid)) {
                        var parent = item.elements.getItem(folderid);
                        var entryid = unescape(cmdparam.shift());
                        if (parent.entries.hasItem(entryid)) {
                           var entry = parent.entries.getItem(entryid);
                           parent.remove(entry);
                           parent.entries.removeItem(entryid);
                           item.entries.removeItem(entryid);
                           entry.destroy();
                        } else {
                           this.debug("DELTREEENTRY: Entry " + entryid + " not existing!");
                        }	
                     } else {
                        this.debug("DELTREEENTRY: Folder " + folderid + " not existing!");
                     }	
                  } else {
                     this.debug("DELTREEENTRY: Object not existing: " + id);
                  }
               } else if (cmd == "deltreefolder") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var folderid = unescape(cmdparam.shift());
                     if (item.elements.hasItem(folderid)) {
                        var folder = item.elements.getItem(folderid);
                        for (var j in folder.entries.items) {
                           if (folder.entries.hasItem(j) && (typeof(folder.entries.items[j]) == 'object')) {
                              var entry = folder.entries.items[j];
                              //this.debug("Destroying ENTRY '" + j + "' in FOLDER '" + folderid + "'");
                              folder.remove(entry);
                              item.entries.removeItem(j);
                              entry.destroy();
                           }
                        }
                        delete folder.entries;
                        for (var j in folder.elements.items) {
                           if (folder.elements.hasItem(j) && (typeof(folder.elements.items[j]) == 'object')) {
                              var subfolder = folder.elements.items[j];
                              //this.debug("Requesting destroy of SUBFOLDER '" + j + "' in FOLDER '" + folderid + "'");
                              folder.remove(subfolder);
                              this.processCommands("deltreefolder " + escape(id) + " " + escape(j));
                           }
                        }
                        delete folder.elements;
                        //this.debug("Destroying FOLDER '" + folderid + "'");
                        folder.destroy();
                     } else {
                        this.debug("DELTREEFOLDER: Folder " + folderid + " not existing!");
                     }
                  } else {
                     this.debug("DELTREEFOLDER: Object not existing: " + id);
                  }
               } else if ((cmd == "iframewrite") ||
                          (cmd == "iframewritereset") ||
                          (cmd == "iframewriteclose")) {
                  var command = cmd + " " + cmdparam.join(" ");
                  var id = cmdparam.shift();
                  //this.debug("IFRAMEWRITE: Handling: " + id);
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var text = cmdparam.shift();
                     var dst = unescape(cmdparam.shift());
                     var doc = item.getDocument();
                     if ((typeof(doc) != 'undefined') &&
                                (doc  != null)) {
                        var tmp = doc;
                        if (cmd == "iframewritereset") {
                           tmp = doc.open("text/html; charset=utf8");
                           if ((typeof(tmp) == 'undefined') ||
                                      (tmp  == null)) {
                              doc.close();
                              tmp = doc.open("text/html; charset=utf8");
                           }
                        }
                        if ((typeof(tmp) != 'undefined') &&
                                   (tmp  != null)) {
                           if ((typeof(text) != 'undefined') &&
                                      (text  != null)) {
                              tmp.write(unescape(text));
                           }
                           if (cmd == "iframewriteclose") {
                              tmp.close();
                           }
                        } else {
                           this.debug("ERROR: iframe document object: Not ready!");
                        }
                     } else {
                        // TODO:XXX:FIXME: Potentieller Endlosloop!
                        this.debug("IFRAMEWRITE: Waiting for iframe " + id + " to get ready");
                        var _this = this;
                        var curCommand = command;
                        window.setTimeout(function () { _this.processCommands(curCommand); }, 100, this);
                     }
                  } else {
                     this.debug("IFRAMEWRITE: Object not found: " + id);
                  }
               } else if (cmd == "createiframe") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id     = unescape(cmdparam.shift());
                     json.url    = unescape(cmdparam.shift());
                     json.option = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     this.debug("CREATEIFRAME: Object already existing: " + json.id);
                  } else {
                     var iframe = new myproject.myIframe().set({
                        width: 0,
                        height: 0,
                        //minWidth: 200,
                        //minHeight: 150,
                        source: json.url,
                        decorator: null,
                        nativeContextMenu: true
                     });
                     if (json.option == "maxsize") {
                        iframe.set({
                           width: 3000,
                           height: 3000,
                           minWidth: 200,
                           minHeight: 150
                        });
                     }
                     iframe.flex = 1;
                     iframe.id = json.id;
                     iframe.main = this;
                     this.objects.setItem(iframe.id, iframe);
                  }
               } else if ((cmd == "createtextedit") ||
                          (cmd == "createhtmltextedit")) {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     this.debug("ADDTEXTEDIT: Object already existing: " + id);
                  } else {
                     var table = unescape(cmdparam.shift());
                     var columnname = unescape(cmdparam.shift());
                     var forid = unescape(cmdparam.shift());
                     var textarea = new myproject.myTextArea(unescape(cmdparam.shift()).replace(/\&lt;/g, "<"));
                     textarea.infotext = unescape(cmdparam.shift());
                     textarea.flex = 1;
                     textarea.autoSize = true;
                     if (cmd == "createhtmltextedit") {
                        textarea.htmloption = 1;
                     } else {
                        textarea.htmloption = 0;
                     }
                     textarea.table = table;
                     textarea.lockable = new Array();
                     textarea.columnname = columnname;
                     textarea.forid = forid;
                     textarea.main = this;
                     textarea.addListener("unlock", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        dstitem.setEnabled(true);
                        for (var i = 0; i < this.lockable.length; ++i) {
                           this.main.processCommands("setactive " + this.lockable[i] + " 1");
                        }
                        this.main.processCommands("setactive " + this.id + " 1");
                     }, textarea);
                     textarea.setNativeContextMenu(true);
                     // TODO:FIXME:XXX: Spellcheck geht noch nicht!
                     textarea.getContentElement().setAttribute("spellcheck", "true");

                     textarea.changed = 0;
                     textarea.canClose = this.canCloseForm;
                     if ((typeof(textarea.setLiveUpdate) != 'undefined')) {
                        textarea.setLiveUpdate(true);
                     }
                     textarea.addListener("changeValue", function(e) {
                        this.changed += 1;
                        this.main.debug("changed " + this.id);
                     }, textarea);
                     
                     textarea.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        this.main.processCommands("createtoolbar " + dstid + "_toolbar");
                        this.main.processCommands("addobject " + id + " " + dstid + "_toolbar");
                        this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_speichern Speichern resource/qx/icon/Tango/32/actions/document-save.png", function(e) {
                           for (var i = 0; i < this.lockable.length; ++i) {
                              this.main.processCommands("setactive " + this.lockable[i] + " ");
                           }
                           this.main.processCommands("setactive " + this.id + " ");
                           this.main.sendRequest("job=saveedit,oid=" + this.id.toString() + ",id=" + this.forid + ",table=" + this.table + "," + this.columnname + "=" + escape(this.getValue()));
                           dstitem.changed = 0;
                        }, dstitem);
                        this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_speichern");
                        this.lockable.push(dstid + "_toolbar_speichern");
                        if (dstitem.htmloption == 1) {
                           this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_preview Vorschau resource/qx/icon/Tango/32/actions/system-search.png", function(e) {
                              this.main.sendRequest("job=htmlpreview,oid=" + this.id.toString() + ",id=" + this.forid + ", "+ ",table=" + this.table + ",column=" + this.columnname + ",value=" + escape(this.getValue()));
                           }, dstitem);
                           this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_preview");
                           this.lockable.push(dstid + "_toolbar_preview");
                        }
                        if (dstitem.infotext != "") {
                           this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_hilfe Hilfe resource/qx/icon/Tango/32/actions/help-faq.png", function(e) {
                              this.main.processCommands("showmessage " + escape(this.columnname) + " 600 400 " + escape(this.infotext));
                           }, dstitem);
                           this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_hilfe");
                        }
                     });
                     textarea.id = id;
                     textarea.main = this;
                     this.objects.setItem(textarea.id, textarea);
                  }
               } else if (cmd == "selectradiobutton") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id   = unescape(cmdparam.shift());
                     json.toid = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     var dstitem = this.objects.getItem(json.id);
                     if ((typeof(dstitem.groupobj) == "object")) {
                        var childs = dstitem.groupobj.getChildren();
                        for (var j = 0; j < childs.length; j++) if (childs[j].id == json.toid) dstitem.groupobj.setSelection([childs[j]]);
                     } else {
                        this.debug("SELECTRRADIOBUTTON: groupobj(" + dstitem.groupobj + ") has type: " + typeof(dstitem.groupobj));
                     }
                  } else {
                     this.debug("SELECTRRADIOBUTTON: Object not found: " + json.id);
                  }
               } else if ((cmd == "createtoolbarbutton") ||
	                       (cmd == "createbutton")) {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id     = unescape(cmdparam.shift());
                     json.label  = unescape(cmdparam.shift());
                     json.image  = unescape(cmdparam.shift());
                     json.action = unescape(cmdparam.shift());
                  }
                  if (this.objects.hasItem(json.id)) {
                     this.debug("CREATE(TOOLBAR)BUTTON: Object already existing: " + json.id);
                  } else {
                     var menu;
                     if (json.menu) {
                        menu = new qx.ui.menu.Menu;
                     }
                     var button;
                     if (cmd == "createtoolbarbutton") {
                        button = (typeof(menu) == "object") ? 
                           new myproject.myToolBarMenuButton(json.label, json.image, menu) :
                           new myproject.myToolBarButton    (json.label, json.image);
                     } else {
                        button =
                           new myproject.myButton           (json.label, json.image);
                     }
                     button.menu = menu;
                     button.json = json;
                     if (typeof(actionparent) != 'undefined') {
                        button.action = action;
                        button.actionparent = actionparent;
                     } else {
                        button.action = json.action;
                        button.urlappend = json.urlappend;
                     }
                     button.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        if (dstitem.json.menu) {
                           if (dstitem.json.menutype == "radio") dstitem.groupobj = new qx.ui.form.RadioGroup();
                           for (var j = 0; j < dstitem.json.menu.length; j++) {
                              var curbutton;
                              if (dstitem.json.menutype == "radio") {
                                 curbutton = new qx.ui.menu.RadioButton(unescape(dstitem.json.menu[j].label));
                                 curbutton.setGroup(dstitem.groupobj);
                              } else {
                                 curbutton = new qx.ui.menu.Button(unescape(dstitem.json.menu[j].label), dstitem.json.menu[j].image);
                              }
                              curbutton.action    = dstitem.json.menu[j].action;
                              curbutton.urlappend = dstitem.json.menu[j].urlappend;
                              curbutton.id        = dstitem.json.menu[j].id;
                              curbutton.parent    = dstitem;
                              //if (typeof(actionparent) != 'undefined') curbutton.actionparent = actionparent;
                              curbutton.addListener("execute", function(e) {
                                 if (typeof(curbutton.parent.actionparent) != 'undefined') {
                                    curbutton.parent.actionparent.menuaction    = this.action;
                                    curbutton.parent.actionparent.menuurlappend = this.urlappend;
                                 }
                                 curbutton.parent.fireEvent("execute");
                              }, curbutton);
                              dstitem.menu.add(curbutton);
                           }
                           if (typeof(json.selected) != 'undefined') {
                              var cmd = "JSON " + escape(JSON.stringify({
                                 job: "selectradiobutton",
                                 id: dstid,
                                 toid: json.selected
                              }));
                              this.main.debug(cmd);
                              this.main.processCommands(cmd);
                           }
                        }
                        if (dstitem.json.menutype == "popup") {
                           dstitem.addListener("execute", function(e) {
                              //this.popup = new qx.ui.popup.Popup(new qx.ui.layout.Grow);
                              //this.popup.add(new qx.ui.basic.Atom("Content: " + this.json.url));
                              //this.popup.setPadding(20);
                              //this.popup.placeToWidget(this.main.menuobjects.getItem("tabellen"));
                              //this.popup.show();
                              var cmd = "JSON " + escape(JSON.stringify({
                                 job: "destroy",
                                 id:  this.json.popupid ? this.json.popupid : this.json.id + "_popup"
                              }));
                              this.main.debug(cmd);
                              this.main.processCommands(cmd);
                              var cmd = "JSON " + escape(JSON.stringify({
                                 job: "createpopup",
                                 width: this.json.popupwidth,
                                 height: this.json.popupheight,
                                 noshow: this.json.popupnoshow,
                                 padding: this.json.popuppadding,
                                 id: this.json.popupid ? this.json.popupid : this.json.id + "_popup",
                                 parentid: this.json.id
                              }));
                              this.main.debug(cmd);
                              this.main.processCommands(cmd);
                              //var cmd = "JSON " + escape(JSON.stringify({
                              //   job: "createiframe",
                              //   url: this.json.url,
                              //   id:  this.json.popupid ? this.json.popupid + "_iframe" : this.json.id + "_popup_iframe",
                              //   parentid: this.json.id
                              //}));
                              //this.main.debug(cmd);
                              //this.main.processCommands(cmd);
                              //var cmd = "JSON " + escape(JSON.stringify({
                              //   job: "addobject",
                              //   id: this.json.popupid ? this.json.popupid : this.json.id + "_popup",
                              //   to: this.json.popupid ? this.json.popupid + "_iframe" : this.json.id + "_popup_iframe",
                              //   parentid: this.json.id
                              //}));
                              //this.main.debug(cmd);
                              //this.main.processCommands(cmd);
                              //var cmd = "JSON " + escape(JSON.stringify({
                              //   job: "show",
                              //   id:  this.json.popupid ? this.json.popupid : this.json.id + "_popup"
                              //}));
                              //this.main.debug(cmd);
                              //this.main.processCommands(cmd);
                              this.main.sendRequest(this.action);
                           }, dstitem);
                        } else if (typeof(dstitem.actionparent) != 'undefined') {
                           dstitem.addListener("execute", dstitem.action, dstitem.actionparent);
                        } else {
                           dstitem.addListener("execute", function(e) {
                              this.main.sendRequest(this.action);
                           }, dstitem);
                        }
                     });
                     button.flex = 0;
                     button.id = json.id;
                     button.main = this;
                     this.objects.setItem(button.id, button);
                  }
               } else if (cmd == "createpopup") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id  = cmdparam.shift();
                  }
                  if (this.objects.hasItem(json.id)) {
                     this.debug("CREATEPOPUP: Object already existing: " + json.id);
                  } else {
                     //this.debug("CREATEPOPUP: lalala: BEGIN: " + json.id);
                     var popup = new myproject.myPopup(new qx.ui.layout.Grow());
                     if (json.padding) popup.setPadding(json.padding);
                     popup.childs = new Hash();
                     //popup.addListener("addobject", function(e) {
                     //   var id = e.getData();
                     //   var dstid = this.id;
                     //   var item = this.main.objects.getItem(id);
                     //   var dstitem = this.main.objects.getItem(dstid);
                     //});
                     popup.placeToWidget(json.parentid ? this.objects.getItem(json.parentid) : this.loginwin);
                     if (json.width && json.width) popup.set({width: json.width, height: json.height});
                     popup.id = json.id;
                     popup.main = this;
                     if (!json.noshow) popup.show();
                     this.objects.setItem(popup.id, popup);
                     //this.debug("CREATEPOPUP: lalala: END: " + json.id);
                  }
               } else if (cmd == "createtoolbar") {
                  if (typeof(json) != "object") {
                     json = new Object();
                     json.id = cmdparam.shift();
                  }
                  if (this.objects.hasItem(json.id)) {
                     this.debug("CREATETOOLBAR: Object already existing: " + json.id);
                  } else {
                     var toolbar = new myproject.myToolBar();
                     toolbar.childs = new Hash();
                     toolbar.part = new qx.ui.toolbar.Part();
                     toolbar.add(toolbar.part);
                     toolbar.addListener("delobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        dstitem.remove(dstitem.part);
                        dstitem.part.destroy();
                     });
                     toolbar.flex = 0;
                     toolbar.id = json.id;
                     toolbar.main = this;
                     this.objects.setItem(toolbar.id, toolbar);
                  }
               } else if (cmd == "createedit") {
                  var id = cmdparam.shift(); // 1
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATEEDIT: Object already existing: " + id);
                  } else {
                     var scroller = new myproject.myScroll();
                     scroller.flex = 1;
                     scroller.setContentPadding(10, 10, 10, 10);
                     scroller.setHeight(0);
                     scroller.table = unescape(cmdparam.shift()); // 2
                     scroller.columns = cmdparam.shift().split(","); // 3
                     for (var j = 0; j < scroller.columns.length; j++) {
                        scroller.columns[j] = unescape(scroller.columns[j]);
                     }
                     scroller.types = cmdparam.shift().split(","); // 4
                     scroller.dbname = cmdparam.shift().split(","); // 5
                     scroller.viewstatus = cmdparam.shift().split(","); // 6
                     scroller.values = cmdparam.shift().split(","); // 7
                     scroller.units = cmdparam.shift().split(","); // 8
                     scroller.infotext = unescape(cmdparam.shift()); // 9
                     scroller.wid = unescape(cmdparam.shift()); // 10
                     scroller.urlappend = unescape(cmdparam.shift()); // 11
                     scroller.label = new Array();
                     scroller.unit = new Array();
                     scroller.lockable = new Array();
                     scroller.childs = new Hash();
                     scroller.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        this.main.processCommands("createtoolbar " + dstid + "_toolbar");
                        dstitem.formular = new qx.ui.container.Composite().set({
                           //decorator: "main",
                           //backgroundColor: "black",
                           width:100,
                           allowShrinkX: true,
                           allowShrinkY: true,
                           allowGrowX: true,
                           allowGrowY: false
                        });
                        dstitem.changed = 0;
                        dstitem.canClose = this.main.canCloseForm;
                        dstitem.layout = new qx.ui.layout.Grid(5, 5);
                        dstitem.layout.setColumnFlex(1, 2);
                        //layout.setRowFlex(1, 3);
                        dstitem.layout.setColumnMinWidth(0,70);
                        dstitem.layout.setColumnMinWidth(1,100);
                        dstitem.layout.setColumnMaxWidth(2,150);
                        //dstitem.layout.setRowMinHeight(0,70);
                        //dstitem.layout.setSpacing(5);
                        dstitem.formular.setLayout(dstitem.layout);

                        dstitem.groupBox = new qx.ui.groupbox.GroupBox().set({allowGrowY: false});
                        dstitem.groupBox.setContentPadding(10, 10, 10, 10);
                        dstitem.groupBox.setLayout(new qx.ui.layout.Grow());
                        
                        dstitem.groupBox.add(dstitem.formular);
                        dstitem.add(dstitem.groupBox);
                        
                        dstitem.form = new Array();
                        dstitem.buttonnew = new Array();
                        dstitem.buttonedit = new Array();
                        var x = 0;
                        var linenum = 0;
                        for (var j = 0; j < dstitem.columns.length; j++) {
                           if (dstitem.types[j] == "id") {
                              dstitem.rowid = unescape(dstitem.values[j]);
                           }
                           if (dstitem.types[j] == "composite") {
                              /* dstitem.form[dstitem.dbname[j]] = new myproject.myIframe().set({
                                 width: 0,
                                 height: 0,
                                 //minWidth: 200,
                                 minHeight: 150,
                                 //source: unescape(dstitem.values[j]),
                                 source: "http://www.priv.de/",
                                 decorator: null,
                                 nativeContextMenu: true
                              });
                              //if (option == "maxsize") { 
                              //   dstitem.form[dstitem.dbname[j]].set({
                              //      width: 3000,
                              //      height: 3000,
                              //      minWidth: 200,
                              //      minHeight: 150
                              //   });
                              //} 
                              dstitem.form[dstitem.dbname[j]].flex = 1; */
                              
                              dstitem.form[dstitem.dbname[j]] = new qx.ui.container.Composite().set({
                                 //decorator: "main",
                                 //backgroundColor: "black",
                                 width:100,
                                 height: 150, // TODO:XXX:FIXME: Die Breite sollte von remote konfigurierbar sein!
                                 allowShrinkX: true,
                                 allowShrinkY: true,
                                 allowGrowX: true,
                                 allowGrowY: false
                              });
                              dstitem.form[dstitem.dbname[j]].layout = new qx.ui.layout.VBox();
                              dstitem.form[dstitem.dbname[j]].setLayout(dstitem.form[dstitem.dbname[j]].layout);
                              
                              // dstitem.form[dstitem.dbname[j]].add(new qx.ui.form.DateField()); //, {row: 1, column: 1});
                              // dstitem.form[dstitem.dbname[j]].add(new qx.ui.form.DateField()); //, {row: 1, column: 1});
                              // dstitem.form[dstitem.dbname[j]].add(new qx.ui.form.DateField()); //, {row: 1, column: 1});
                              
                              dstitem.form[dstitem.dbname[j]].childs = new Hash();
                              dstitem.form[dstitem.dbname[j]].id = id + "_" + dstitem.dbname[j];
                              dstitem.form[dstitem.dbname[j]].main = this.main;
                              this.childs.setItem(dstitem.form[dstitem.dbname[j]].id, dstitem.form[dstitem.dbname[j]]);
                              this.main.objects.setItem(dstitem.form[dstitem.dbname[j]].id, dstitem.form[dstitem.dbname[j]]);
                           } else if (dstitem.types[j] == "html") {
                              dstitem.form[dstitem.dbname[j]] = new qx.ui.basic.Label(unescape(dstitem.values[j]));
                              dstitem.form[dstitem.dbname[j]].set({
                                 rich : true
                              });
                           } else if (dstitem.viewstatus[j] == "readonly") {
                              dstitem.form[dstitem.dbname[j]] = new qx.ui.basic.Label(unescape(dstitem.values[j]));
                              dstitem.form[dstitem.dbname[j]].setWrap(true);
                              //dstitem.form[dstitem.dbname[j]].setRich(true);
                              //dstitem.form[dstitem.dbname[j]].setFocusable(true);
                              dstitem.form[dstitem.dbname[j]].setSelectable(true);
                           } else {
                              if ((dstitem.types[j] == "date") ||
                                  (dstitem.types[j] == "datetime")) {
                                 // yyyy-MM-dd kk:mm:ss
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.DateField();
                                 //this.debug("XXX:" + dstitem.dbname[j] + ":" + dstitem.types[j]);
                                 if (dstitem.types[j] == "datetime") {
                                    dstitem.form[dstitem.dbname[j]].setDateFormat(new qx.util.format.DateFormat("dd.MM.yyyy HH:mm"));
                                 } else {
                                    dstitem.form[dstitem.dbname[j]].setDateFormat(new qx.util.format.DateFormat("dd.MM.yyyy"));
                                 }
                                 if ((unescape(dstitem.values[j]) != "") &&
                                     (unescape(dstitem.values[j]) != "0000-00-00 0:0:0") &&
                                     (unescape(dstitem.values[j]) != "0000-00-00 00:00:00")) {
                                    var mydate = unescape(dstitem.values[j]).split(" ");
                                    if (mydate.length == 2) {
                                       var mytime = mydate[1].split(":");
                                       mydate = mydate[0].split("-");
                                       var date = new Date();
                                       if (mydate.length == 3) {
                                          //this.debug("SET DATE " + parseInt(mydate[0], 10).toString() + "." + (parseInt(mydate[1])-1, 10).toString() + "." + parseInt(mydate[2], 10).toString()) + "(" + mydate[2] + ")";
                                          date.setFullYear(parseInt(mydate[0], 10),(parseInt(mydate[1], 10)-1),parseInt(mydate[2], 10));
                                          if (mytime.length == 3) {
                                             date.setHours(parseInt(mytime[0], 10));
                                             date.setMinutes(parseInt(mytime[1], 10));
                                             date.setSeconds(parseInt(mytime[2], 10));
                                             //this.debug("SET TIME " + parseInt(mytime[0], 10).toString() + ":" + parseInt(mytime[1], 10).toString() + ":" + parseInt(mytime[2], 10).toString());
                                          }
                                          dstitem.form[dstitem.dbname[j]].setValue(date);
                                          //this.debug("SET VALUE " + unescape(dstitem.values[j]) + ":" + mytime[0] + ':' + parseInt(mytime[0], 10).toString() + ":" + mytime.length.toString());
                                       } else {
                                          this.debug("Bad value as datetime " + unescape(dstitem.values[j]));
                                       }
                                    } else {
                                       this.debug("Bad value as date " + unescape(dstitem.values[j]));
                                    }
                                 }
                              } else if (dstitem.types[j] == "double") {
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.TextField(unescape(dstitem.values[j]));
                                 dstitem.form[dstitem.dbname[j]].setTextAlign("right");
                              } else if (dstitem.types[j] == "number") {
                                 //var thenumber = 0;
                                 //if (unescape(dstitem.values[j]) != "") {
                                 //   thenumber = parseInt(unescape(dstitem.values[j]), 10);
                                 //}
                                 //if (typeof(thenumber) != 'undefined') {
                                 //   dstitem.form[dstitem.dbname[j]] = new qx.ui.form.Spinner(thenumber);tabview
                                 //} else {
                                 //   this.debug("BAD NUMBER is :" + unescape(dstitem.values[j]) + ":");
                                    dstitem.form[dstitem.dbname[j]] = new qx.ui.form.TextField(unescape(dstitem.values[j]));
                                    dstitem.form[dstitem.dbname[j]].setTextAlign("right");
                                 //}
                              } else if (dstitem.types[j] == "id") {
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.TextField(unescape(dstitem.values[j]));
                              } else if (dstitem.types[j] == "password") {
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.PasswordField(unescape(dstitem.values[j]));
                              } else if (dstitem.types[j] == "boolean") { 
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.CheckBox();
                                 dstitem.form[dstitem.dbname[j]].setValue(unescape(dstitem.values[j]) == "1");
                              } else if (dstitem.types[j] == "list") {
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.SelectBox();
                                 dstitem.form[dstitem.dbname[j]].removeListener("mousewheel", dstitem.form[dstitem.dbname[j]]._onMouseWheel, dstitem.form[dstitem.dbname[j]]); 
                                 dstitem.form[dstitem.dbname[j]].selected = unescape(dstitem.values[j]);
                              } else if (dstitem.types[j] == "textarea") {
                                 dstitem.types[j] = "text";
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.TextArea(unescape(dstitem.values[j])).set({
                                    //height: 150,
                                    autoSize: true
                                 });
                              } else {
                                 dstitem.types[j] = "text";
                                 dstitem.form[dstitem.dbname[j]] = new qx.ui.form.TextField(unescape(dstitem.values[j]));
                              }
                              dstitem.form[dstitem.dbname[j]].setNativeContextMenu(true);
                              dstitem.form[dstitem.dbname[j]].parent = dstitem;
                              if ((typeof(dstitem.form[dstitem.dbname[j]].setLiveUpdate) != 'undefined')) {
                                 dstitem.form[dstitem.dbname[j]].setLiveUpdate(true);
                              }
                              dstitem.form[dstitem.dbname[j]].firstTouch = 0;
                              dstitem.form[dstitem.dbname[j]].addListener("changeSelection", function(e) {
                                 if (this.firstTouch > 1) {
                                    this.parent.main.debug("changed " + this + " " + this.parent.id + " " + this.firstTouch + " " + this.parent.changed + "->" + (this.parent.changed+1) + ": PROPAGATING!");
                                    this.parent.changed += 1;
                                 } else {
                                    this.parent.main.debug("changed " + this + " " + this.parent.id + " " + this.firstTouch + "->" + (this.firstTouch+1) + " " + this.parent.changed);
                                    this.firstTouch += 1;
                                 }
                              }, dstitem.form[dstitem.dbname[j]]);
                              dstitem.form[dstitem.dbname[j]].addListener("changeValue", function(e) {
                                 this.parent.changed += 1;
                                 this.parent.main.debug("changed " + this.parent.id);
                              }, dstitem.form[dstitem.dbname[j]]);
                           }
                           if (!((dstitem.viewstatus[j] == "hidden") ||
                                ((dstitem.viewstatus[j] == "readonly") &&
                                 (unescape(dstitem.columns[j]) == " ") &&
                                 (unescape(dstitem.values[j]) == "")))) {
                              var tmp = "";
                              if (unescape(dstitem.columns[j]) != " ") {
                                 tmp = unescape(dstitem.columns[j]) + " :";
                              }
                              dstitem.label[j] = new qx.ui.basic.Label(tmp);
                              dstitem.label[j].set({alignX: "right"});
                              dstitem.unit[j] = new qx.ui.basic.Label(unescape(dstitem.units[j]));
                              dstitem.formular.add(dstitem.label[j], {row: linenum+x, column: 0}); 
                              dstitem.formular.add(dstitem.form[dstitem.dbname[j]], {row: linenum+x, column: 1});
                              if ((dstitem.types[j] == "list") &&
                                  (dstitem.viewstatus[j] != "readonly")) {
                                 dstitem.buttonnew[j] = new myproject.myButton("Neu", "resource/qx/icon/Tango/16/actions/list-add.png");
                                 dstitem.buttonnew[j].action = "job=listcreateentry,rowid=" + escape(dstitem.rowid) +",column=" + escape(dstitem.dbname[j]) + ",oid=" + escape(this.id.toString()) + ",table=" + escape(this.table) + ",wid=" + escape(this.wid);
                                 dstitem.buttonnew[j].flex = 0;
                                 dstitem.buttonnew[j].main = this.main;
                                 dstitem.buttonnew[j].addListener("execute", function(e) {
                                    //alert("asdf" + this.action + ";" + this + ";" + this.main);
                                    this.main.sendRequest(this.action);
                                 }, dstitem.buttonnew[j]);
                                 dstitem.formular.add(dstitem.buttonnew[j], {row: linenum+x, column: 2});
                                 dstitem.buttonedit[j] = new myproject.myButton("Edit", "resource/qx/icon/Tango/16/actions/document-open.png");
                                 dstitem.buttonedit[j].action = "job=listcreateentry,rowid=" + escape(dstitem.rowid) +",column=" + escape(dstitem.dbname[j]) + ",oid=" + escape(this.id.toString()) + ",table=" + escape(this.table) + ",wid=" + escape(this.wid);
                                 dstitem.buttonedit[j].flex = 0;
                                 dstitem.buttonedit[j].main = this.main;
                                 dstitem.buttonedit[j].selectbox = dstitem.form[dstitem.dbname[j]];
                                 dstitem.buttonedit[j].setEnabled(0);
                                 dstitem.buttonedit[j].selectbox.addListener("changeSelection", function(e) {
                                    var selection = this.selectbox.getSelection();
                                    if ((selection.length > 0) && (selection[0].getModel() != "") && (selection[0].getModel() != "null")) {
                                       this.setEnabled(true);
                                       //alert(":" + selection[0].getModel() + ":" + selection[0].getModel().length + ";");
                                    } else {
                                       this.setEnabled(false);
                                    }
                                 }, dstitem.buttonedit[j]);
                                 dstitem.buttonedit[j].addListener("execute", function(e) {
                                    //alert("asdf" + this.action + ";" + this + ";" + this.main);
                                    var selection = this.selectbox.getSelection();
                                    if (selection.length > 0) {
                                       this.main.sendRequest(this.action + ",id=" + escape(selection[0].getModel()));
                                    }
                                 }, dstitem.buttonedit[j]);
                                 dstitem.formular.add(dstitem.buttonedit[j], {row: linenum+x, column: 3});
                              }
                              if (unescape(dstitem.units[j]) != "") {
                                 x++;
                                 dstitem.formular.add(dstitem.unit[j], {row: linenum+x, column: 1}); 
                              }
                              linenum++;
                           }
                        }
                        dstitem.main = this.main;
                        this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_speichern Speichern resource/qx/icon/Tango/32/actions/document-save.png", function(e) {
                           var params = "job=";
                           if ((typeof(dstitem.rowid) != "undefined") && (dstitem.rowid != "")) {
                              params = params + "saveedit";
                           } else {
                              params = params + "newedit";
                           }
                           params = params + ",oid=" + escape(this.id.toString()) + ",table=" + escape(this.table) + ",wid=" + escape(this.wid) + this.urlappend;
                           for (var j = 0; j < dstitem.columns.length; j++) {
                              if (dstitem.types[j] == "composite") {
                              } else if ((dstitem.viewstatus[j] == "readonly") ||
                                  (dstitem.types[j] == "text") ||
                                  (dstitem.types[j] == "password") ||
                                  (dstitem.types[j] == "number") ||
                                  (dstitem.types[j] == "double") ||
                                  (dstitem.types[j] == "id")) {
                                 params = params + "," + dstitem.dbname[j] + "=" + escape(dstitem.form[dstitem.dbname[j]].getValue());
                              } else if (dstitem.types[j] == "boolean") {
                                 params = params + "," + dstitem.dbname[j] + "=";
                                 if (dstitem.form[dstitem.dbname[j]].getValue()) {
                                    params = params + "1";
                                 } else {
                                    params = params + "0";
                                 }
                              } else if (dstitem.types[j] == "list") {
                                 var selection = dstitem.form[dstitem.dbname[j]].getSelection();
                                 if (selection.length > 0) {
                                    params = params + "," + dstitem.dbname[j] + "=" + escape(selection[0].getModel());
                                 }
                              } else if (dstitem.types[j] == "date") {
                                 params = params + "," + dstitem.dbname[j] + "=" + escape(new qx.util.format.DateFormat("yyyy-MM-dd").format(dstitem.form[dstitem.dbname[j]].getValue()));
                              } else if (dstitem.types[j] == "datetime") {
                                 params = params + "," + dstitem.dbname[j] + "=" + escape(new qx.util.format.DateFormat("yyyy-MM-dd HH:mm").format(dstitem.form[dstitem.dbname[j]].getValue()));
                              }
                              if (typeof(dstitem.label[j]) != 'undefined') {
                                 dstitem.label[j].setEnabled(false);
                              } else {
                                 this.main.debug("crateedit: Unable to send content for field '" + dstitem.dbname[j] + "' of type '" + dstitem.types[j] + "'... Sending nothing for it!");
                              }
                              if (typeof(dstitem.unit[j]) != 'undefined') {
                                 dstitem.unit[j].setEnabled(false);
                              }
                              dstitem.form[dstitem.dbname[j]].setEnabled(false);
                           }
                           for (var i = 0; i < this.lockable.length; ++i) {
                              this.main.processCommands("setactive " + this.lockable[i] + " ");
                           }
                           dstitem.changed = 0;
                           this.main.sendRequest(params);
                        }, dstitem);
                        this.lockable.push(dstid + "_toolbar_speichern");
                        this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_speichern");
                        this.main.processCommands("addobject " + id + " " + dstid + "_toolbar");
                     });
                     scroller.addListener("unlock", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        for (var j = 0; j < dstitem.columns.length; j++) {
                           if (typeof(dstitem.label[j]) != 'undefined') {
                              dstitem.label[j].setEnabled(true);
                           }
                           if (typeof(dstitem.unit[j]) != 'undefined') {
                              dstitem.unit[j].setEnabled(true);
                           }
                           dstitem.form[dstitem.dbname[j]].setEnabled(true);
                        }
                        for (var i = 0; i < this.lockable.length; ++i) {
                           this.main.processCommands("setactive " + this.lockable[i] + " 1");
                        }
                     });
                     scroller.addListener("delobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        for (var j = 0; j < dstitem.columns.length; j++) {
                           if (!((dstitem.viewstatus[j] == "hidden") ||
                                ((dstitem.viewstatus[j] == "readonly") &&
                                 (unescape(dstitem.columns[j]) == " ") &&
                                 (unescape(dstitem.values[j]) == "")))) {
                              dstitem.formular.remove(dstitem.label[j]);
                              dstitem.label[j].destroy();
                              if (unescape(dstitem.units[j]) != "") {
                                 dstitem.formular.remove(dstitem.unit[j]);
                                 dstitem.unit[j].destroy();
                              }
                              dstitem.formular.remove(dstitem.form[dstitem.dbname[j]]);
                              if ((dstitem.types[j] == "list") && 
                                  (dstitem.viewstatus[j] != "readonly")){
                                 dstitem.formular.remove(dstitem.buttonnew[j]);
                                 dstitem.buttonnew[j].destroy();
                                 dstitem.formular.remove(dstitem.buttonedit[j]);
                                 dstitem.buttonedit[j].destroy();
                              }
                           }
                           dstitem.form[dstitem.dbname[j]].destroy();
                        }
                        dstitem.groupBox.remove(dstitem.formular);
                        dstitem.formular.destroy();
                        dstitem.remove(dstitem.groupBox);
                        dstitem.groupBox.destroy();
                        this.debug("EDIT(" + dstid.toString() + "): Removed my helperobjects from parent " + id.toString());
                     });
                     scroller.id = id;
                     scroller.main = this;
                     this.objects.setItem(scroller.id, scroller);
                  }
               } else if (cmd == "createtext") {
                  var id = cmdparam.shift(); // 1. ID
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATETEXT: Object already existing: " + id);
                  } else {
                     var rich = cmdparam.shift();
                     var text = new myproject.myLabel(unescape(cmdparam.join(' ')));
                     text.flex = 1;
                     text.setWrap(true);
                     if (rich != "") {
                        text.set({ rich : true });
                        if (parseInt(rich, 10) > 0) {
                           text.set({ width: parseInt(rich, 10) });
                        }
                     }
                     text.id = id;
                     text.main = this;
                  }
                  this.objects.setItem(text.id, text);
               } else if (cmd == "settext") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var item = this.objects.getItem(id);
                     var rich = unescape(cmdparam.shift());
                     if (rich != "") {
                        item.set({
                           rich : true,
                           value: unescape(cmdparam.shift())
                        });
                        if (parseInt(rich, 10) > 0) {
                           item.set({ width: parseInt(rich, 10) });
                        }
                     }
                  } else {
                     this.debug("SETTEXT: Object not found: " + id);
                  }
               } else if (cmd == "createlist") {
                  var id = cmdparam.shift(); // 1. ID
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATELIST: Object already existing: " + id);
                  } else {
                     var curlist = new myproject.myList();
                     curlist.flex = 1;
                     curlist.tablename = unescape(cmdparam.shift());
                     //curlist.buttonnames = cmdparam.shift().split(",");
                     //curlist.buttonimages = cmdparam.shift().split(",");
                     //curlist.buttonaction = cmdparam.shift().split(",");
                     //curlist.buttontype = cmdparam.shift().split(",");
                     curlist.buttonnames  = new Array();
                     curlist.buttonimages = new Array();
                     curlist.buttonaction = new Array();
                     curlist.buttontype   = new Array();
                     var tmp = cmdparam.shift();
                     if (tmp == 'JSON') {
                        var myjson = eval('(' + unescape(cmdparam.shift()) + ')');
                        for (var j = 0; j < myjson.length; j++) {
                           curlist.buttonnames.push(myjson[j].label);
                           curlist.buttonimages.push("JSON");
                           curlist.buttonaction.push(myjson[j]);
                           curlist.buttontype.push(myjson[j].bindto);
                        }
                     } else {
                        curlist.buttonnames = tmp.split(",");
                        curlist.buttonimages = cmdparam.shift().split(",");
                        curlist.buttonaction = cmdparam.shift().split(",");
                        curlist.buttontype = cmdparam.shift().split(",");
                     }
                     curlist.infotext = unescape(cmdparam.shift());
                     curlist.urlappend = unescape(cmdparam.shift());
                     curlist.childs = new Hash();
                     curlist.id = id;
                     curlist.main = this;
                     curlist.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        if ((dstitem.buttonnames.length > 0) || (dstitem.infotext != "")) {
                           this.main.processCommands("createtoolbar " + dstid + "_toolbar");
                           this.main.processCommands("addobject " + id + " " + dstid + "_toolbar");
                           dstitem.buttons = new Array();
                           for (var j = 0; j < dstitem.buttonnames.length; j++) {
                              dstitem.buttons[j] = new Array();
                              dstitem.buttons[j].type = dstitem.buttontype[j];
                              dstitem.buttons[j].parent = this;
                              dstitem.buttons[j].id = dstitem.buttonnames[j];
                              if (dstitem.buttonnames[j] != '') {
                                 var newid = dstid + "_toolbar_" + dstitem.buttonnames[j];
                                 var job = "createtoolbarbutton";
                                 if (dstitem.buttonimages[j] == 'JSON') {
                                    dstitem.buttonaction[j].id = newid;
                                    dstitem.buttonaction[j].job = job;
                                    dstitem.buttons[j].action = dstitem.buttonaction[j].action;
                                    // TODO:XXX:FIXME: Doeppelter Code, auch bei createtable vorhanden.
                                    tmp = "JSON " + escape(JSON.stringify(dstitem.buttonaction[j]));
                                    //this.main.debug("JSON: " + tmp);
                                 } else {
                                    dstitem.buttons[j].action = dstitem.buttonaction[j];
                                    tmp = job + " " + newid + " " + dstitem.buttonnames[j] + " " + dstitem.buttonimages[j];
                                 }
                                 this.main.processCommands(tmp, function(e) {
                                    this.curaction = "";
                                    this.cururlappend = "";
                                    if ((typeof(this.action) != "undefined") && (this.action != "")) {
                                       this.curaction = this.action;
                                    }
                                    if ((typeof(this.menuaction) != "undefined") && (this.menuaction != "")) {
                                       this.curaction = this.menuaction;
                                       if ((typeof(this.menuurlappend) != "undefined") && (this.menuurlappend != "")) this.cururlappend = this.menuurlappend;
                                    }
                                    if (this.curaction != "") {
                                       var tmp = "job=" + this.curaction + ",oid=" + this.parent.id.toString() + ",table=" + this.parent.tablename + this.parent.urlappend + this.cururlappend;
                                       if (this.type == "row") {
                                          var model = this.parent.getSelection();
                                          for (var loop = 0; loop < model.length; loop++) {
                                             // TODO:FIXME:XXX: DBID geht nicht?
                                             this.parent.main.sendRequest(tmp + ",id=" + model[loop].dbid);
                                          };
                                       } else {
                                          this.parent.main.sendRequest(tmp);
                                       }
                                    }
                                    this.menuaction = "";
                                    this.menuurlappend = "";
                                 }, dstitem.buttons[j]);
                                 this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_" + dstitem.buttonnames[j]);
                                 if (dstitem.buttontype[j] == "row") {
                                    this.main.processCommands("setactive " + dstid + "_toolbar_" + dstitem.buttonnames[j] + " ");
                                 }
                              }
                           }
                           if (dstitem.infotext != "") {
                              this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_hilfe" + " Hilfe resource/qx/icon/Tango/32/actions/help-faq.png", function(e) {
                                 this.main.processCommands("showmessage " + escape(this.columnname) + " 600 400 " + escape(this.infotext));
                              }, dstitem);
                              this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_hilfe");
                           }
                        }
                        //item.setContentPadding(10, 10, 10, 10);
                        if (!this.main.tablelisteners.hasItem(dstitem.tablename)) {
                           this.main.tablelisteners.setItem(dstitem.tablename, new Array());
                        }
                        this.main.tablelisteners.getItem(dstitem.tablename).push(dstitem);
                     });
                     curlist.addListener("reloadData", function(e) {
                        var entryinfo = e.getData();
                        var dstid = this.id;
                        var dstitem = this.main.objects.getItem(dstid);
                        this.main.sendRequest("job=updatelist,table=" + dstitem.tablename + ",oid=" + dstid + dstitem.urlappend);
                     });
                     //curlist.addListener("dblclick", function(e) {
                     //   this.debug("bla");
  						   //   for (var i = 0; i < this.getSelection().lenght; i++) {
                     //      this.debug("Selected item: " + this.getSelection()[i]);
                     //	   //this.main.sendRequest("job=dblclick,type=list,oid=" + this.id.toString() + ",table=" + this.tablename + ",id=" + this.getTableModel().getValueById(this.idcol, ind));
                     //	}
                     //}, curlist);
                     curlist.addListener("delobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        if (this.main.tablelisteners.hasItem(dstitem.tablename)) {
                           var idx = this.main.tablelisteners.getItem(dstitem.tablename).indexOf(dstitem);
                           if (idx!=-1) this.main.tablelisteners.getItem(dstitem.tablename).splice(idx, 1);
                        }
                     });
                     curlist.addListener("changeSelection", function(e) {
                        if (this.getSelection().length > 0) {
                           for (var j = 0; j < this.buttonnames.length; j++) {
                              if (this.buttontype[j] == "row") {
                                 this.main.processCommands("setactive " + this.id + "_toolbar_" + this.buttonnames[j] + " 1");
                              }
                           }
                        } else {
                           for (var j = 0; j < this.buttonnames.length; j++) {
                              if (this.buttontype[j] == "row") {
                                 this.main.processCommands("setactive " + this.id + "_toolbar_" + this.buttonnames[j] + " ");
                              }
                           }
                        }
                     }, curlist);
                     this.objects.setItem(curlist.id, curlist);
                  }
               } else if (cmd == "clearlist") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var curlist = this.objects.getItem(id);
                     var destroystr = '';
                     for (var i in curlist.childs.items) {
                        if (curlist.childs.hasItem(i) && (typeof(curlist.childs.items[i]) == 'object')) this.processCommands("destroy " + i);
                     }
                  } else {
                     this.debug("CLEARLIST: Object not found: " + id);
                  }
               } else if (cmd == "createlistitem") {
                  var id = cmdparam.shift(); // 1. ID
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATELISTITEM: Object already existing: " + id);
                  } else {
                     var dbid = unescape(cmdparam.shift());
                     var label = unescape(cmdparam.shift());
                     var image = unescape(cmdparam.shift());
                     var imagepos = cmdparam.shift();
                     if ((typeof(imagepos) == 'undefined') || (imagepos == "")) {
                        imagepos = "top-left";
                     } else {
                        imagepos = unescape(imagepos);
                     }
                     var curlistitem = new myproject.myListItem(label.replace(/\n/g, "<br>"), image, dbid);
                     curlistitem.setRich(true);
                     curlistitem.setIconPosition(imagepos);

                     curlistitem.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        dstitem.item = item;
                        dstitem.addListener("dblclick", function(e) {
                           if ((this.dbid != "") && (this.dbid != "null") && (this.dbid != null)) {
                              this.main.sendRequest("job=dblclick,type=list,oid=" + this.item.id.toString() + ",table=" + this.item.tablename + ",id=" + this.dbid + this.item.urlappend);
                           }
                        }, dstitem);
                     });

                     curlistitem.flex = 1;
                     curlistitem.dbid = dbid;
                     curlistitem.id = id;
                     curlistitem.main = this;
                     this.objects.setItem(curlistitem.id, curlistitem);
                  }
               } else if (cmd == "createtable") {
                  var id = cmdparam.shift(); // 1. ID
                  if (this.objects.hasItem(id)) {
                     this.debug("CREATETABLE: Object already existing: " + id);
                  } else {
                     var table = unescape(cmdparam.shift()); // 2. Tabelle
                     var columns = cmdparam.shift().split(","); // 3. ColumnTEXT
                     var types = cmdparam.shift().split(",");  // 4. Typen
                     var dbnames = cmdparam.shift().split(","); // 5. ColumnDBName
                     for (var j = 0; j < columns.length; j++) {
                        columns[j] = unescape(columns[j]);
                     }
                     var tableModel = new myproject.myRemoteTableModel();
                     tableModel.main = this;
                     tableModel.id = id;
                     tableModel.curtabletablename = table;
                     var viewstatus = cmdparam.shift().split(",");  // 6. Viewstatus
                     var defsize = cmdparam.shift().split(",");
                     var minsize = cmdparam.shift().split(",");
                     var maxsize = cmdparam.shift().split(",");
                     //var restrictions = cmdparam.shift();
                     var tmp = cmdparam.shift();
                     var buttonnames;
                     var buttonimages
                     var buttonaction;
                     var buttontype;
                     if (tmp == 'JSON') {
                        //var jsonpre = unescape(cmdparam.shift());
                        //this.debug("Parsing..." + jsonpre);
                        var myjson = eval('(' + unescape(cmdparam.shift()) + ')');
                        //this.debug("Parsed " + myjson);
                        buttonnames  = new Array();
                        buttonimages = new Array();
                        buttonaction = new Array();
                        buttontype   = new Array();
                        for (var j = 0; j < myjson.length; j++) {
                           buttonnames.push(myjson[j].label);
                           buttonimages.push("JSON");
                           buttonaction.push(myjson[j]);
                           buttontype.push(myjson[j].bindto);
                        }
                     } else {
                        buttonnames = tmp.split(",");
                        buttonimages = cmdparam.shift().split(",");
                        buttonaction = cmdparam.shift().split(",");
                        buttontype = cmdparam.shift().split(",");
                     }
                     var infotext = unescape(cmdparam.shift());
                     var urlappend = unescape(cmdparam.shift());
                     var rowHeight = unescape(cmdparam.shift());
                     tableModel.urlappend = urlappend;
                     tableModel.setColumns(columns, dbnames);
                     var curtable = new myproject.myTable(tableModel, {
                        tableColumnModel : function(obj) {
                           return new qx.ui.table.columnmodel.Resize(obj);
                        }
                     });
                     this.debug("idcol4");
                     curtable.idcol = unescape(cmdparam.shift());
                     if ((typeof(curtable.idcol) == "undefined") || (curtable.idcol == "")) curtable.idcol = "id";
                     //curtable.idcol = "id";
                     curtable.flex = 1;
                     tableModel.curtable = curtable;
                     curtable.tablename = table;
                     curtable.types = types;
                     curtable.dbname = dbnames;
                     curtable.viewstatus = viewstatus;
                     //curtable.restrictions = restrictions;
                     curtable.buttonnames = buttonnames;
                     curtable.buttonimages = buttonimages;
                     curtable.buttonaction = buttonaction;
                     curtable.buttontype = buttontype;
                     curtable.infotext = infotext;
                     curtable.urlappend = urlappend;
                     curtable.id = id;
                     curtable.main = this;
                     if ((typeof(rowHeight) != "undefined") && (rowHeight > 0)) curtable.setRowHeight(rowHeight);
                     curtable.setShowCellFocusIndicator(false);
                     for (var j = 0; j < columns.length; j++) {
                        if (curtable.types[j] == "id") {
                           curtable.getTableColumnModel().setDataCellRenderer(j, new qx.ui.table.cellrenderer.Number());
                        } else if (curtable.types[j] == "date") {
                           curtable.getTableColumnModel().setDataCellRenderer(j, new qx.ui.table.cellrenderer.Date("yyyy-MM-dd"));
                        } else if (curtable.types[j] == "datetime") {
                           curtable.getTableColumnModel().setDataCellRenderer(j, new qx.ui.table.cellrenderer.Date("yyyy-MM-dd kk:mm:ss"));
                        } else if (curtable.types[j] == "html") { 
                           curtable.getTableColumnModel().setDataCellRenderer(j, new qx.ui.table.cellrenderer.Html("center", "blue"));
                        } else if (curtable.types[j] == "boolean") { 
                           curtable.getTableColumnModel().setDataCellRenderer(j, new qx.ui.table.cellrenderer.Boolean());
                        //} else {
                        //   if (curtable.restrictions != "readonly") { tableModel.setColumnEditable(j, true); }
                        }
                        if ((curtable.viewstatus[j] == "hidden") || (curtable.viewstatus[j] == "writeonly")) {
                           curtable.getTableColumnModel().setColumnVisible(j,false);
                        }
                        if (parseInt(defsize[j], 10)) curtable.getTableColumnModel().getBehavior().setWidth(   j, parseInt(defsize[j], 10));
                        if (parseInt(minsize[j], 10)) curtable.getTableColumnModel().getBehavior().setMinWidth(j, parseInt(minsize[j], 10));
                        if (parseInt(maxsize[j], 10)) curtable.getTableColumnModel().getBehavior().setMaxWidth(j, parseInt(maxsize[j], 10));
                     }
                     var Model = qx.ui.table.selection.Model;
                     curtable.getSelectionModel().setSelectionMode(Model.MULTIPLE_INTERVAL_SELECTION);
                     curtable.setDraggable(true);
                     curtable.addListener("dragstart", function(e) {
                        this.debug("Related of dragstart: " + e.getRelatedTarget());
                        e.addType(this.tablename);
                        e.addAction("copy");
                        //e.addAction("move");
                     });
                     curtable.getDataRowRenderer().setHighlightFocusRow(false);
                     tableModel.addListener("dataChanged", function (e) {
                        curtable.getSelectionModel().fireEvent('changeSelection');
                     }, curtable);
                     curtable.getSelectionModel().addListener("changeSelection", function(e) {
                        var i = 0;
                        this.getSelectionModel().iterateSelection(function(ind) {
                           this.debug("idcol2");
                           if (this.getTableModel().getValueById(this.idcol, ind) != null) {
                              i++;
                           }
                        }, this);
                        for (var j = 0; j < this.buttonnames.length; j++) {
                           if (this.buttontype[j] == "row") {
                              if (i == 0) {
                                 this.main.processCommands("setactive " + this.id + "_toolbar_" + this.buttonnames[j] + " ");
                              } else {
                                 this.main.processCommands("setactive " + this.id + "_toolbar_" + this.buttonnames[j] + " 1");
                              }
                           }
                        }
                     }, curtable);
                     curtable.addListener("cellDblclick", function(e) {
  							   this.getSelectionModel().iterateSelection(function(ind) {
                           //this.debug("job=dblclick,type=table,oid=" + this.id.toString() + ",table=" + this.tablename + ",id=" + this.getTableModel().getValueById(this.idcol, ind));
                           this.debug("idcol1");
                           var id = this.getTableModel().getValueById(this.idcol, ind);
                           if ((id != "") && (id != "null") && (id != null)) {
                              this.main.sendRequest("job=dblclick,type=table,oid=" + this.id.toString() + ",table=" + this.tablename + ",id=" + id + this.urlappend);
                           }
                        }, this);
                     }, curtable);
                     curtable.addListener("reloadData", function(e) {
                        var entryinfo = e.getData();
                        var dstid = this.id;
                        var dstitem = this.main.objects.getItem(dstid);
                        dstitem.getTableModel().reloadData();
                     });
                     curtable.addListener("delobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
                        if (this.main.tablelisteners.hasItem(dstitem.tablename)) {
                           var idx = this.main.tablelisteners.getItem(dstitem.tablename).indexOf(dstitem);
                           if (idx!=-1) this.main.tablelisteners.getItem(dstitem.tablename).splice(idx, 1);
                        }
                        this.debug("TABLE(" + dstid.toString() + "): Removed my helperobjects from parent " + id.toString());
                     });
                     curtable.addListener("addobject", function(e) {
                        var id = e.getData();
                        var dstid = this.id;
                        var item = this.main.objects.getItem(id);
                        var dstitem = this.main.objects.getItem(dstid);
//                        if (dstitem.restrictions != "readonly") {
                        if ((dstitem.buttonnames.length > 0) || (dstitem.infotext != "")) {
                           this.main.processCommands("createtoolbar " + dstid + "_toolbar");
                           this.main.processCommands("addobject " + id + " " + dstid + "_toolbar");
                           dstitem.buttons = new Array();
                           for (var j = 0; j < dstitem.buttonnames.length; j++) {
                              dstitem.buttons[j] = new Array();
                              dstitem.buttons[j].type = dstitem.buttontype[j];
                              dstitem.buttons[j].parent = this;
                              dstitem.buttons[j].id = dstitem.buttonnames[j];
                              if (dstitem.buttonnames[j] != '') {
                                 var newid = dstid + "_toolbar_" + dstitem.buttonnames[j];
                                 var job = "createtoolbarbutton";
                                 if (dstitem.buttonimages[j] == 'JSON') {
                                    dstitem.buttonaction[j].id = newid;
                                    dstitem.buttonaction[j].job = job;
                                    dstitem.buttons[j].action = dstitem.buttonaction[j].action;
                                    // TODO:XXX:FIXME: Doeppelter Code, auch bei createlist vorhanden.
                                    tmp = "JSON " + escape(JSON.stringify(dstitem.buttonaction[j]));
                                    //this.main.debug("JSON: " + tmp);
                                 } else {
                                    dstitem.buttons[j].action = dstitem.buttonaction[j];
                                    tmp = job + " " + newid + " " + dstitem.buttonnames[j] + " " + dstitem.buttonimages[j];
                                 }
                                 this.main.processCommands(tmp, function(e) {
                                    this.curaction = "";
                                    this.cururlappend = "";
                                    if ((typeof(this.action) != "undefined") && (this.action != "")) {
                                       this.curaction = this.action;
                                    }
                                    if ((typeof(this.menuaction) != "undefined") && (this.menuaction != "")) {
                                       this.curaction = this.menuaction;
                                       if ((typeof(this.menuurlappend) != "undefined") && (this.menuurlappend != "")) this.cururlappend = this.menuurlappend;
                                    }
                                    if (this.curaction != "") {
                                       var tmp = "job=" + this.curaction + ",oid=" + this.parent.id.toString() + ",table=" + this.parent.tablename + this.parent.urlappend  + this.cururlappend;
                                       if (this.type == "row") {
                                          var id = "";
                                          var ids = "";
                                          this.parent.getSelectionModel().iterateSelection(function(ind) {
                                             this.parent.debug("idcol3");
                                             var curid = this.parent.getTableModel().getValueById(this.parent.idcol, ind);
                                             if (id == "") {
                                                id = curid;
                                             }
                                             if (ids != "") {
                                                ids = ids + ";";
                                             }
                                             ids = ids + curid;
                                          }, this);
                                          this.parent.main.sendRequest(tmp + ",id=" + id + ",ids=" + ids);
                                       } else {
                                          this.parent.main.sendRequest(tmp);
                                       }
                                    };
                                    this.menuaction = "";
                                    this.menuurlappend = "";
                                 }, dstitem.buttons[j]);
                                 this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_" + dstitem.buttonnames[j]);
                                 if (dstitem.buttontype[j] == "row") {
                                    this.main.debug("Sending deactive to " + dstid + "_toolbar_" + dstitem.buttonnames[j] + " ");
                                    this.main.processCommands("setactive " + dstid + "_toolbar_" + dstitem.buttonnames[j] + " ");
                                 }
                              }
                           }
                           if (dstitem.infotext != "") {
                              this.main.processCommands("createtoolbarbutton " + dstid + "_toolbar_hilfe" + " Hilfe resource/qx/icon/Tango/32/actions/help-faq.png", function(e) {
                                 this.main.processCommands("showmessage " + escape(this.columnname) + " 600 400 " + escape(this.infotext));
                              }, dstitem);
                              this.main.processCommands("addobject " + dstid + "_toolbar " + dstid + "_toolbar_hilfe");
                           }
                        }
                        if (!this.main.tablelisteners.hasItem(dstitem.tablename)) {
                           this.main.tablelisteners.setItem(dstitem.tablename, new Array());
                        }
                        this.main.tablelisteners.getItem(dstitem.tablename).push(dstitem);
                     }); 
                     curtable.addListener("droprequest", function(e) {
                        this.debug("Related of droprequest: " + e.getRelatedTarget());
                        var action = e.getCurrentAction();
                        var type = e.getCurrentType();
                        var result;
                        if (!(e.getRelatedTarget() == this)) {
                           switch(type) {
                              case this.tablename:
                                 var copy = [];
                                 this.getSelectionModel().iterateSelection(function(ind) {
                                    copy.push(this.getTableModel().getRowData(ind));
                                 }, this);
                                 result = copy;
                                 break;
                           }
                        }
                        e.addData(type, result);
                     });
                     curtable.setDroppable(true);
                     curtable.addListener("dragover", function(e) {
                        this.debug("Related of dragover: " + e.getRelatedTarget());
                        if ((e.getTarget() == this) || (!e.supportsType(this.tablename))) {
                           e.preventDefault();
                        }
                     });
                     curtable.addListener("drop", function(e) {
                        this.debug("Related of drop: " + e.getRelatedTarget());
                        // Move items from source to target
                        var items = e.getData(this.tablename);
                        //for (var i=0, l=items.length; i<l; i++) {
                        //   this.getTableModel().addRows(items[i]);
                        //}
                        this.getTableModel().addRows(items);
                     });
                     this.objects.setItem(curtable.id, curtable);
                  }
               } else if (cmd == "addrow") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var curtable = this.objects.getItem(id);
                     var ionum = cmdparam.shift();
                     var elements = cmdparam.join(" ").split(",");
                     var line = [];
                     for (var xx = 0; xx < elements.length; xx++) {
                        line[curtable.dbname[xx]] = unescape(elements[xx]);
                        if ((curtable.types[xx] == "id") || 
                            (curtable.types[xx] == "number")) {
                           if (line[curtable.dbname[xx]] != "")
                              line[curtable.dbname[xx]] = parseInt(line[curtable.dbname[xx]], 10);
                        } else if (curtable.types[xx] == "double") {
                           if (line[curtable.dbname[xx]] != "")
                              line[curtable.dbname[xx]] = parseFloat(line[curtable.dbname[xx]]);
                        } else if (curtable.types[xx] == "boolean") {
                           // TODO:FIXME:XXX: Nicht auf [X] prüfen sondern auf 1/0!!! Serverseitig fixen!
                           line[curtable.dbname[xx]] = (line[curtable.dbname[xx]] == "[X]");
                        }
                     }
                     if ((ionum != "") && (typeof(this.ioreqs[ionum]) != "undefined") &&
                                          (typeof(this.iodata[ionum]) != "undefined")) {
                        this.iodata[ionum].push(line);
                     } else {
                        this.debug("ADDROW: data is empty: ionum=" + ionum + " :" + this.ioreqs[ionum] + ":" + this.iodata[ionum]);
                     }
                  } else {
                     this.debug("ADDROW: Object not found: " + id);
                  }
               } else if (cmd == "addrowsdone") {
                  var id = cmdparam.shift();
                  if (this.objects.hasItem(id)) {
                     var curtable = this.objects.getItem(id);
                     var rowcount = parseInt(cmdparam.shift(), 10);
                     var ionum = cmdparam.shift();
                     if ((ionum != "") && (typeof(this.ioreqs[ionum]) != "undefined")) {
                        //this.ioreqs[ionum]._onRowCountLoaded(rowcount);
                        //this.debug("ADDROWDONE: _onRowCountLoaded: " + rowcount + ":" + ":ionum=" + ionum);
                        if (typeof(this.iodata[ionum]) != "undefined") {
                           this.ioreqs[ionum]._onRowDataLoaded(this.iodata[ionum]);
                           //this.debug("ADDROWDONE: _onRowDataLoaded");
                           delete(this.iodata[ionum]);
                        } else {
                           this.debug("ADDROWSDONE: data is empty: " + ionum + ":" + this.iodata[ionum]);
                        }
                        delete(this.ioreqs[ionum]);
                     } else {
                        //this.debug("ADDROWDONE: Unknown ionum: " + ionum + ":" + rowcount);
                        curtable.getTableModel()._onRowCountLoaded(rowcount);
                     }
                  } else {
                     this.debug("ADDROWSDONE: Object not found: " + id);
                  }
               } else if ((cmd == "delrow") || (cmd == "updaterow")) {
                  var table = cmdparam.shift();
                  var dbid = cmdparam.shift();
                  this.onEntryChanged(table, dbid);
               } else if (cmd == "showmessage") {
                  var msg = new qx.ui.window.Window(unescape(cmdparam.shift()));
                  msg.setWidth(parseInt(unescape(cmdparam.shift()), 10));
                  msg.setHeight(parseInt(unescape(cmdparam.shift()), 10));
                  msg.setShowMinimize(false);
                  msg.setShowMaximize(false);
                  msg.setShowClose(true);
                  msg.scroller = new qx.ui.container.Scroll().set({
                     allowGrowX: true,
                     allowGrowY: true,
                     allowShrinkX: true,
                     allowShrinkY: true,
                     width: 1,
                     height: 1
                  });
                  msg.root = new qx.ui.container.Composite(new qx.ui.layout.VBox).set({
                     allowGrowX: true,
                     allowGrowY: true,
                     allowShrinkX: true,
                     allowShrinkY: true,
                     height: 1,
                     width: 1
                  });
                  msg.scroller.setContentPadding(10, 10, 10, 10);
                  msg.scroller.add(msg.root);
                  msg.setLayout(new qx.ui.layout.VBox());
                  msg.add(msg.scroller, { flex: 1 });
   
                  //msg.setLayout(new qx.ui.layout.VBox());
                  msg.center();
                  // TODO:FIXME:XXX: Nicht <br> ändern sondern chr(10)!
                  var lines = unescape(cmdparam.join(" ")).split("<br>");
                  this.debug("Adding lines...");
                  for (var line in lines) {
                     if (typeof(lines[line]) == "string") {
                        var text = new qx.ui.basic.Label(lines[line]);
                        text.setWrap(true);
                        msg.root.add(text);
                     }
                  }
                  this.debug("Adding lines done!");
                  msg.button = new qx.ui.form.Button("OK", "resource/qx/icon/Tango/32/actions/dialog-apply.png");
                  msg.add(msg.button);
                  msg.button.addListener("execute", function(e) {
                     this.remove(this.button);
                     this.button.destroy();
                     this.destroy();
                  }, msg);
                  msg.open();
                  msg.button.activate();
               } else if (cmd == "addbutton") {
                  var id = unescape(cmdparam.shift());
                  var dstid = unescape(cmdparam.shift());
                  var text = unescape(cmdparam.shift());
                  var image = unescape(cmdparam.shift());
                  var action = unescape(cmdparam.shift());
                  if (this.objects.hasItem(dstid)) {
                     this.debug("ADDBUTTON: Object already existing: " + id);
                  } else {
                     if (id == "") {
                        if (typeof(this.menuscroller) == 'undefined') {
                           this.createMenu();
                        }
                        var button = new qx.ui.form.Button(text, image);
                        button.action = action;
                        button.main = this;
                        button.id = dstid;
                        this.menuroot.add(button);
                        this.debug("ADDBUTTON: Added " + dstid + " (IMAGE: " + image + ") to ROOTMENU.");
                        button.addListener("execute", function(e) {
                           this.main.sendRequest(this.action);
                        }, button);
                        this.menuobjects.setItem(button.id, button);
                     } else {
                        if (this.menuobjects.hasItem(id)) {
                           var button = new qx.ui.menu.Button(text, image);
                           button.action = action;
                           button.main = this;
                           button.id = dstid;
                           if (dstid != "") {
                              button.addListener("execute", function(e) {
                                 this.main.sendRequest(this.action);
                              }, button);
                              this.menuobjects.getItem(id).add(button);
                              this.menuobjects.setItem(button.id, button);
                              this.debug("ADDBUTTON: Added " + dstid + " to menu " + id + ".");
                           } else {
                              this.menuobjects.getItem(id).addSeparator();
                           }
                        } else {
                           this.debug("ADDBUTTON: Menu " + id + " not found");
                        }
                     }
                  }
               } else if (cmd == "addmenu") {
                  var id = unescape(cmdparam.shift());
                  var dstid = unescape(cmdparam.shift());
                  var text = unescape(cmdparam.shift());
                  var image = unescape(cmdparam.shift());
                  if (this.objects.hasItem(dstid)) {
                     this.debug("ADDMENU: Object already existing: " + id);
                  } else {
                     var menu = new qx.ui.menu.Menu;
                     menu.id = dstid;
                     if (id == "") {
                        if (typeof(this.menuscroller) == 'undefined') {
                           this.createMenu();
                        }
                        menu.button = new qx.ui.form.MenuButton(text, image, menu);
                        this.menuroot.add(menu.button);
                        this.menuobjects.setItem(menu.id, menu);
                        this.debug("ADDMENU: Added " + dstid + " to ROOTMENU.");
                     } else {
                        if (this.menuobjects.hasItem(id)) {
                           menu.button = new qx.ui.menu.Button(text, image, null, menu);
                           this.menuobjects.getItem(id).add(menu.button);
                           this.menuobjects.setItem(menu.id, menu);
                        } else {
                           this.debug("ADDMENU: Menu " + dstid + " not found");
                        }
                     }
                  }
               } else {
                  if (curcmd != "") {
                     this.debug("Unknown data from server: " + curcmd)
                  }
               }
            }
         }

         /////////////////////////////// HASH begin

         function Hash() {
            this.length = 0;
            this.items = new Array();
            for (var i = 0; i < arguments.length; i += 2) {
               if (typeof(arguments[i + 1]) != 'undefined') {
                  this.items[arguments[i]] = arguments[i + 1];
                  this.length++;
               }
            }
            this.removeItem = function(in_key) {
               var tmp_previous;
               if (typeof(this.items[in_key]) != 'undefined') {
                  this.length--;
                  var tmp_previous = this.items[in_key];
                  delete this.items[in_key];
               }               
               return tmp_previous;
            }
            this.getItem = function(in_key) {
               return this.items[in_key];
            }
            this.setItem = function(in_key, in_value) {
               var tmp_previous;
               if (typeof(in_value) != 'undefined') {
                  if (typeof(this.items[in_key]) == 'undefined') {
                     this.length++;
                  } else {
                     tmp_previous = this.items[in_key];
                  }
                  this.items[in_key] = in_value;
               }               
               return tmp_previous;
            }
            this.hasItem = function(in_key) {
               return typeof(this.items[in_key]) != 'undefined';
            }
            this.clear = function() {
               for (var i in this.items) {
                  delete this.items[i];
               }
               this.length = 0;
            }
         }

         /////////////////////////////// HASH end
         
      }
   }
});
