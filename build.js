const { spawn } = require('child_process');

if (!String.prototype.endsWith) {
  String.prototype.endsWith = function(search, this_len) {
    if (this_len === undefined || this_len > this.length) {
      this_len = this.length;
    }
    return this.substring(this_len - search.length, this_len) === search;
  };
}

let p = spawn('cmd.exe');

p.stderr.pipe(process.stderr);

let executionPlan = [
  { expect: process.cwd() + ">", command: "cd C:\\code\\configuration" },

  { expect: "C:\\code\\Configuration>", command: "cd platform" },
  { expect: "C:\\code\\Configuration\\Platform>", command: "yarn install", successCheck: "Done in " },
  
  { expect: "C:\\code\\Configuration\\Platform>", command: "cd server\\build" },
  { expect: "C:\\code\\Configuration\\Platform\\Server\\build>", command: "start.cmd", successCheck: "psake succeeded executing " },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "Invoke-psake Build", successCheck: "psake succeeded executing psakefile.ps1" },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "Invoke-psake Restore-Database-MSSQL", successCheck: "psake succeeded executing psakefile.ps1" },
  { expect: "PS C:\\code\\Configuration\\Platform\\Server\\build> ", command: "exit" },

  { expect: "C:\\code\\Configuration\\Platform\\Server\\build>", command: "cd ../../../" },

  { expect: "C:\\code\\Configuration>", command: "cd Basic/build" },
  { expect: "C:\\code\\Configuration\\Basic\\build>", command: "start.cmd", successCheck: "psake succeeded executing " },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "Invoke-psake Build", successCheck: "psake succeeded executing psakefile.ps1" },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "Invoke-psake Execute-Scripts-MSSQL", successCheck: "psake succeeded executing psakefile.ps1" },
  { expect: "PS C:\\code\\Configuration\\Basic\\build> ", command: "exit" },

  { expect: "C:\\code\\Configuration\\Basic\\build>", command: "cd ../../" },

  { expect: "C:\\code\\Configuration>", command: "cd configuration" },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn install", successCheck: "Done in " },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run es-setup", successCheck: "Succeeded: " },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run publishAll", successCheck: "Done in " },
  { expect: "C:\\code\\Configuration\\Configuration>", command: "yarn run import-test-data", successCheck: "Testing data imported successfully." },
  
  { expect: "C:\\code\\Configuration\\Configuration>", command: "cd .." },
  
  { expect: "C:\\code\\Configuration>", command: "cd platform/client" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "npm install" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "bower install" },
  { expect: "C:\\code\\Configuration\\Platform\\Client>", command: "npm run server" },
  
];

let state = 0;
let buffer = "";

p.stdout.on('data', (data) => {
  
  let dataUtf8 = data.toString("utf-8");

  buffer += dataUtf8;

  process.stdout.write(data);

  let r = executionPlan[state];

  if (r && dataUtf8.endsWith(r.expect)) {

    let previous = executionPlan[state - 1];
    if (previous && previous.successCheck && buffer.indexOf(previous.successCheck) == -1) {
      process.stderr.write("FAILED!\n");
      process.exit(1);
    } 

    state++;
    buffer = "";

    p.stdin.write(r.command + "\n");
  }

});


