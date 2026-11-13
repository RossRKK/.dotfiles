-- Branch overview per workspace root: normalized cwd -> TriageReport, or false
-- for "asked, not a git repo" (nil means the answer hasn't arrived yet, which
-- renders as a bare header rather than as an empty repo).
--
-- Cached because triage.report is async: the dashboard has to render before the
-- git work finishes, so it draws from here and is told to redraw when a fresh
-- report lands. Keyed by root so switching tabs shows that project's overview
-- immediately, without a flash of the previous one.
---@type table<string, table|false>
return {}
