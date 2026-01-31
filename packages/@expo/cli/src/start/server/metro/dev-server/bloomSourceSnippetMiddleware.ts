import type { MetroConfig } from '@expo/metro/metro';
import type connect from 'connect';
import fs from 'node:fs/promises';
import path from 'node:path';

export function bloomSourceSnippetMiddleware(
  metroConfig: Pick<MetroConfig, 'projectRoot'>
): connect.NextHandleFunction {
  const projectRoot = path.resolve(metroConfig.projectRoot!);

  return async (req, res, next) => {
    if (req.method !== 'POST') return next();
    if (!('rawBody' in req) || !(req as any).rawBody) {
      res.statusCode = 406;
      return res.end('Source snippet requires JSON body');
    }

    let body: unknown;
    try {
      body = JSON.parse((req as any).rawBody as string);
    } catch {
      res.statusCode = 400;
      return res.end('Invalid JSON');
    }

    const file = (body as { file?: unknown })?.file;
    const lineNumber = (body as { lineNumber?: unknown })?.lineNumber;
    const contextLinesRaw = (body as { contextLines?: unknown })?.contextLines;
    const contextLines =
      typeof contextLinesRaw === 'number' && Number.isFinite(contextLinesRaw)
        ? Math.max(0, Math.min(20, Math.floor(contextLinesRaw)))
        : 3;

    if (
      typeof file !== 'string' ||
      typeof lineNumber !== 'number' ||
      !Number.isFinite(lineNumber)
    ) {
      res.statusCode = 400;
      return res.end('Expected { file: string, lineNumber: number }');
    }

    const resolved = path.resolve(file);
    if (resolved !== projectRoot && !resolved.startsWith(projectRoot + path.sep)) {
      res.statusCode = 403;
      return res.end('File is outside project root');
    }

    try {
      const contents = await fs.readFile(resolved, 'utf8');
      const lines = contents.split(/\r?\n/);
      const totalLines = lines.length;
      const safeLine = Math.max(1, Math.min(totalLines, Math.floor(lineNumber)));
      const startLine = Math.max(1, safeLine - contextLines);
      const endLine = Math.min(totalLines, safeLine + contextLines);
      const slice = lines.slice(startLine - 1, endLine);

      res.setHeader('Content-Type', 'application/json');
      res.end(
        JSON.stringify({
          file: resolved,
          lineNumber: safeLine,
          startLine,
          endLine,
          lines: slice,
        })
      );
    } catch (error) {
      res.statusCode = 404;
      res.end(`Failed to read file: ${String(error)}`);
    }
  };
}
