const https = require('https');

const PACKAGE = '@mariozechner/pi-coding-agent';
const DAYS = 7; // days old

const url = `https://registry.npmjs.org/${encodeURIComponent(PACKAGE)}`;

https.get(url, (res) => {
  let data = '';
  res.on('data', (chunk) => data += chunk);
  res.on('end', () => {
    const registry = JSON.parse(data);
    const timeMap = registry.time;
    const versions = Object.keys(registry.versions);

    // Filter out non-version keys (like 'created', 'modified')
    const realVersions = versions.filter(v => /^[0-9]/.test(v));

    // Map to [{version, date}]
    let candidates = realVersions.map(version => ({
      version,
      date: new Date(timeMap[version])
    }));

    // Sort by date descending
    candidates.sort((a, b) => b.date - a.date);

    // Find latest version at least N days old
    const now = new Date();
    const threshold = new Date(now - DAYS*24*60*60*1000);

    const chosen = candidates.find(({date}) => date <= threshold);

    if(!chosen) {
      console.error(`No version found older than ${DAYS} days.`);
      process.exit(1);
    }

    console.log(`Installing version ${chosen.version} published at ${chosen.date.toISOString()}`);

    // Spawn npm install -g ...
    const { spawn } = require('child_process');
    const npm = spawn('npm', ['install', '-g', `${PACKAGE}@${chosen.version}`], { stdio: 'inherit' });

    npm.on('exit', code => process.exit(code));
  });
});
