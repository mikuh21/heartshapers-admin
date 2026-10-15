begin;

-- VIP is an account-level entitlement. Keep VIP users in the normal "user"
-- role, but let their server-managed app_metadata membership tier grant access.
create or replace function public.has_game_access(p_game_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'membership_tier', 'regular') = 'vip'
    or coalesce(
      exists (
        select 1
        from public.game_purchases purchase
        where purchase.game_id = game.id
          and purchase.user_id = auth.uid()
      ),
      false
    )
    or coalesce(
      (
        select override_row.access_status
        from public.user_game_access override_row
        where override_row.game_id = game.id
          and override_row.user_id = auth.uid()
      ),
      case when game.is_locked then 'locked' else 'free' end
    ) = 'free'
  from public.games game
  where game.id = p_game_id;
$$;

-- VIP accounts should never need to submit a payment for book content.
drop policy if exists payment_submissions_customer_insert
  on public.payment_submissions;
create policy payment_submissions_customer_insert
  on public.payment_submissions for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and admin_id is null
    and reviewed_at is null
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'membership_tier', 'regular') <> 'vip'
  );

-- Preserve the existing purchase-validation rules for games, and additionally
-- prevent VIP accounts from creating paid game payment submissions.
drop policy if exists game_payment_submissions_customer_insert
  on public.game_payment_submissions;
create policy game_payment_submissions_customer_insert
  on public.game_payment_submissions for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and admin_id is null
    and reviewed_at is null
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'membership_tier', 'regular') <> 'vip'
    and split_part(proof_image_url, '/', 1) = auth.uid()::text
    and exists (
      select 1
      from public.games game
      where game.id = game_payment_submissions.game_id
        and game.price = game_payment_submissions.amount
        and game.price > 0
        and coalesce(
          (
            select access_override.access_status
            from public.user_game_access access_override
            where access_override.user_id = auth.uid()
              and access_override.game_id = game_payment_submissions.game_id
          ),
          case when game.is_locked then 'locked' else 'free' end
        ) = 'locked'
    )
    and not exists (
      select 1
      from public.game_purchases purchase
      where purchase.user_id = auth.uid()
        and purchase.game_id = game_payment_submissions.game_id
    )
  );

commit;
