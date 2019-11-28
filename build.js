const ROOT_PATH = "c:\\Code\\Sava";

let executionPlan = [

  { command: `set PROMPT=$P$G` },

  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: '"c:\\Program Files\\Git\\bin\\sh.exe" -c "find . -type d -name \\"node_modules\\" -exec rm -rf {} +"', errorCheck: `cannot remove` },
  { expect: `${ROOT_PATH}>`, command: '"c:\\Program Files\\Git\\bin\\sh.exe" -c "find . -type d -name \\"bower_components\\" -exec rm -rf {} +"', errorCheck: `cannot remove` },  

  { expect: `${ROOT_PATH}>`, command: `cd mono` },

  { expect: `${ROOT_PATH}\\mono>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -Build -SkipBasic`, errorCheck: [`Build finished with errors`, `Could not find a part of the path`, 'An unexpected error occoured', "-- FAILED"] },
  { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -Restore -DatabaseType Oracle -SkipBasic -DatabaseOracleDomain "adacta-fintech.com"`, successCheck: `Upgrade successful` },
  { expect: `PS ${ROOT_PATH}\\mono> `, command: `exit` },

  { expect: `${ROOT_PATH}\\mono>`, command: `cd ..` },

  { expect: `${ROOT_PATH}>`, command: `cd implementation/build/` },
  { expect: `${ROOT_PATH}\\implementation\\build>`, command: `start.cmd`, successCheck: `psake succeeded executing ` },  
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Build`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Execute-Scripts`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `Invoke-psake Import-CSV`, successCheck: `psake succeeded executing psakefile.ps1` },
  { expect: `PS ${ROOT_PATH}\\implementation\\build> `, command: `exit` },
  
  { expect: `${ROOT_PATH}\\implementation\\build>`, command: `cd ../..` },
  
  { expect: `${ROOT_PATH}>`, command: `cd implementation/configuration/` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn install`, successCheck: `Done in ` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run es-setup`, successCheck: `Succeeded: `, errorCheck: [`No Living connections`, `Error: No elasticsearch manifest configuration`, `TypeError: Cannot read property 'length' of undefined`] },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run build`, successCheck: `Done in `, errorCheck: "Error: ENOENT: no such file or directory" },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run resolve_translations`, successCheck: `Done in ` },
  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `yarn run publishAll`, successCheck: `Done in ` },

  { expect: `${ROOT_PATH}\\implementation\\Configuration>`, command: `cd ../..` },

  { expect: `${ROOT_PATH}>`, command: `cd mono\\client` },
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `npm install`},
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `bower install`},
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `npm run server` },
  
];

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

function replaceInFile(file, text, newText) {
  let data = fs.readFileSync(file).toString("utf-8");

  if (newText === '' || data.indexOf(newText) == -1) {
    data = data.replace(text, newText);

    fs.writeFileSync(file, data);
  }
}

function fail() {
  console.error("FAILED!");
  process.exit(1);
}

function errorFromArrayOccurred(array, buffer) {
  if (Array.isArray(array)) {
    for (let i = 0; i < array.length; i++) {
      const error = array[i];
      if (buffer.indexOf(error.toUpperCase()) != -1) {
        return true;
      }
    }
  }

  return false;
}

function failOnError(item, buffer) {
  if (item && item.errorCheck && (
    errorFromArrayOccurred(item.errorCheck, buffer) || 
    typeof item.errorCheck == "string" && buffer.indexOf(item.errorCheck.toUpperCase()) != -1)
  ) {

    fail();
  }
}

replaceInFile(`${ROOT_PATH}/mono/build.ps1`, '/nr:false `', '/nr:true `')
replaceInFile(`${ROOT_PATH}/mono/build.ps1`, '/verbosity:minimal `', '/verbosity:normal `')
replaceInFile(`${ROOT_PATH}/mono/build.ps1`, 'Start-Process cmd -ArgumentList "/C npm run server"', '# Start-Process cmd -ArgumentList "/C npm run server"')
replaceInFile(`${ROOT_PATH}/implementation/build/psakefile.ps1`, '$dbORCLdomain="si.corp.adacta-group.com"', '$dbORCLdomain="adacta-fintech.com"')

let p = spawn('cmd.exe');

let state = 0;
let buffer = "";
let errorBuffer = "";

p.stderr.on('data', (data) => {
  errorBuffer += data.toString("utf-8").toUpperCase();
  process.stderr.write(data);

  let previous = executionPlan[state - 1];

  failOnError(previous, errorBuffer);
});

p.stdout.on('data', (data) => {
  
  buffer += data.toString("utf-8").toUpperCase();

  process.stdout.write(data);

  let current = executionPlan[state];
  let previous = executionPlan[state - 1];

  failOnError(previous, buffer);

  if (current && (!current.expect || buffer.endsWith(current.expect.toUpperCase()))) {

    if (previous && previous.successCheck && buffer.indexOf(previous.successCheck.toUpperCase()) == -1) {
      fail();
    } 

    state++;
    buffer = "";
    errorBuffer = "";

    p.stdin.write(current.command + "\n");
  }

});


