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

const ROOT_PATH = "C:\\code\\Sava";

let executionPlan = [
  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: `cd platform` },
  { expect: `${ROOT_PATH}\\Platform>`, command: `yarn install`, successCheck: `Done in ` },
  
  { expect: `${ROOT_PATH}\\Platform>`, command: `cd server\\build` },
  { expect: `${ROOT_PATH}\\Platform\\Server\\build>`, command: `start.cmd`, successCheck: `psake succeeded executing ` },
  { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `Invoke-psake Build`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `Invoke-psake Restore-Database-Oracle`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `exit` },

  { expect: `${ROOT_PATH}\\Platform\\Server\\build>`, command: `cd ../../../` },

  { expect: `${ROOT_PATH}>`, command: `cd implementation/build/` },
  { expect: `${ROOT_PATH}\\implementation\\build>`, command: `start.cmd`, successCheck: `psake succeeded executing ` },  
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Build`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Execute-Scripts`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Import-CSV`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `exit` },
  { expect: `${ROOT_PATH}\\implementation\\build>`, command: `cd ..\\configuration` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn install`, successCheck: `Done in ` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run es-setup`, successCheck: `Succeeded: ` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run publishAll`, successCheck: `Done in ` },

  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `cd ../..` },

  { expect: `${ROOT_PATH}>`, command: `cd Platform\\Client` },
  { expect: `${ROOT_PATH}\\Platform\\Client>`, command: `npm install` },
  { expect: `${ROOT_PATH}\\Platform\\Client>`, command: `bower install` },
  { expect: `${ROOT_PATH}\\Platform\\Client>`, command: `npm run server` },
  
];

let state = 0;
let buffer = "";

p.stdout.on('data', (data) => {
  
  buffer += data.toString("utf-8");

  process.stdout.write(data);

  let r = executionPlan[state];

  if (r && buffer.endsWith(r.expect)) {

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


