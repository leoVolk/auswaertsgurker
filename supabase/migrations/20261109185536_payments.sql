-- Etappe 5: Zahlungen per PayPal.Me-Link des Fanclubs
--
-- Die App wickelt keine Zahlungen ab. Mitglieder melden ihre Zahlung (open -> reported, nur über
-- report_payment), alles andere setzen Organisatoren (set_payment_status). Gilt für Fahrten und Tickets.

create type public.payment_status as enum ('open', 'reported', 'confirmed', 'refunded');

-- ---------------------------------------------------------------------------
-- PayPal.Me-Name des Fanclubs
-- ---------------------------------------------------------------------------

alter table public.clubs
  add column paypal_me text check (paypal_me ~ '^[A-Za-z0-9]{1,20}$');

grant update (paypal_me) on public.clubs to authenticated;

-- ---------------------------------------------------------------------------
-- Zahlungsstatus an Anmeldungen und Ticketanfragen
-- ---------------------------------------------------------------------------

alter table public.trip_registrations
  add column payment_status public.payment_status not null default 'open',
  -- Betrag beim Melden bzw. Bestätigen (Preis kann sich später ändern)
  add column payment_amount_cents integer check (payment_amount_cents between 0 and 100000),
  add column payment_status_changed_at timestamptz;

alter table public.ticket_requests
  add column payment_status public.payment_status not null default 'open',
  add column payment_amount_cents integer check (payment_amount_cents between 0 and 100000),
  add column payment_status_changed_at timestamptz;

-- Optional: Ticket-PDF erst nach bestätigter Zahlung abrufbar
alter table public.ticket_rounds
  add column download_requires_payment boolean not null default false;

grant insert (download_requires_payment), update (download_requires_payment)
  on public.ticket_rounds to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Mitglied meldet eigene Zahlungen (open -> reported); liefert die Anzahl gemeldeter Posten
create function public.report_payment(
  p_trip_registration_ids uuid[] default '{}',
  p_ticket_request_ids uuid[] default '{}'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_trips integer;
  v_tickets integer;
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  update public.trip_registrations r
  set payment_status = 'reported',
      payment_status_changed_at = now(),
      payment_amount_cents = t.price_cents
  from public.trips t
  where r.id = any (p_trip_registration_ids)
    and t.id = r.trip_id
    and r.user_id = v_user
    and r.status in ('requested', 'confirmed')
    and r.payment_status = 'open'
    and t.price_cents > 0;

  get diagnostics v_trips = row_count;

  update public.ticket_requests q
  set payment_status = 'reported',
      payment_status_changed_at = now(),
      payment_amount_cents = c.price_cents
  from public.ticket_categories c
  where q.id = any (p_ticket_request_ids)
    and c.id = q.category_id
    and q.requested_by = v_user
    and q.status = 'allocated'
    and q.payment_status = 'open'
    and c.price_cents > 0;

  get diagnostics v_tickets = row_count;

  if v_trips + v_tickets = 0 then
    raise exception 'Hier ist nichts mehr offen. Vielleicht hast du die Zahlung schon gemeldet.';
  end if;

  return v_trips + v_tickets;
end;
$$;

-- Organisatoren setzen den Zahlungsstatus (bestätigen, zurück auf offen, erstatten)
create function public.set_payment_status(
  p_status public.payment_status,
  p_trip_registration_ids uuid[] default '{}',
  p_ticket_request_ids uuid[] default '{}'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trips integer;
  v_tickets integer;
begin
  if p_status = 'reported' then
    raise exception 'Zahlungen melden nur Mitglieder selbst.';
  end if;

  if cardinality(p_trip_registration_ids) + cardinality(p_ticket_request_ids) = 0
    or exists (
      select 1 from public.trip_registrations
      where id = any (p_trip_registration_ids) and not public.is_club_organizer(club_id)
    )
    or exists (
      select 1 from public.ticket_requests
      where id = any (p_ticket_request_ids) and not public.is_club_organizer(club_id)
    ) then
    raise exception 'Nur Organisatoren können Zahlungen bestätigen.';
  end if;

  if p_status = 'refunded' and (
    exists (
      select 1 from public.trip_registrations
      where id = any (p_trip_registration_ids) and payment_status not in ('confirmed', 'refunded')
    )
    or exists (
      select 1 from public.ticket_requests
      where id = any (p_ticket_request_ids) and payment_status not in ('confirmed', 'refunded')
    )
  ) then
    raise exception 'Erstatten kann man nur bestätigte Zahlungen.';
  end if;

  update public.trip_registrations r
  set payment_status = p_status,
      payment_status_changed_at = now(),
      payment_amount_cents = case when p_status = 'open' then null else coalesce(r.payment_amount_cents, t.price_cents) end
  from public.trips t
  where r.id = any (p_trip_registration_ids)
    and t.id = r.trip_id;

  get diagnostics v_trips = row_count;

  update public.ticket_requests q
  set payment_status = p_status,
      payment_status_changed_at = now(),
      payment_amount_cents = case when p_status = 'open' then null else coalesce(q.payment_amount_cents, c.price_cents) end
  from public.ticket_categories c
  where q.id = any (p_ticket_request_ids)
    and c.id = q.category_id;

  get diagnostics v_tickets = row_count;

  return v_trips + v_tickets;
end;
$$;

-- Belegung plus eigener Zahlungsstatus (Rückgabetyp ändert sich -> neu anlegen)
drop function public.get_trip_stats(uuid);

create function public.get_trip_stats(p_club_id uuid)
returns table (
  trip_id uuid,
  taken_seats integer,
  waitlist_count integer,
  my_registration_id uuid,
  my_status public.registration_status,
  my_waitlist_position integer,
  my_payment_status public.payment_status
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    t.id,
    (count(r.id) filter (where r.status in ('requested', 'confirmed')))::integer,
    (count(r.id) filter (where r.status = 'waitlist'))::integer,
    mine.id,
    mine.status,
    case when mine.status = 'waitlist' then (
      select count(*)::integer + 1
      from public.trip_registrations w
      where w.trip_id = t.id
        and w.status = 'waitlist'
        and (w.status_changed_at, w.created_at) < (mine.status_changed_at, mine.created_at)
    ) end,
    mine.payment_status
  from public.trips t
  left join public.trip_registrations r on r.trip_id = t.id
  left join public.trip_registrations mine on mine.trip_id = t.id and mine.user_id = auth.uid()
  where t.club_id = p_club_id
    and public.is_club_member(p_club_id)
  group by t.id, mine.id, mine.status, mine.status_changed_at, mine.created_at, mine.payment_status;
$$;

-- Ticket-PDF: bei entsprechender Einstellung erst nach bestätigter Zahlung für das Mitglied lesbar
create or replace function public.can_read_ticket_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ticket_requests r
    join public.ticket_rounds rd on rd.id = r.round_id
    where r.id = public.ticket_file_request_id(p_name)
      and public.ticket_file_path(r.club_id, r.id) = p_name
      and (
        public.is_club_organizer(r.club_id)
        or (
          r.requested_by = auth.uid()
          and r.status = 'allocated'
          and r.ticket_file_path = p_name
          and (not rd.download_requires_payment or r.payment_status = 'confirmed')
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.report_payment(uuid[], uuid[]),
  public.set_payment_status(public.payment_status, uuid[], uuid[]),
  public.get_trip_stats(uuid)
from public, anon, authenticated;

grant execute on function
  public.report_payment(uuid[], uuid[]),
  public.set_payment_status(public.payment_status, uuid[], uuid[]),
  public.get_trip_stats(uuid)
to authenticated;
