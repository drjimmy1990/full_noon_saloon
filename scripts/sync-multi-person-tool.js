const fs = require('fs');
const path = require('path');

const rootDir = path.join(__dirname, '..');
const systemMessagePath = path.join(rootDir, 'system message whats.txt');
const systemMessageText = fs.readFileSync(systemMessagePath, 'utf8').trim();

const workflowFiles = [
  'n8n-workflow latest.json',
  'sallon whats.json',
  'n8n-workflow.json'
];

const newToolDesc = 'Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm or null for queue), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), notes (optional), personsCount (number, default 1: number of persons/appointments to book; automatically multiplies deposit and extends duration).';

workflowFiles.forEach(file => {
  const filePath = path.join(rootDir, file);
  if (!fs.existsSync(filePath)) {
    console.log(`Skipping ${file} (not found)`);
    return;
  }
  
  const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let updatedAgent = false;
  let updatedTool = false;

  (content.nodes || []).forEach(node => {
    // 1. Update AI Agent system message
    if (node.name === 'AI Agent1' || (node.type && node.type.includes('agent'))) {
      if (node.parameters && node.parameters.options) {
        node.parameters.options.systemMessage = '=' + systemMessageText;
        updatedAgent = true;
      }
    }

    // 2. Update create_booking tool node
    if (node.name === 'create_booking') {
      if (node.parameters) {
        node.parameters.toolDescription = newToolDesc;
        node.parameters.description = newToolDesc;

        if (node.parameters.bodyParameters && Array.isArray(node.parameters.bodyParameters.parameters)) {
          const params = node.parameters.bodyParameters.parameters;
          const exists = params.find(p => p.name === 'personsCount');
          if (!exists) {
            params.push({
              name: 'personsCount',
              value: "={{ $fromAI('personsCount', '1', 'string') }}"
            });
          } else {
            exists.value = "={{ $fromAI('personsCount', '1', 'string') }}";
          }
          updatedTool = true;
        }
      }
    }
  });

  fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
  console.log(`Updated ${file}: agent=${updatedAgent}, tool=${updatedTool}`);
});
