const ROOT_PATH = "c:\\Code\\Sava";

let executionPlan = [

  { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },

  { expect: `${ROOT_PATH}>`, command: `powershell` },

  { expect: `PS ${ROOT_PATH}> `, command: 'docker rm -f es' },
  
  { expect: `PS ${ROOT_PATH}> `, detached: true, commands: [
    { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },
    { expect: `${ROOT_PATH}>`, command: `powershell` },
    { expect: `PS ${ROOT_PATH}> `, command: `cd implementation` },
    { expect: `PS ${ROOT_PATH}\\implementation> `, command: `docker run -p 9200:9200 -m 4g -e "discovery.type=single-node" --name es elasticsearch:7.9.0`, successCheck: `Active license is now [BASIC]; Security is disabled`, errorCheck: 'failed to shutdown container:' },
  ] },

  { expect: `PS ${ROOT_PATH}> `, command: 'cd implementation' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: 'git stash --include-untracked', errorCheck: ['No local changes to save', 'Permission denied', 'Cannot save the untracked files'] },
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

  { expect: `${ROOT_PATH}>`, detached: true, commands: [
    { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },
    { expect: `${ROOT_PATH}>`, command: `powershell` },
    { expect: `PS ${ROOT_PATH}> `, command: `cd mono` },
    { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -RunIS`, successCheck: `Enter 'Q' to stop IIS Express` },
  ] },

  { expect: `${ROOT_PATH}>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}> `, command: `cd implementation` },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `.\\build.ps1 -Build -ExecuteScripts -TargetLayer hr`, successCheck: [`Upgrade successful`, `0 Error(s)`], errorCheck: ['401 Unauthorized'] },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `yarn install`, errorCheck: ['Failed to download', 'Error:']},
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `.\\build.ps1 -ImportCSV`, successCheck: 'Done in ' },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `exit` },

  { expect: `${ROOT_PATH}>`, detached: true, commands: [
    { expect: process.cwd() + `>`, command: `cd ${ROOT_PATH}` },
    { expect: `${ROOT_PATH}>`, command: `powershell` },
    { expect: `PS ${ROOT_PATH}> `, command: `cd mono` },
    { expect: `PS ${ROOT_PATH}\\Mono> `, command: `.\\build.ps1 -RunServer`, successCheck: `AdInsure is initialized and ready to use.` },
  ] },

  { expect: `${ROOT_PATH}>`, command: `cd implementation/` },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run validate-workspace -e environment.local.json`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },
  { expect: `${ROOT_PATH}\\implementation>`, command: `yarn run publish-workspace -e environment.local.json`, successCheck: `Done in `, errorCheck: [`[ERROR]`] },

  { expect: `${ROOT_PATH}\\implementation>`, command: `powershell` },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `.\\build.ps1 -ExecutePostPublishScripts -TargetLayer hr`, successCheck: ['Upgrade successful', 'No new scripts need to be executed - completing.'], errorCheck: ['401 Unauthorized', 'No new scripts need to be executed - completing'] },
  { expect: `PS ${ROOT_PATH}\\implementation> `, command: `exit` },

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

function runExecutionPlan(executionPlan, callback) {
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
  
  p.stdout.on('data', async (data) => {
    
    buffer += data.toString("utf-8").toUpperCase();
  
    process.stdout.write(data);
  
    let current = executionPlan[state];
    let previous = executionPlan[state - 1];
  
    failOnError(previous, buffer);
  
    if (!current && executionPlan.indexOf(previous) == executionPlan.length - 1 && previous && previous.successCheck && taskWasSuccessful(previous.successCheck, buffer)) {
      callback()
    }
    else if (current && (!current.expect || buffer.endsWith(current.expect.toUpperCase()))) {
  
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
          if (current.detached) {

            let runExecutionPlanPromisify = require("util").promisify(runExecutionPlan)
            await runExecutionPlanPromisify(current.commands)
          } else {
            p.stdin.write(current.command + "\n");
            break;
          }
        }
      }
    }
  
  });
}

replaceInFile(`${ROOT_PATH}/mono/build.ps1`, 'dotnet build "$root\\AdInsure.sln" --configuration $buildConfiguration', 'dotnet build "$root\\AdInsure.sln" --configuration $buildConfiguration -v n /nr:true')
replaceInFile(`${ROOT_PATH}/implementation/build.ps1`, 'dotnet build "plugins/Server.Plugins.$pluginsTargetlayer.sln" -c Debug -o $binDir', 'dotnet build "plugins/Server.Plugins.$pluginsTargetlayer.sln" -c Debug -o $binDir -v n /nr:true')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"title": "SI - Localhost"', '"title": "HR - Localhost"')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"targetLayer": "sava-si"', '"targetLayer": "sava-hr"')
replaceInFile(`${ROOT_PATH}/implementation/.adi/environments/environment.local.json`, '"localCurrency": "EUR"', '"localCurrency": "HRK"')

runExecutionPlan(executionPlan)
