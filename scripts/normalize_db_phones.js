const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const envPath = path.join(rootDir, 'saloon-mostafa', '.env');
const env = fs.readFileSync(envPath, 'utf8');
const parsed = {};
env.split('\n').forEach(line => {
  const idx = line.indexOf('=');
  if (idx !== -1) {
    const k = line.slice(0, idx).trim();
    const v = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    parsed[k] = v;
  }
});

const { createClient } = require(path.join(rootDir, 'saloon-mostafa', 'node_modules', '@supabase', 'supabase-js'));
const supabase = createClient(parsed.NEXT_PUBLIC_SUPABASE_URL, parsed.SUPABASE_SERVICE_ROLE_KEY);

function normalizePhone(input) {
  if (!input) return '';
  let cleaned = String(input).trim();
  const hasPlus = cleaned.startsWith('+');
  cleaned = cleaned.replace(/\D/g, '');

  if (cleaned.startsWith('00966')) {
    cleaned = '966' + cleaned.slice(5);
  } else if (cleaned.startsWith('966')) {
    // Already starts with 966
  } else if (cleaned.startsWith('05') && cleaned.length === 10) {
    cleaned = '966' + cleaned.slice(1);
  } else if (cleaned.startsWith('5') && cleaned.length === 9) {
    cleaned = '966' + cleaned;
  } else if (hasPlus && cleaned.length >= 11) {
    return cleaned;
  } else if (cleaned.length === 10 && cleaned.startsWith('0')) {
    cleaned = '966' + cleaned.slice(1);
  }
  return cleaned;
}

async function run(apply = false) {
  console.log(`\n=== Running DB Phone Normalization (apply=${apply}) ===\n`);
  
  let modifiedCount = 0;
  let totalProcessed = 0;
  let page = 0;
  const pageSize = 1000;

  while (true) {
    const from = page * pageSize;
    const to = from + pageSize - 1;

    const { data: clients, error } = await supabase
      .from('Client')
      .select('id, name, phone, platform, platform_user_id')
      .order('createdAt', { ascending: false })
      .range(from, to);

    if (error) {
      console.error('Error fetching clients:', error);
      break;
    }

    if (!clients || clients.length === 0) break;

    totalProcessed += clients.length;
    console.log(`Processing batch ${page + 1}: ${clients.length} clients (${from} to ${to})...`);

    for (const client of clients) {
      if (!client.phone) continue;
      
      const canonical = normalizePhone(client.phone);
      if (client.phone !== canonical && canonical.length >= 9) {
        modifiedCount++;
        console.log(`[#${modifiedCount}] ID: ${client.id} | Name: "${client.name}" | Old: "${client.phone}" -> New: "${canonical}"`);
        
        if (apply) {
          const { error: updateErr } = await supabase
            .from('Client')
            .update({ phone: canonical })
            .eq('id', client.id);

          if (updateErr) {
            console.error(`  ERROR updating client ${client.id}:`, updateErr.message);
          } else {
            console.log(`  UPDATED successfully.`);
          }
        }
      }
    }

    if (clients.length < pageSize) break;
    page++;
  }

  console.log(`\nSummary: ${modifiedCount} of ${totalProcessed} clients normalized.`);
  if (!apply) {
    console.log('NOTE: Dry-run complete. No changes written. Pass --apply to execute updates.');
  } else {
    console.log('NOTE: All updates applied successfully!');
  }
}

const isApply = process.argv.includes('--apply');
run(isApply);
