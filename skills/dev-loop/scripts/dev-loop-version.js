"use strict";

const SUPPORTED_SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$/;

function parseSupportedSemver(value) {
  if (typeof value !== "string") return null;
  const match = SUPPORTED_SEMVER.exec(value);
  if (!match) return null;
  return {
    raw: value,
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    beta: match[4] === undefined ? null : Number(match[4]),
  };
}

function compareSupportedSemver(left, right) {
  for (const key of ["major", "minor", "patch"]) {
    if (left[key] !== right[key]) return left[key] < right[key] ? -1 : 1;
  }
  if (left.beta === right.beta) return 0;
  if (left.beta === null) return 1;
  if (right.beta === null) return -1;
  return left.beta < right.beta ? -1 : 1;
}

module.exports = {
  compareSupportedSemver,
  parseSupportedSemver,
};
