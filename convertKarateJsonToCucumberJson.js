const fs = require('fs');

// Function to convert a single karateJson to cucumberJson structure
function convertOne(inputJson) {
    if (!inputJson.scenarioResults || !Array.isArray(inputJson.scenarioResults)) {
        console.error(`Error: inputJson.scenarioResults is not an array for ${inputJson.relativePath}`);
        return null;
    }

    const elements = inputJson.scenarioResults.map(scenario => ({
        start_timestamp: new Date(scenario.startTime).toISOString(),
        line: scenario.line,
        name: scenario.name,
        description: scenario.description,
        id: scenario.refId,
        type: 'scenario',
        keyword: 'Scenario',
        steps: scenario.stepResults.map(step => ({
            result: {
                duration: step.durationMillis * 1_000_000, // ms → ns
                status: step.failed ? 'failed' : 'passed'
            },
            line: step.line,
            name: step.name,
            match: {
                location: step.match ? step.match.location : 'unknown'
            },
            keyword: step.keyword
        }))
    }));

    return {
        line: inputJson.line,
        name: inputJson.name,
        description: inputJson.name, // using name as description
        id: inputJson.packageQualifiedName,
        keyword: 'Feature',
        uri: inputJson.relativePath,
        tags: [],
        elements: elements
    };
}

// Main: process args
// Usage: node convertKarateJsonToCucumberJson.js out.json in1.json in2.json ...
const args = process.argv.slice(2);

if (args.length < 2) {
    console.error("Usage: node convertKarateJsonToCucumberJson.js <outputFile> <inputFile1> [<inputFile2> ...]");
    process.exit(1);
}

const outputFile = args[0];
const inputFiles = args.slice(1);

const outputJson = [];

for (const inputFile of inputFiles) {
    try {
        const data = fs.readFileSync(inputFile, 'utf8');
        const inputJson = JSON.parse(data);
        const converted = convertOne(inputJson);
        if (converted) {
            outputJson.push(converted);
        }
    } catch (err) {
        console.error(`Error processing file ${inputFile}:`, err);
    }
}

// Write concatenated cucumber JSON
try {
    fs.writeFileSync(outputFile, JSON.stringify(outputJson, null, 4), 'utf8');
    console.log(`File ${outputFile} has been saved with ${outputJson.length} features.`);
} catch (err) {
    console.error(`Error writing file ${outputFile}:`, err);
}
