alter table public.admin_logs enable row level security;

revoke all on table public.admin_logs from public, anon, authenticated;
grant select, insert on table public.admin_logs to authenticated;
grant select, insert on table public.admin_logs to service_role;

drop policy if exists admin_logs_admin_select on public.admin_logs;
create policy admin_logs_admin_select
  on public.admin_logs for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin'));

drop policy if exists admin_logs_admin_insert on public.admin_logs;
create policy admin_logs_admin_insert
  on public.admin_logs for insert to authenticated
  with check (
    admin_email = (auth.jwt() ->> 'email')
    and (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin')
  );

create or replace function public.verify_payment_submission(payment_id uuid, note text default null)
returns public.payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  book_title text;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('admin', 'super_admin') then
    raise exception 'Only admins can verify payments';
  end if;

  select * into payment
  from public.payment_submissions
  where id = payment_id
  for update;

  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status <> 'pending' then raise exception 'Only pending payments can be verified'; end if;

  update public.payment_submissions
  set status = 'verified', admin_id = current_admin, reviewed_at = now(), admin_notes = nullif(trim(note), '')
  where id = payment_id
  returning * into payment;

  insert into public.book_purchases (user_id, book_id, payment_id)
  values (payment.user_id, payment.book_id, payment.id)
  on conflict (user_id, book_id) do nothing;

  select title into book_title from public.books where id = payment.book_id;
  begin
    insert into public.admin_logs (action, details, admin_email)
    values (
      'payment_verified',
      jsonb_build_object(
        'target_type', 'payment_submission',
        'target_id', payment.id,
        'target_name', book_title,
        'payment_id', payment.id,
        'book_id', payment.book_id,
        'book_title', book_title,
        'customer_id', payment.user_id,
        'amount', payment.amount,
        'reference_number', payment.reference_number
      ),
      current_email
    );
  exception when others then
    raise warning 'Admin audit log write failed for payment verification';
  end;

  return payment;
end;
$$;

create or replace function public.reject_payment_submission(payment_id uuid, note text)
returns public.payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  book_title text;
  safe_note text;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('admin', 'super_admin') then
    raise exception 'Only admins can reject payments';
  end if;
  if nullif(trim(note), '') is null then raise exception 'A rejection reason is required'; end if;

  select * into payment from public.payment_submissions where id = payment_id for update;
  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status <> 'pending' then raise exception 'Only pending payments can be rejected'; end if;

  update public.payment_submissions
  set status = 'rejected', admin_id = current_admin, reviewed_at = now(), admin_notes = trim(note)
  where id = payment_id
  returning * into payment;

  select title into book_title from public.books where id = payment.book_id;
  safe_note := case
    when trim(note) ~* '(password|passphrase|pin|token|secret|credential|api[ _-]?key|bearer)' then '[redacted]'
    else left(trim(note), 300)
  end;

  begin
    insert into public.admin_logs (action, details, admin_email)
    values (
      'payment_rejected',
      jsonb_build_object(
        'target_type', 'payment_submission',
        'target_id', payment.id,
        'target_name', book_title,
        'payment_id', payment.id,
        'book_id', payment.book_id,
        'book_title', book_title,
        'customer_id', payment.user_id,
        'amount', payment.amount,
        'reference_number', payment.reference_number,
        'rejection_reason', safe_note
      ),
      current_email
    );
  exception when others then
    raise warning 'Admin audit log write failed for payment rejection';
  end;

  return payment;
end;
$$;

revoke all on function public.verify_payment_submission(uuid, text) from public;
revoke all on function public.reject_payment_submission(uuid, text) from public;
grant execute on function public.verify_payment_submission(uuid, text) to authenticated;
grant execute on function public.reject_payment_submission(uuid, text) to authenticated;