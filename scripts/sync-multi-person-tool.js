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

const newBookingDesc = 'Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm or null for queue), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), notes (optional), personsCount (number, default 1: number of persons/appointments to book; automatically multiplies deposit and extends duration).';

const newCheckDesc = 'Use this tool to check available time slots for a service with a specific staff member on a given date. Returns an array of slots {time, booked}, queue status (mode: "queue"), or if blocked: true. For multi-person bookings, pass personsCount (e.g. 2 or 3) to automatically verify and return only slots that can fit all persons consecutively. CRITICAL: You must ONLY show and offer slots where booked=false. Slots where booked=true are ALREADY TAKEN and MUST NEVER be offered. NEVER tell the customer a time is available before running this tool.';

workflowFiles.forEach(file => {
  const filePath = path.join(rootDir, file);
  if (!fs.existsSync(filePath)) {
    console.log(`Skipping ${file} (not found)`);
    return;
  }
  
  const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let updatedAgent = false;
  let updatedBooking = false;
  let updatedCheck = false;

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
        node.parameters.toolDescription = newBookingDesc;
        node.parameters.description = newBookingDesc;

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
          updatedBooking = true;
        }
      }
    }

    // 3. Update check_availability tool node
    if (node.name === 'check_availability') {
      if (node.parameters) {
        node.parameters.toolDescription = newCheckDesc;
        node.parameters.description = newCheckDesc;

        if (node.parameters.queryParameters && Array.isArray(node.parameters.queryParameters.parameters)) {
          const params = node.parameters.queryParameters.parameters;
          const exists = params.find(p => p.name === 'personsCount');
          if (!exists) {
            params.push({
              name: 'personsCount',
              value: "={{ $fromAI('personsCount', '1', 'string') }}"
            });
          } else {
            exists.value = "={{ $fromAI('personsCount', '1', 'string') }}";
          }
          updatedCheck = true;
        }
      }
    }
  });

  fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
  console.log(`Updated ${file}: agent=${updatedAgent}, bookingTool=${updatedBooking}, checkTool=${updatedCheck}`);
});
