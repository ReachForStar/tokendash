import { mkdtempSync, rmSync, writeFileSync, appendFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildUsageFileIndex, clearUsageFileIndexMemory, type UsageFileRef } from '../../server/usageFileIndex.js';

let tempRoot = '';
let previousIndexDir: string | undefined;

beforeEach(() => {
  tempRoot = mkdtempSync(join(tmpdir(), 'tokendash-usage-index-'));
  previousIndexDir = process.env.TOKENDASH_USAGE_INDEX_DIR;
  process.env.TOKENDASH_USAGE_INDEX_DIR = join(tempRoot, 'index');
  clearUsageFileIndexMemory();
});

afterEach(() => {
  clearUsageFileIndexMemory();
  if (previousIndexDir === undefined) {
    delete process.env.TOKENDASH_USAGE_INDEX_DIR;
  } else {
    process.env.TOKENDASH_USAGE_INDEX_DIR = previousIndexDir;
  }
  rmSync(tempRoot, { recursive: true, force: true });
});

describe('buildUsageFileIndex', () => {
  it('persists parsed file values and reuses unchanged files after memory is cleared', () => {
    const sourcePath = join(tempRoot, 'session.jsonl');
    writeFileSync(sourcePath, 'first');
    let parseCalls = 0;
    const parseFile = (file: UsageFileRef) => {
      parseCalls += 1;
      return readFileSync(file.path, 'utf-8');
    };

    const first = buildUsageFileIndex({
      cacheName: 'test-agent',
      parserVersion: 'v1',
      files: [{ path: sourcePath }],
      parseFile,
    });

    expect(first.values).toEqual(['first']);
    expect(first.parsedFiles).toBe(1);
    expect(first.reusedFiles).toBe(0);
    expect(parseCalls).toBe(1);

    clearUsageFileIndexMemory();
    const second = buildUsageFileIndex({
      cacheName: 'test-agent',
      parserVersion: 'v1',
      files: [{ path: sourcePath }],
      parseFile,
    });

    expect(second.values).toEqual(['first']);
    expect(second.parsedFiles).toBe(0);
    expect(second.reusedFiles).toBe(1);
    expect(parseCalls).toBe(1);

    appendFileSync(sourcePath, '\nsecond');
    const third = buildUsageFileIndex({
      cacheName: 'test-agent',
      parserVersion: 'v1',
      files: [{ path: sourcePath }],
      parseFile,
    });

    expect(third.values).toEqual(['first\nsecond']);
    expect(third.parsedFiles).toBe(1);
    expect(parseCalls).toBe(2);
  });

  it('invalidates cached values when the parser version changes', () => {
    const sourcePath = join(tempRoot, 'session.jsonl');
    writeFileSync(sourcePath, 'payload');
    let parseCalls = 0;
    const parseFile = (file: UsageFileRef) => {
      parseCalls += 1;
      return readFileSync(file.path, 'utf-8');
    };

    buildUsageFileIndex({
      cacheName: 'test-agent',
      parserVersion: 'v1',
      files: [{ path: sourcePath }],
      parseFile,
    });
    clearUsageFileIndexMemory();
    const second = buildUsageFileIndex({
      cacheName: 'test-agent',
      parserVersion: 'v2',
      files: [{ path: sourcePath }],
      parseFile,
    });

    expect(second.parsedFiles).toBe(1);
    expect(second.reusedFiles).toBe(0);
    expect(parseCalls).toBe(2);
  });
});
