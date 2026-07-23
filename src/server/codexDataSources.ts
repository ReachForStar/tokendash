import { accessSync, constants, existsSync, realpathSync } from 'node:fs';
import { delimiter, join, resolve } from 'node:path';
import { homedir } from 'node:os';

const KNOWN_CODEX_HOME_SUFFIXES = [
  ['.codex'],
  ['.trae', 'cli'],
  ['.codex-traex'],
  ['.aidencodex'],
  ['Library', 'Application Support', 'AidenCodex'],
  ['Library', 'Application Support', 'Traex-Codex'],
];

/** Expand a user-entered Codex home path into an absolute local filesystem path. */
function normalizeHomePath(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const expanded = trimmed === '~'
    ? homedir()
    : trimmed.startsWith('~/')
      ? join(homedir(), trimmed.slice(2))
      : trimmed;
  return resolve(expanded);
}

/** Split a path-list environment value into individual Codex home candidates. */
function parseHomeList(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(delimiter)
    .flatMap(part => part.split(','))
    .map(part => normalizeHomePath(part))
    .filter((part): part is string => part !== null);
}

/** Return the canonical de-duplication key for a path, preserving missing paths. */
function canonicalPathKey(path: string): string {
  try {
    return existsSync(path) ? realpathSync(path) : path;
  } catch {
    return path;
  }
}

/** De-duplicate filesystem paths while preserving the caller's ordering. */
function uniquePaths(paths: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const path of paths) {
    const key = canonicalPathKey(path);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(path);
  }
  return result;
}

/** Built-in Codex-compatible homes that TokenDash can safely scan by default. */
function defaultCodexHomes(): string[] {
  return KNOWN_CODEX_HOME_SUFFIXES.map(parts => join(homedir(), ...parts));
}

/** Resolve all Codex-compatible data homes that should contribute to usage. */
export function getCodexHomes(): string[] {
  const baseHomes = process.env.CODEX_HOME
    ? parseHomeList(process.env.CODEX_HOME)
    : defaultCodexHomes();
  const extraHomes = [
    ...parseHomeList(process.env.TOKENDASH_CODEX_HOME),
    ...parseHomeList(process.env.TOKENDASH_CODEX_HOMES),
  ];
  return uniquePaths([...baseHomes, ...extraHomes]);
}

/** Return every live/archived transcript directory for all configured homes. */
export function getCodexSessionDirs(): string[] {
  return uniquePaths(getCodexHomes().flatMap(home => [
    join(home, 'sessions'),
    join(home, 'archived_sessions'),
  ]));
}

/** Check whether at least one configured Codex transcript directory is readable. */
export function isCodexSessionDirAccessible(): boolean {
  return getCodexSessionDirs().some(dir => {
    try {
      accessSync(dir, constants.R_OK);
      return true;
    } catch {
      return false;
    }
  });
}
