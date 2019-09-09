const { spawn } = require('child_process');
const fs = require('fs');

if (!String.prototype.endsWith) {
  String.prototype.endsWith = function(search, this_len) {
    if (this_len === undefined || this_len > this.length) {
      this_len = this.length;
    }
    return this.substring(this_len - search.length, this_len) === search;
  };
}

const ROOT_PATH = "C:\\code\\Sava";

function replaceInFile(file, text, newText) {
  let data = fs.readFileSync(file).toString("utf-8");

  if (data.indexOf(newText) == -1) {
    data = data.replace(text, newText);

    fs.writeFileSync(file, data);
  }
}

replaceInFile(`${ROOT_PATH}/mono/build.ps1`, 'Start-Process cmd -ArgumentList "/C npm run server"', '# Start-Process cmd -ArgumentList "/C npm run server"')

let p = spawn('cmd.exe');

p.stderr.pipe(process.stderr);

let executionPlan = [
  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: `cd mono` },
  // { expect: `${ROOT_PATH}\\Platform>`, command: `yarn install`, successCheck: `Done in ` },
  
  // { expect: `${ROOT_PATH}\\Platform>`, command: `cd server\\build` },

  { expect: `${ROOT_PATH}\\mono>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}\\mono> `, command: `.\\build.ps1 -Build`, errorCheck: `Build finished with errors` },
  { expect: `PS ${ROOT_PATH}\\mono> `, command: `.\\build.ps1 -Restore`, successCheck: `Upgrade successful` },

  { expect: `PS ${ROOT_PATH}\\mono> `, command: `exit` },

  { expect: `${ROOT_PATH}\\mono>`, command: `cd ..` },

  // { expect: `PS ${ROOT_PATH}\\mono> `, command: `.\\build.ps1 -ExecuteScripts` },

  // { expect: `${ROOT_PATH}\\Platform\\Server\\build>`, command: `start.cmd`, successCheck: `psake succeeded executing ` },
  // { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `Invoke-psake Build`, successCheck: `psake succeeded executing psakefile.ps1` },
  // { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `Invoke-psake Restore-Database-Oracle`, successCheck: `psake succeeded executing psakefile.ps1` },
  // { expect: `PS ${ROOT_PATH}\\Platform\\Server\\build> `, command: `exit` },

  // { expect: `${ROOT_PATH}\\Platform\\Server\\build>`, command: `cd ../../../` },
  
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

  { expect: `${ROOT_PATH}>`, command: `cd mono\\client` },
  // { expect: `${ROOT_PATH}\\Platform\\Client>`, command: `npm install` },
  // { expect: `${ROOT_PATH}\\Platform\\Client>`, command: `bower install` },
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `npm run server` },
  
];

function fail() {
  process.stderr.write("FAILED!\n");
  process.exit(1);
}

let state = 0;
let buffer = "";

p.stdout.on('data', (data) => {
  
  buffer += data.toString("utf-8");

  process.stdout.write(data);

  let current = executionPlan[state];
  let previous = executionPlan[state - 1];

  // console.log("current =", current);
  // console.log("previous =", previous);
  // console.log("state =", state);

  if (previous && previous.errorCheck && buffer.indexOf(previous.errorCheck) != -1) {
    fail();
  }
  else if (current && buffer.endsWith(current.expect)) {

    if (previous && previous.successCheck && buffer.indexOf(previous.successCheck) == -1) {
      fail();
    } 

    state++;
    buffer = "";

    p.stdin.write(current.command + "\n");
  }

});


