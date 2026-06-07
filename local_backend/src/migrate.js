const config = require('./config');
const { LocalDatabase } = require('./db');

async function main() {
  const db = new LocalDatabase({ databaseUrl: config.databaseUrl });
  try {
    await db.migrate();
    console.log('[postgres] migrations complete');
  } finally {
    await db.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
