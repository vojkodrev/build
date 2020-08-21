const ROOT_PATH = "c:\\Code\\Sava";

let executionPlan = [

  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: `powershell`, argv: "--clean" },
  { expect: `PS ${ROOT_PATH}> `, command: 'iisreset /stop', successCheck: 'Internet services successfully stopped', argv: "--clean" },
  { expect: `PS ${ROOT_PATH}> `, command: `cd implementation`, argv: "--clean" },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `mv .\\configuration.json ..`, argv: "--clean" },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `git clean -fdx`, argv: "--clean" },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `git reset --hard`, successCheck: 'HEAD is now at', argv: "--clean" },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `mv ..\\configuration.json .`, argv: "--clean" },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `exit`, argv: "--clean" },

  { expect: `${ROOT_PATH}>`, command: '"c:\\Program Files\\Git\\bin\\sh.exe" -c "find . -type d -name \\"node_modules\\" -exec rm -rf {} +"', errorCheck: `cannot remove` },
  
  { expect: `${ROOT_PATH}>`, command: `cd mono` },

  { expect: `${ROOT_PATH}\\mono>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -Build -SkipBasic`, successCheck: `0 Error(s)`, errorCheck: [`Build finished with errors`, `Could not find a part of the path`, 'An unexpected error occoured', "-- FAILED"] },
  { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -Restore -DatabaseType Oracle -SkipBasic`, successCheck: `Upgrade successful`, errorCheck: ['ERROR at line'] },
  { expect: `PS ${ROOT_PATH}\\mono> `, command: `exit` },

  { expect: `${ROOT_PATH}\\mono>`, command: `cd ..` },

  { expect: `${ROOT_PATH}>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}> `, command: `cd implementation` },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `.\\build.ps1 -Build -BuildPrintouts -ExecuteScripts -EnvironmentTarget si`, successCheck: `Upgrade successful`, errorCheck: ['401 Unauthorized'] },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `exit` },
  
  { expect: `${ROOT_PATH}>`, command: `cd implementation\\.adi` },
  { expect: `${ROOT_PATH}\\implementation\\.adi>`, command: `git clean -fdx` },
  { expect: `${ROOT_PATH}\\implementation\\.adi>`, command: `cd ../..` },
  
  { expect: `${ROOT_PATH}>`, command: `cd implementation/` },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run es-setup-si`, successCheck: `successfully: `, errorCheck: [`No Living connections`, `Error: No elasticsearch manifest configuration`, `TypeError: Cannot read property 'length' of undefined`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run translate-workspace`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run resolve_translations`, successCheck: `Done in ` },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run validate-workspace`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run publish-workspace`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },

  { expect: `${ROOT_PATH}\\implementation>`, command: `cd ..` },

  { expect: `${ROOT_PATH}>`, command: `cd mono\\client` },
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `yarn install`},
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `yarn run start` },
  
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
// replaceInFile(`${ROOT_PATH}/mono/build.ps1`, 'Start-Process cmd -ArgumentList "/C npm run server"', '# Start-Process cmd -ArgumentList "/C npm run server"')
// replaceInFile(`${ROOT_PATH}/implementation/build/psakefile.ps1`, '$dbORCLdomain="adacta-fintech.com"', '$dbORCLdomain=""')
replaceInFile(`${ROOT_PATH}/implementation/configuration.json`, '"targetLayer": "sava-hr"', '"targetLayer": "sava-si"')
replaceInFile(`${ROOT_PATH}/implementation/configuration.json`, '"localCurrency": "HRK"', '"localCurrency": "EUR"')

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

    buffer = "";
    errorBuffer = "";

    while (true) {
      current = executionPlan[state];

      if (!current) {
        break;
      }

      state++;

      if (!current.argv || process.argv.filter(i => i == current.argv).length > 0) {
        p.stdin.write(current.command + "\n");
        break;
      }
    }
  }

});


