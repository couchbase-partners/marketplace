#!/usr/local/bin/node

const fs = require("fs"),
      readline = require("readline");
const replacementRegex = /\$__\w*__/g
const scriptURLReplacementRegex = /__SCRIPT_URL__/g

async function processEmbeddedLines(file) {
    let lines = [];
    const reader = readline.createInterface({
        input: fs.createReadStream(file),
        crlfDelay: Infinity
    });

    for await (const line of reader) {
        if (line.match(replacementRegex)) {
            lines.push(...performReplacement(line));
        } else if (line.match(scriptURLReplacementRegex)) {
            lines.push(swapInScriptUrl(line));
        } else {
            lines.push("'" +line + "\n'");
        }
        
    }
    var userData= lines.join(",")
    userData = "[concat(" + userData + ")]"
    return userData
    
}

function swapInScriptUrl(line) {
    return "'" + line.replace(scriptURLReplacementRegex, script_url) + "\n'"
}

function performReplacement(line) {
    const values = [];
    index = 0;
    while ((match = replacementRegex.exec(line)) != null) {
        values.push("'" + line.substring(index, match.index)+"'");
        index = match.index + match[0].length;
        value = match[0].substring(3, match[0].length - 2)
        values.push(`parameters('${value}')`);
    }
    if (index == line.length) {
        values.push("'\n'");
    } else {
        values.push("'" + line.substring(index) + "\n'");
    }
    return values;
}

let args = process.argv.slice(2);
if (!args[0] || args[0] === "" || !fs.existsSync(args[0])) {
    console.error("You must specify the source template file to use.");
    process.exit(1);
}

let template = JSON.parse(fs.readFileSync(args[0], "utf-8"));

if (!args[1] || args[1] == "" || !fs.existsSync(args[1])) {
    console.error("You must specify the shell file to use.");
    process.exit(1); 
}

if (args[2] && args[2] != "" && !fs.existsSync(args[2])) {
    console.error("You must specify the location of the script_url.txt file.")
    process.exit(1)
}

const script_url = fs.readFileSync(args[2], "utf-8")

processEmbeddedLines(args[1]).then(x => {
    const index = template.resources.findIndex(t => t.type == "Microsoft.Compute/virtualMachineScaleSets")
    template.variables.scriptValue = x
    console.log(JSON.stringify(template, null, 4))
});

