-- 094 — Record which project a donation was made to.
--
-- Migration 085 seeded the spec's project list into project_categories and
-- noted that showing/hiding it is a Dashboard action. The list is served (GET
-- /api/project-categories) and the visibility switch is served (GET
-- /api/donation-options → projects_visible), but the app never rendered
-- either: DonationOptions.projectsVisible was parsed into a model field that
-- no screen read, so "donate to a specific project" was unreachable.
--
-- Making it reachable needs somewhere to put the answer. donations.category
-- already exists but belongs to the in-kind flow (item category), so this is
-- its own column rather than an overloaded one.
ALTER TABLE donations
  ADD COLUMN IF NOT EXISTS project_slug VARCHAR(64);

-- Reporting groups donations by project.
CREATE INDEX IF NOT EXISTS idx_donations_project
  ON donations (project_slug)
  WHERE project_slug IS NOT NULL;
