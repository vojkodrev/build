const { spawn } = require('child_process');

if (!String.prototype.endsWith) {
  String.prototype.endsWith = function(search, this_len) {
    if (this_len === undefined || this_len > this.length) {
      this_len = this.length;
    }
    return this.substring(this_len - search.length, this_len) === search;
  };
}

function logWithoutNewLine(kind, text) {
  if (text.endsWith("\r\n")) {
    text = text.substring(0, text.length - 2);
  } else if (text.endsWith("\n")) {
    text = text.substring(0, text.length - 1);
  }

  console.log(kind + ":", text);
}

p = spawn('cmd.exe')

p.stderr.on('data', (data) => {
  let dataUtf8 = data.toString("utf-8");
  logWithoutNewLine("stderr", dataUtf8);

});

let state = 0;

let executionPlan = [
  { expect: process.cwd() + ">", command: "cd C:\\code\\configuration\\platform\n" },
  { expect: "C:\\code\\Configuration\\Platform>", command: "yarn install\n" },
  
  { expect: "C:\\code\\Configuration\\Platform>", command: "cd server\\build\n" },
  { expect: "C:\\code\\Configuration\\Platform\\Server\\build>", command: "start.cmd\n" },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "Invoke-psake Build\n" },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "Invoke-psake Restore-Database-MSSQL\n" },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "exit\n" },

  { expect: "C:\\code\\Configuration\\Platform\\Server\\build>", command: "cd ../../../Basic/build\n" },
  { expect: "C:\\code\\Configuration\\Basic\\build>", command: "start.cmd\n" },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "Invoke-psake Build\n" },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "Invoke-psake Execute-Scripts-MSSQL\n" },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "exit\n" },

  { expect: "C:\\code\\Configuration\\Basic\\build>", command: "cd ../../Configuration\n" },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn install\n" },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run es-setup\n" },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run publishAll\n" },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run import-test-data\n" },
  
  { expect: "C:\\code\\Configuration\\Configuration>", command: "cd ../platform/client\n" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "npm install\n" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "bower install\n" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "npm run server\n" },
  
];

p.stdout.on('data', (data) => {
  
  let dataUtf8 = data.toString("utf-8");

  logWithoutNewLine("stdout", dataUtf8);

  let r = executionPlan[state];

  if (r && dataUtf8.endsWith(r.expect)) {
    state++;

    logWithoutNewLine("stdin", r.command);
    p.stdin.write(r.command);
  }

});


