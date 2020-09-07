const ROOT_PATH = "c:\\Code\\Sava";

let executionPlan = [

  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}> `, command: 'iisreset /stop', successCheck: 'Internet services successfully stopped' },
  { expect: `PS ${ROOT_PATH}> `, command: 'cd implementation' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'git stash --include-untracked', errorCheck: 'No local changes to save' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'mv .\\.adi\\environments\\environment.local.json ..', errorCheck: ['Cannot find path'] },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'git clean -fdx' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'git reset --hard', successCheck: 'HEAD is now at' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'mv ..\\environment.local.json .adi\\environments', errorCheck: ['Cannot find path'] },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'git stash pop', errorCheck: 'conflict' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'exit' },

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
  
  { expect: `${ROOT_PATH}>`, command: 'docker rm -f es' },
  { expect: `${ROOT_PATH}>`, command: 'docker run -d -p 9200:9200 --name es registry.adacta-fintech.com/adinsure/platform/es' },

  { expect: `${ROOT_PATH}>`, command: `cd implementation/` },
  // { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run es-setup-si`, successCheck: `successfully: `, errorCheck: [`No Living connections`, `Error: No elasticsearch manifest configuration`, `TypeError: Cannot read property 'length' of undefined`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run translate-workspace -e environment.local.json`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run resolve_translations`, successCheck: `Done in ` },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run validate-workspace -e environment.local.json`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run publish-workspace -e environment.local.json`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },

  // { expect: `${ROOT_PATH}\\implementation>`, command: `powershell` },
  // { expect: `PS ${ROOT_PATH}\\implementation> `, command: `.\\build.ps1 -ExecuteScripts -EnvironmentTarget si -PostPublish`, successCheck: ['Upgrade successful', 'No new scripts need to be executed - completing.'], errorCheck: ['401 Unauthorized', 'No new scripts need to be executed - completing'] },
  // { expect: `PS ${ROOT_PATH}\\implementation> `, command: `exit` },

  { expect: `${ROOT_PATH}\\implementation>`, command: `cd ..` },

  { expect: `${ROOT_PATH}>`, command: `cd mono\\client` },
  { expect: `${ROOT_PATH}\\mono\\client>`, command: `yarn install`, errorCheck: 'Failed to download'},
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

function taskWasSuccessful(successCheck, buffer) { 
  if (successCheck) {
    if (Array.isArray(successCheck)) {

      for (let item of successCheck) {
        if (taskWasSuccessful(item, buffer)) {
          return true;
        }
      }

      return false;

    } else {
      return buffer.indexOf(successCheck.toUpperCase()) != -1
    }
  }

  return true;

}

replaceInFile(`${ROOT_PATH}/mono/build.ps1`, '/nr:false `', '/nr:true `')
replaceInFile(`${ROOT_PATH}/mono/build.ps1`, '/verbosity:minimal `', '/verbosity:normal `')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"title": "HR - Localhost"', '"title": "SI - Localhost"')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"targetLayer": "sava-hr"', '"targetLayer": "sava-si"')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"localCurrency": "HRK"', '"localCurrency": "EUR"')

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

    if (previous && !taskWasSuccessful(previous.successCheck, buffer)) {
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


