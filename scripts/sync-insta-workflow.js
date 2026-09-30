const fs = require('fs');
const path = require('path');

const rootDir = __dirname ? path.join(__dirname, '..') : '.';
const instaPath = path.join(rootDir, 'latest insta.json');
const sysmsgPath = path.join(rootDir, 'system-message-dynamic.txt');

const wf = JSON.parse(fs.readFileSync(instaPath, 'utf8'));
let sysmsg = fs.readFileSync(sysmsgPath, 'utf8').trim();

// Note for Instagram: ensure channelType is instagram
sysmsg = sysmsg.replace('channelType: "whatsapp"', 'channelType: "instagram"');

// On Instagram, phone number is not sent by header, so ensure rule:
if (!sysmsg.includes('INSTAGRAM PHONE COLLECTION')) {
  sysmsg = sysmsg.replace(
    '### Step 5: Summary & Explicit Confirmation',
    `### Step 5: Summary & Explicit Confirmation
- On Instagram: Because phone number is not pre-loaded, ALWAYS ask the customer for their mobile phone number if not yet provided: "يرجى تزويدنا برقم الجوال لتأكيد الحجز والتواصل:".`
  );
}

const checkDesc = 'Use this tool to check available time slots for a service with a specific staff member on a given date. Returns an array of slots {time, booked}, queue status (mode: "queue"), or if blocked: true. For multi-person bookings, pass personsCount (e.g. 2 or 3) to automatically verify and return only slots that can fit all persons consecutively. CRITICAL: You must ONLY show and offer slots where booked=false. Slots where booked=true are ALREADY TAKEN and MUST NEVER be offered. NEVER tell the customer a time is available before running this tool.';

const bookingDesc = 'Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm or null for queue), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), notes (optional), personsCount (number, default 1: number of persons/appointments to book; automatically multiplies deposit and extends duration).';

const branchesDesc = 'Returns the list of active branches. If only ONE branch is open in the salon, automatically use it directly without asking the customer. If TWO OR MORE branches are open, ask the customer to choose their preferred branch among the open branches. NEVER offer or mention branches where all days are closed.';

const staffDesc = 'Use this tool AFTER the customer selects a branch. Pass branchId (UUID) to get all available services and their assigned specialists/staff at that branch.';

wf.nodes.forEach(node => {
  if (node.name === 'AI Agent1') {
    node.parameters.options.systemMessage = '=' + sysmsg;
  }

  if (node.name === 'check_availability') {
    node.parameters.toolDescription = checkDesc;
    node.parameters.description = checkDesc;
    node.parameters.url = 'https://salonnoon.net/api/availability';
    if (!node.parameters.queryParameters) node.parameters.queryParameters = { parameters: [] };
    const params = node.parameters.queryParameters.parameters;
    const exists = params.find(p => p.name === 'personsCount');
    if (!exists) {
      params.push({ name: 'personsCount', value: "={{ $fromAI('personsCount', '1', 'string') }}" });
    }
  }

  if (node.name === 'create_booking') {
    node.parameters.toolDescription = bookingDesc;
    node.parameters.description = bookingDesc;
    node.parameters.url = 'https://salonnoon.net/api/booking';
    if (!node.parameters.bodyParameters) node.parameters.bodyParameters = { parameters: [] };
    const params = node.parameters.bodyParameters.parameters;
    const exists = params.find(p => p.name === 'personsCount');
    if (!exists) {
      params.push({ name: 'personsCount', value: "={{ $fromAI('personsCount', '1', 'string') }}" });
    }
    const ch = params.find(p => p.name === 'channelType');
    if (ch) {
      ch.value = 'instagram';
    } else {
      params.push({ name: 'channelType', value: 'instagram' });
    }
  }

  if (node.name === 'get_branches') {
    node.parameters.toolDescription = branchesDesc;
    node.parameters.description = branchesDesc;
    node.parameters.url = 'https://salonnoon.net/api/branches?active=true';
  }

  if (node.name === 'get_staff_for_service') {
    node.parameters.toolDescription = staffDesc;
    node.parameters.description = staffDesc;
    node.parameters.url = 'https://salonnoon.net/api/services-with-staff';
  }
});

fs.writeFileSync(instaPath, JSON.stringify(wf, null, 2), 'utf8');
console.log('Successfully updated latest insta.json!');
