const fs = require('fs');

const sysMsg = fs.readFileSync('system message whats.txt', 'utf8');

const filesToUpdate = ['sallon whats.json', 'n8n-workflow.json', 'n8n-workflow latest.json', 'latest insta.json'];

filesToUpdate.forEach(file => {
  if (!fs.existsSync(file)) return;
  const flow = JSON.parse(fs.readFileSync(file, 'utf8'));
  let updated = false;

  flow.nodes.forEach(n => {
    // 1. Update AI Agent system message
    if (n.parameters && n.parameters.options && typeof n.parameters.options.systemMessage === 'string') {
      n.parameters.options.systemMessage = sysMsg;
      updated = true;
    }

    // 2. Update check_availability description
    if (n.name === 'check_availability') {
      const newDesc = 'Use this tool to check available time slots for a service with a specific staff member on a given date. Returns an array of slots {time, booked}, queue status (mode: "queue"), or if blocked: true. For multi-person bookings, all persons must be with the same specialist; call this tool for that specialist to see all available slots for the day, allowing the customer to pick preferred times (whether consecutive or separated). CRITICAL: You must ONLY show and offer slots where booked=false. Slots where booked=true are ALREADY TAKEN and MUST NEVER be offered. NEVER tell the customer a time is available before running this tool.';
      n.parameters.toolDescription = newDesc;
      n.parameters.description = newDesc;
      updated = true;
    }

    // 3. Update create_booking description
    if (n.name === 'create_booking') {
      const newDesc = 'Use this tool to create a booking ONLY after ALL booking fields are collected AND the customer explicitly confirmed. This validates availability and blocked dates automatically. If it returns an error (409), tell the customer the issue and ask them to pick another time/date. Parameters: serviceId (UUID), branchId (UUID), staffId (UUID), date (YYYY-MM-DD), time (HH:mm, or comma-separated times for multiple persons e.g. "16:30, 19:00"), name (customer name), phone (customer phone), durationMode ("time" or "queue"), durationMinutes (number), paymentMethod ("cash"), notes (optional), personsCount (number, default 1: for multi-person bookings with the same specialist, pass the number of persons and their selected times; the system creates discrete slots for each person and returns ONE combined payment link for the total deposit).';
      n.parameters.toolDescription = newDesc;
      n.parameters.description = newDesc;
      updated = true;
    }
  });

  if (updated) {
    fs.writeFileSync(file, JSON.stringify(flow, null, 2), 'utf8');
    console.log('Successfully updated', file);
  }
});
