#!/usr/bin/env node
'use strict';

const path = require('path');
const nestedScript = path.join(__dirname, '..', 'skills', 'grok-search', 'scripts', 'grok-search.cjs');

// Outer wrapper delegates execution directly to the canonical nested CLI implementation.
const cli = require(nestedScript);

if (require.main === module) {
  cli.run();
}

module.exports = cli;
