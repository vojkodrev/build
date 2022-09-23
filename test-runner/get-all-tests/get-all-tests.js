
const { program } = require('commander');
const util = require('util');
const glob = util.promisify(require("glob"));
const acorn = require("acorn");
const fs = require("fs");
const readFile = util.promisify(fs.readFile);
const path = require('path');
const RecursiveIterator = require("recursive-iterator");

(async () => {
  program
    .option('-d, --dir <directory>')
    .parse();

  const options = program.opts();

  const jsFiles = await glob("**/*.js", { cwd: options.dir }); 
  
  for (const jsFile of jsFiles) {
    const jsFilePath = path.join(options.dir, jsFile);
    const jsFileContent = await readFile(jsFilePath);
    const parsedJsFile = acorn.parse(jsFileContent, {ecmaVersion: 2020});

    for (const item1 of new RecursiveIterator(parsedJsFile)) {

      if (item1?.node?.expression?.callee?.name === 'describe') {

        const describeLiteral = item1.node.expression.arguments[0].value;

        for (const item2 of new RecursiveIterator(item1.node.expression)) {

          if (item2?.node?.expression?.callee?.name === 'it') {
            const itLiteral = item2.node.expression.arguments[0].value;
            console.log(`${describeLiteral} ${itLiteral}`);
          }
        }
      }
    }
  }
})().catch(e => {
  console.error(e);
});
