"use strict";

plugin.consumes = [
    "connect"
];
plugin.provides = [
    "connect.favicon"
];

module.exports = plugin;

function plugin(options, imports, register) {
    var connect = imports.connect;
    var favicon = connect.getFavicon();

    var icon = options.path || __dirname + "/favicon.ico";
    connect.useStart(favicon(icon, options));

    register(null, {
        "connect.favicon": {}
    });
}