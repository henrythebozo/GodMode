-- Cards members hold at other banks (Amex, Chase, ...), kept so the app can
-- show every card in one row. Display data only: the artwork the app draws,
-- issuer and product names, the network and the last 4 digits. Slate never
-- asks for or stores a full card number or security code, and can't charge
-- these cards.

create table public.linked_cards (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  design       text not null check (design ~ '^[a-z0-9_]{1,40}$'),
  issuer       text not null check (char_length(issuer) between 1 and 40),
  product      text not null check (char_length(product) between 1 and 40),
  network      text not null check (network in ('visa', 'mastercard', 'amex', 'discover')),
  last4        char(4) not null check (last4 ~ '^[0-9]{4}$'),
  holder_name  text not null check (char_length(holder_name) between 1 and 60),
  nickname     text check (nickname is null or char_length(nickname) between 1 and 40),
  created_at   timestamptz not null default now()
);

create index linked_cards_user_idx on public.linked_cards (user_id, created_at);
create unique index linked_cards_once on public.linked_cards (user_id, design, last4);

alter table public.linked_cards enable row level security;
create policy "Read own linked cards" on public.linked_cards
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.linked_cards from anon, authenticated;
grant select on public.linked_cards to authenticated;

-- Add a card. Up to 20 per member; the same design and last 4 only once.
create function public.add_linked_card(
  p_design text,
  p_issuer text,
  p_product text,
  p_network text,
  p_last4 text,
  p_holder_name text,
  p_nickname text default null
)
returns public.linked_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_design text := lower(trim(coalesce(p_design, '')));
  v_last4 text := trim(coalesce(p_last4, ''));
  v_network text := lower(trim(coalesce(p_network, '')));
  v_row public.linked_cards;
begin
  if v_design !~ '^[a-z0-9_]{1,40}$' then
    raise exception using message = 'Pick a card design.', hint = 'invalid_design';
  end if;
  if v_last4 !~ '^[0-9]{4}$' then
    raise exception using message = 'Enter the last 4 digits of the card.', hint = 'invalid_last4';
  end if;
  if trim(coalesce(p_issuer, '')) = '' or trim(coalesce(p_product, '')) = '' then
    raise exception using message = 'Enter the bank and the card name.', hint = 'invalid_card';
  end if;
  if v_network not in ('visa', 'mastercard', 'amex', 'discover') then
    raise exception using message = 'Pick the card network.', hint = 'invalid_network';
  end if;
  if trim(coalesce(p_holder_name, '')) = '' then
    raise exception using message = 'Enter the name on the card.', hint = 'invalid_name';
  end if;

  -- Serialise one member's adds so the limit can't be raced past.
  perform 1 from public.profiles where id = v_user for update;
  if (select count(*) from public.linked_cards where user_id = v_user) >= 20 then
    raise exception using message = 'You can add up to 20 cards.', hint = 'too_many_cards';
  end if;
  if exists (select 1 from public.linked_cards
             where user_id = v_user and design = v_design and last4 = v_last4) then
    raise exception using message = 'You''ve already added this card.', hint = 'card_exists';
  end if;

  insert into public.linked_cards (user_id, design, issuer, product, network, last4, holder_name, nickname)
  values (
    v_user,
    v_design,
    left(trim(p_issuer), 40),
    left(trim(p_product), 40),
    v_network,
    v_last4,
    left(trim(p_holder_name), 60),
    nullif(left(trim(coalesce(p_nickname, '')), 40), '')
  )
  returning * into v_row;
  return v_row;
end;
$$;

create function public.remove_linked_card(p_card_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  delete from public.linked_cards where id = p_card_id and user_id = v_user;
  if not found then
    raise exception using message = 'Card not found.', hint = 'card_not_found';
  end if;
end;
$$;

revoke all on function
  public.add_linked_card(text, text, text, text, text, text, text),
  public.remove_linked_card(uuid)
from public, anon;

grant execute on function
  public.add_linked_card(text, text, text, text, text, text, text),
  public.remove_linked_card(uuid)
to authenticated;
