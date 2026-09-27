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

workflowFiles.forEach(file => {
  const filePath = path.join(rootDir, file);
  if (!fs.existsSync(filePath)) {
    console.log(`Skipping ${file} (not found)`);
    return;
  }
  
  const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let updatedAgent = false;
  let updatedWait = false;
  let updatedCheck = false;

  (content.nodes || []).forEach(node => {
    // 1. Update AI Agent system message
    if (node.name === 'AI Agent1' || (node.type && node.type.includes('agent'))) {
      if (node.parameters && node.parameters.options) {
        node.parameters.options.systemMessage = '=' + systemMessageText;
        updatedAgent = true;
      }
    }

    // 2. Update Wait node to 8 seconds
    if (node.name === 'Wait' || node.type === 'n8n-nodes-base.wait') {
      if (node.parameters) {
        node.parameters.amount = 8;
        node.parameters.unit = 'seconds';
        updatedWait = true;
      }
    }

    // 3. Update check_availability tool description
    if (node.name === 'check_availability') {
      if (node.parameters) {
        node.parameters.description = "MANDATORY before offering or confirming any booking time. Returns unbooked time slots (slots), queue status (mode: 'queue'), or if the specialist is off (blocked: true). CRITICAL: Filter and offer ONLY slots where booked=false. Slots where booked=true must NEVER be offered. NEVER tell the customer a time is available before running this tool.";
        updatedCheck = true;
      }
    }
  });

  fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
  console.log(`Updated ${file}: agent=${updatedAgent}, wait=${updatedWait}, check_availability=${updatedCheck}`);
});
