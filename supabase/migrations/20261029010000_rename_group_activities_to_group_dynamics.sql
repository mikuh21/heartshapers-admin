-- Rename the old "Group Activities" taxonomy label to "Group Dynamics".
-- Keep category IDs intact where possible so any existing relationships remain valid.
-- If Ministry already has an active Group Dynamics category, retire the redundant
-- Group Activities category only when it has no game placements.

UPDATE public.categories AS c
SET name = 'Group Dynamics'
FROM public.pillars AS p
WHERE c.pillar_id = p.id
  AND p.name <> 'Ministry'
  AND lower(c.name) = 'group activities';

UPDATE public.categories AS old_category
SET deleted_at = COALESCE(old_category.deleted_at, now())
FROM public.pillars AS p
WHERE old_category.pillar_id = p.id
  AND p.name = 'Ministry'
  AND lower(old_category.name) = 'group activities'
  AND EXISTS (
    SELECT 1
    FROM public.categories AS current_category
    WHERE current_category.pillar_id = old_category.pillar_id
      AND lower(current_category.name) = 'group dynamics'
      AND current_category.deleted_at IS NULL
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.game_placements AS gp
    WHERE gp.category_id = old_category.id
  );

-- If Ministry has no existing Group Dynamics category, rename the old category
-- in place instead of creating a second category.
UPDATE public.categories AS c
SET name = 'Group Dynamics'
FROM public.pillars AS p
WHERE c.pillar_id = p.id
  AND p.name = 'Ministry'
  AND lower(c.name) = 'group activities'
  AND NOT EXISTS (
    SELECT 1
    FROM public.categories AS existing
    WHERE existing.pillar_id = c.pillar_id
      AND lower(existing.name) = 'group dynamics'
      AND existing.deleted_at IS NULL
  );
