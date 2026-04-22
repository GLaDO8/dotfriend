#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');

const script = path.join(__dirname, '..', 'dotfriend');
const result = spawnSync(script, process.argv.slice(2), {
  stdio: 'inherit',
  shell: false
});

process.exit(result.status ?? 0);
