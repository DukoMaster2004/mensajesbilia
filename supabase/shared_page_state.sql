create table if not exists public.shared_page_state (
  collection text not null,
  item_key text not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (collection, item_key)
);

alter table public.shared_page_state enable row level security;

create or replace function public.set_shared_page_state_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shared_page_state_updated_at on public.shared_page_state;
create trigger shared_page_state_updated_at
before update on public.shared_page_state
for each row execute function public.set_shared_page_state_updated_at();

notify pgrst, 'reload schema';
