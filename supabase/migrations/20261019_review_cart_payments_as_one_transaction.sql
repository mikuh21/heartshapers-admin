begin;

-- A cart payment uses the same user, GCash reference, and proof object for each
-- item. These RPCs review every pending row in that cart as one database transaction.
create or replace function public.review_cart_payment(
  p_user_id uuid,
  p_reference_number text,
  p_proof_image_url text,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  book_payment public.payment_submissions%rowtype;
  game_payment public.game_payment_submissions%rowtype;
  affected integer := 0;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('admin','super_admin') then
    raise exception 'Only admins can review payments';
  end if;
  if p_action not in ('verify','reject') then raise exception 'Invalid review action'; end if;
  if p_action = 'reject' and nullif(trim(p_note), '') is null then
    raise exception 'A rejection reason is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_user_id::text || ':' || p_reference_number || ':' || p_proof_image_url, 0
  ));

  if not exists (
    select 1 from public.payment_submissions
    where user_id=p_user_id and reference_number=p_reference_number
      and proof_image_url=p_proof_image_url and status='pending'
    union all
    select 1 from public.game_payment_submissions
    where user_id=p_user_id and reference_number=p_reference_number
      and proof_image_url=p_proof_image_url and status='pending'
  ) then raise exception 'No pending items were found for this transaction'; end if;

  for book_payment in
    select * from public.payment_submissions
    where user_id=p_user_id and reference_number=p_reference_number
      and proof_image_url=p_proof_image_url and status='pending'
    for update
  loop
    update public.payment_submissions
    set status=case when p_action='verify' then 'verified' else 'rejected' end,
        admin_id=current_admin, reviewed_at=now(),
        admin_notes=case when p_action='reject' then trim(p_note) else null end
    where id=book_payment.id;

    if p_action='verify' then
      insert into public.book_purchases(user_id,book_id,payment_id)
      values(book_payment.user_id,book_payment.book_id,book_payment.id)
      on conflict(user_id,book_id) do nothing;
    end if;
    affected := affected + 1;
  end loop;

  for game_payment in
    select * from public.game_payment_submissions
    where user_id=p_user_id and reference_number=p_reference_number
      and proof_image_url=p_proof_image_url and status='pending'
    for update
  loop
    update public.game_payment_submissions
    set status=case when p_action='verify' then 'verified' else 'rejected' end,
        admin_id=current_admin, reviewed_at=now(),
        admin_notes=case when p_action='reject' then trim(p_note) else null end
    where id=game_payment.id;

    if p_action='verify' then
      insert into public.game_purchases(user_id,game_id,payment_id)
      values(game_payment.user_id,game_payment.game_id,game_payment.id)
      on conflict(user_id,game_id) do nothing;
    end if;
    affected := affected + 1;
  end loop;

  insert into public.admin_logs(action, details, admin_email)
  values(
    case when p_action='verify' then 'cart_payment_verified' else 'cart_payment_rejected' end,
    jsonb_build_object('user_id',p_user_id,'reference_number',p_reference_number,
      'proof_image_url',p_proof_image_url,'items_reviewed',affected,
      'rejection_reason',case when p_action='reject' then trim(p_note) else null end),
    current_email
  );

  return jsonb_build_object('status',case when p_action='verify' then 'verified' else 'rejected' end,
    'items_reviewed',affected);
end;
$$;

revoke all on function public.review_cart_payment(uuid,text,text,text,text) from public, anon;
grant execute on function public.review_cart_payment(uuid,text,text,text,text) to authenticated;

commit;
