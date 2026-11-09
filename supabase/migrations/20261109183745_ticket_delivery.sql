-- Hinterlegung pro Ticket: Abholung (Ort/Zeit), Gästekasse oder digital (PDF im privaten Bucket).
-- Ticket-PDFs sind nur für die anfragende Person (solange zugeteilt) und Organisatoren abrufbar.

create type public.ticket_delivery_method as enum ('pickup', 'box_office', 'digital');

alter table public.ticket_requests
  add column delivery_method public.ticket_delivery_method,
  add column pickup_location text check (char_length(pickup_location) between 1 and 200),
  add column pickup_at timestamptz,
  -- Pfad im Bucket ticket-files: <club_id>/<request_id>.pdf
  add column ticket_file_path text,
  add column ticket_file_uploaded_at timestamptz;

-- ---------------------------------------------------------------------------
-- Storage-Bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ticket-files', 'ticket-files', false, 5 * 1024 * 1024, array['application/pdf'])
on conflict (id) do nothing;

-- Erwarteter Pfad der Ticketdatei einer Anfrage
create function public.ticket_file_path(p_club_id uuid, p_request_id uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_club_id::text || '/' || p_request_id::text || '.pdf';
$$;

-- Anfrage-ID aus einem Dateipfad lesen; null bei fremden oder ungültigen Pfaden
create function public.ticket_file_request_id(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select (regexp_match(
    p_name,
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.pdf$'
  ))[1]::uuid;
$$;

-- Lesen: anfragende Person (nur solange zugeteilt) oder Organisator
create function public.can_read_ticket_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ticket_requests r
    where r.id = public.ticket_file_request_id(p_name)
      and public.ticket_file_path(r.club_id, r.id) = p_name
      and (
        public.is_club_organizer(r.club_id)
        or (r.requested_by = auth.uid() and r.status = 'allocated' and r.ticket_file_path = p_name)
      )
  );
$$;

-- Hochladen/Ersetzen: Organisatoren, nur für zugeteilte Tickets
create function public.can_upload_ticket_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ticket_requests r
    where r.id = public.ticket_file_request_id(p_name)
      and public.ticket_file_path(r.club_id, r.id) = p_name
      and r.status = 'allocated'
      and public.is_club_organizer(r.club_id)
  );
$$;

-- Löschen: Organisatoren, unabhängig vom Status
create function public.can_delete_ticket_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ticket_requests r
    where r.id = public.ticket_file_request_id(p_name)
      and public.ticket_file_path(r.club_id, r.id) = p_name
      and public.is_club_organizer(r.club_id)
  );
$$;

create policy "ticket_files_select"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'ticket-files' and public.can_read_ticket_file(name));

create policy "ticket_files_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'ticket-files' and public.can_upload_ticket_file(name));

create policy "ticket_files_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'ticket-files' and public.can_upload_ticket_file(name))
  with check (bucket_id = 'ticket-files' and public.can_upload_ticket_file(name));

create policy "ticket_files_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'ticket-files' and public.can_delete_ticket_file(name));

-- ---------------------------------------------------------------------------
-- RPCs für Organisatoren
-- ---------------------------------------------------------------------------

-- Hinterlegung für mehrere zugeteilte Tickets festlegen. Wechselt ein Ticket von digital weg,
-- wird die Datei gelöst; die Pfade kommen zurück, damit der Client sie aus dem Storage löscht.
create function public.set_ticket_delivery(
  p_request_ids uuid[],
  p_method public.ticket_delivery_method,
  p_pickup_location text,
  p_pickup_at timestamptz
)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_location text := nullif(btrim(coalesce(p_pickup_location, '')), '');
begin
  if exists (
    select 1
    from public.ticket_requests r
    where r.id = any (p_request_ids)
      and not public.is_club_organizer(r.club_id)
  ) or cardinality(p_request_ids) = 0 then
    raise exception 'Nur Organisatoren können die Hinterlegung festlegen.';
  end if;

  if exists (
    select 1
    from public.ticket_requests r
    where r.id = any (p_request_ids)
      and r.status <> 'allocated'
  ) then
    raise exception 'Die Hinterlegung gibt es nur für zugeteilte Tickets.';
  end if;

  if p_method = 'pickup' and v_location is null then
    raise exception 'Bitte gib an, wo die Tickets abgeholt werden.';
  end if;

  return query
  with previous as (
    select id, ticket_file_path
    from public.ticket_requests
    where id = any (p_request_ids)
  ),
  updated as (
    update public.ticket_requests r
    set delivery_method = p_method,
        pickup_location = case when p_method = 'pickup' then v_location end,
        pickup_at = case when p_method = 'pickup' then p_pickup_at end,
        ticket_file_path = case when p_method = 'digital' then r.ticket_file_path end,
        ticket_file_uploaded_at = case when p_method = 'digital' then r.ticket_file_uploaded_at end
    where r.id = any (p_request_ids)
    returning r.id
  )
  select p.ticket_file_path
  from previous p
  join updated u on u.id = p.id
  where p_method <> 'digital'
    and p.ticket_file_path is not null;
end;
$$;

-- Hochgeladene Datei an ein zugeteiltes Ticket hängen (Hinterlegung wird digital)
create function public.attach_ticket_file(p_request_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.ticket_requests%rowtype;
  v_path text;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if v_request.id is null or not public.is_club_organizer(v_request.club_id) then
    raise exception 'Nur Organisatoren können Tickets hinterlegen.';
  end if;

  if v_request.status <> 'allocated' then
    raise exception 'PDFs gibt es nur für zugeteilte Tickets.';
  end if;

  v_path := public.ticket_file_path(v_request.club_id, v_request.id);

  if not exists (
    select 1 from storage.objects where bucket_id = 'ticket-files' and name = v_path
  ) then
    raise exception 'Die Datei wurde nicht gefunden. Lade sie bitte erneut hoch.';
  end if;

  update public.ticket_requests
  set delivery_method = 'digital',
      pickup_location = null,
      pickup_at = null,
      ticket_file_path = v_path,
      ticket_file_uploaded_at = now()
  where id = p_request_id;

  return v_path;
end;
$$;

-- Datei vom Ticket lösen; liefert den Pfad, damit der Client die Datei aus dem Storage löscht
create function public.detach_ticket_file(p_request_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.ticket_requests%rowtype;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if v_request.id is null or not public.is_club_organizer(v_request.club_id) then
    raise exception 'Nur Organisatoren können Tickets hinterlegen.';
  end if;

  update public.ticket_requests
  set ticket_file_path = null,
      ticket_file_uploaded_at = null
  where id = p_request_id;

  return v_request.ticket_file_path;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.ticket_file_path(uuid, uuid),
  public.ticket_file_request_id(text),
  public.can_read_ticket_file(text),
  public.can_upload_ticket_file(text),
  public.can_delete_ticket_file(text),
  public.set_ticket_delivery(uuid[], public.ticket_delivery_method, text, timestamptz),
  public.attach_ticket_file(uuid),
  public.detach_ticket_file(uuid)
from public, anon, authenticated;

-- Die Prüffunktionen laufen in Storage-Policies im Kontext von authenticated
grant execute on function
  public.can_read_ticket_file(text),
  public.can_upload_ticket_file(text),
  public.can_delete_ticket_file(text),
  public.set_ticket_delivery(uuid[], public.ticket_delivery_method, text, timestamptz),
  public.attach_ticket_file(uuid),
  public.detach_ticket_file(uuid)
to authenticated;
