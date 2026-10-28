-- Slate: profiles, multi-currency wallets, cards and a double-entry style ledger.
--
-- Money is stored as integer minor units (cents) in bigint columns, never floats.
-- Clients may only READ their own rows (row level security). Every operation
-- that moves money runs inside one of the SECURITY DEFINER functions at the end
-- of this file, which validate input, lock the wallets involved and write the
-- balance change and its ledger rows in a single transaction.
--
-- This is a simulated ledger: top-ups do not charge a real payment method and
-- cards are display-only. See README.md for what a production version needs.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------

create table public.currencies (
  code        char(3) primary key check (code ~ '^[A-Z]{3}$'),
  name        text not null,
  symbol      text not null,
  -- Units of this currency per 1 USD. Demo rates; swap in a rates feed for production.
  usd_rate    numeric(18, 8) not null check (usd_rate > 0),
  sort_order  int not null default 0
);

create table public.card_plans (
  id                text primary key check (id ~ '^[a-z][a-z0-9_]*$'),
  name              text not null,
  annual_fee_cents  bigint not null check (annual_fee_cents >= 0),
  currency          char(3) not null references public.currencies (code),
  perks             text[] not null default '{}',
  sort_order        int not null default 0
);

insert into public.currencies (code, name, symbol, usd_rate, sort_order) values
  ('USD', 'US Dollar',     '$', 1.00000000, 0),
  ('EUR', 'Euro',          '€', 0.92000000, 1),
  ('GBP', 'British Pound', '£', 0.79000000, 2);

insert into public.card_plans (id, name, annual_fee_cents, currency, perks, sort_order) values
  ('platinum', 'Platinum', 24900, 'USD',
    array['3% cashback on travel', 'Airport lounge access', 'No foreign exchange fees'], 0),
  ('silver',   'Silver',    9900, 'USD',
    array['1% cashback on everything', 'Free ATM withdrawals', 'Instant card freeze'], 1),
  ('gold',     'Gold',     14900, 'USD',
    array['2% cashback on dining', 'Purchase protection', 'Priority support'], 2);

-- ---------------------------------------------------------------------------
-- User data
-- ---------------------------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '' check (char_length(full_name) <= 80),
  created_at  timestamptz not null default now()
);

create table public.wallets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  currency       char(3) not null references public.currencies (code),
  balance_cents  bigint not null default 0 check (balance_cents >= 0),
  created_at     timestamptz not null default now(),
  unique (user_id, currency)
);

create table public.cards (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  plan_id       text not null references public.card_plans (id),
  holder_name   text not null,
  last4         char(4) not null check (last4 ~ '^[0-9]{4}$'),
  network       text not null default 'visa',
  expiry_month  smallint not null check (expiry_month between 1 and 12),
  expiry_year   smallint not null,
  status        text not null default 'active' check (status in ('active', 'frozen', 'cancelled')),
  created_at    timestamptz not null default now()
);

create index cards_user_id_idx on public.cards (user_id, created_at);
create index cards_plan_id_idx on public.cards (plan_id);
-- One live card per plan per person; ordering a second Silver card is refused.
create unique index cards_one_live_card_per_plan on public.cards (user_id, plan_id)
  where status <> 'cancelled';

create table public.transactions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles (id) on delete cascade,
  wallet_id            uuid not null references public.wallets (id) on delete cascade,
  kind                 text not null check (kind in (
                         'top_up', 'transfer_in', 'transfer_out',
                         'conversion_in', 'conversion_out', 'card_fee')),
  direction            text not null generated always as (
                         case when kind in ('top_up', 'transfer_in', 'conversion_in')
                              then 'credit' else 'debit' end) stored,
  amount_cents         bigint not null check (amount_cents > 0),
  currency             char(3) not null references public.currencies (code),
  balance_after_cents  bigint not null check (balance_after_cents >= 0),
  description          text not null default '',
  counterparty_id      uuid references public.profiles (id) on delete set null,
  counterparty_name    text,
  card_id              uuid references public.cards (id) on delete set null,
  -- Shared by the rows one operation writes (both sides of a transfer or conversion).
  group_id             uuid not null default gen_random_uuid(),
  -- Client-supplied idempotency key, stored on the row the caller initiated.
  request_id           uuid,
  created_at           timestamptz not null default now()
);

create index transactions_user_created_idx on public.transactions (user_id, created_at desc);
create index transactions_wallet_id_idx on public.transactions (wallet_id);
create index transactions_counterparty_id_idx on public.transactions (counterparty_id);
create index transactions_card_id_idx on public.transactions (card_id);
create unique index transactions_request_once on public.transactions (user_id, request_id)
  where request_id is not null;

-- ---------------------------------------------------------------------------
-- Row level security and privileges: read your own rows, rename yourself.
-- ---------------------------------------------------------------------------

alter table public.currencies   enable row level security;
alter table public.card_plans   enable row level security;
alter table public.profiles     enable row level security;
alter table public.wallets      enable row level security;
alter table public.cards        enable row level security;
alter table public.transactions enable row level security;

create policy "Currencies are public" on public.currencies
  for select to anon, authenticated using (true);
create policy "Card plans are public" on public.card_plans
  for select to anon, authenticated using (true);
create policy "Read own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "Update own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "Read own wallets" on public.wallets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Read own cards" on public.cards
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Read own transactions" on public.transactions
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.currencies, public.card_plans, public.profiles,
              public.wallets, public.cards, public.transactions
  from anon, authenticated;
grant select on public.currencies, public.card_plans to anon, authenticated;
grant select on public.profiles, public.wallets, public.cards, public.transactions to authenticated;
grant update (full_name) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Internal helpers (the private schema is not exposed through the API)
-- ---------------------------------------------------------------------------

create function private.current_user_id()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'You need to be signed in.',
      hint = 'not_authenticated';
  end if;
  return v_user;
end;
$$;

create function private.valid_currency(p_currency text)
returns char(3)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_code char(3);
begin
  select c.code into v_code from public.currencies c where c.code = upper(trim(p_currency));
  if v_code is null then
    raise exception using message = 'That currency isn''t supported.', hint = 'unsupported_currency';
  end if;
  return v_code;
end;
$$;

create function private.check_amount(p_amount_cents bigint, p_max_cents bigint)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception using message = 'Enter an amount greater than zero.', hint = 'invalid_amount';
  end if;
  if p_amount_cents > p_max_cents then
    raise exception using message = 'That amount is over the limit for one payment.',
      hint = 'amount_over_limit';
  end if;
end;
$$;

create function private.ensure_wallet(p_user uuid, p_currency char(3))
returns void
language sql
set search_path = ''
as $$
  insert into public.wallets (user_id, currency) values (p_user, p_currency)
  on conflict (user_id, currency) do nothing;
$$;

revoke all on all functions in schema private from public, anon, authenticated;

-- New sign-ups get a profile and an empty USD wallet. OAuth providers send the
-- display name as `full_name` or `name`; email sign-ups pass `full_name`.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(new.email, ''), '@', 1)
    ), 80)
  );
  insert into public.wallets (user_id, currency) values (new.id, 'USD');
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------------------
-- API: every function below is callable as /rest/v1/rpc/<name> by signed-in users.
-- Each takes an optional p_request_id; retrying with the same id returns the
-- first result instead of moving money twice.
-- ---------------------------------------------------------------------------

-- Simulated "add money". A real app would credit the wallet from a payment
-- provider webhook (running as service_role) instead of trusting the client.
create function public.top_up(
  p_amount_cents bigint,
  p_currency text default 'USD',
  p_request_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_currency char(3) := private.valid_currency(p_currency);
  v_wallet public.wallets;
  v_row public.transactions;
begin
  perform private.check_amount(p_amount_cents, 2500000); -- 25,000.00 per top-up
  perform private.ensure_wallet(v_user, v_currency);

  select * into v_wallet from public.wallets
  where user_id = v_user and currency = v_currency
  for update;

  select * into v_row from public.transactions
  where user_id = v_user and request_id = p_request_id;
  if found then
    return v_row;
  end if;

  update public.wallets set balance_cents = balance_cents + p_amount_cents
  where id = v_wallet.id
  returning * into v_wallet;

  insert into public.transactions
    (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description, request_id)
  values
    (v_user, v_wallet.id, 'top_up', p_amount_cents, v_currency, v_wallet.balance_cents,
     'Added to your balance', p_request_id)
  returning * into v_row;

  return v_row;
end;
$$;

-- Name of the Slate member who owns this email, so the app can confirm the
-- recipient before sending. Returns null when there is no such member.
create function public.lookup_recipient(p_email text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_name text;
begin
  select p.full_name into v_name
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(u.email) = lower(trim(p_email)) and u.id <> v_user;
  return v_name;
end;
$$;

-- Send money to another member by email. Returns the sender's ledger row.
create function public.transfer(
  p_recipient_email text,
  p_amount_cents bigint,
  p_currency text default 'USD',
  p_note text default null,
  p_request_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender uuid := private.current_user_id();
  v_currency char(3) := private.valid_currency(p_currency);
  v_recipient uuid;
  v_sender_wallet public.wallets;
  v_recipient_wallet public.wallets;
  v_note text := left(coalesce(trim(p_note), ''), 140);
  v_group uuid := gen_random_uuid();
  v_row public.transactions;
begin
  perform private.check_amount(p_amount_cents, 100000000); -- 1,000,000.00 per transfer

  select u.id into v_recipient from auth.users u
  where lower(u.email) = lower(trim(p_recipient_email));
  if v_recipient is null then
    raise exception using message = 'No Slate account uses that email.', hint = 'recipient_not_found';
  end if;
  if v_recipient = v_sender then
    raise exception using message = 'You can''t send money to yourself.', hint = 'self_transfer';
  end if;

  perform private.ensure_wallet(v_sender, v_currency);
  perform private.ensure_wallet(v_recipient, v_currency);

  -- Lock both wallets in id order so two people paying each other at the same
  -- moment queue up instead of deadlocking.
  perform w.id from public.wallets w
  where w.user_id in (v_sender, v_recipient) and w.currency = v_currency
  order by w.id
  for update;

  -- Checked after the lock, so a duplicate request waits for the first one and
  -- then sees its committed row.
  select * into v_row from public.transactions
  where user_id = v_sender and request_id = p_request_id;
  if found then
    return v_row;
  end if;

  select * into v_sender_wallet from public.wallets
  where user_id = v_sender and currency = v_currency;
  if v_sender_wallet.balance_cents < p_amount_cents then
    raise exception using message = 'Insufficient funds.', hint = 'insufficient_funds';
  end if;

  update public.wallets set balance_cents = balance_cents - p_amount_cents
  where id = v_sender_wallet.id
  returning * into v_sender_wallet;
  update public.wallets set balance_cents = balance_cents + p_amount_cents
  where user_id = v_recipient and currency = v_currency
  returning * into v_recipient_wallet;

  insert into public.transactions
    (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description,
     counterparty_id, counterparty_name, group_id, request_id)
  values
    (v_sender, v_sender_wallet.id, 'transfer_out', p_amount_cents, v_currency,
     v_sender_wallet.balance_cents, v_note, v_recipient,
     (select full_name from public.profiles where id = v_recipient), v_group, p_request_id)
  returning * into v_row;

  insert into public.transactions
    (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description,
     counterparty_id, counterparty_name, group_id)
  values
    (v_recipient, v_recipient_wallet.id, 'transfer_in', p_amount_cents, v_currency,
     v_recipient_wallet.balance_cents, v_note, v_sender,
     (select full_name from public.profiles where id = v_sender), v_group);

  return v_row;
end;
$$;

-- Move money between your own currency wallets at the rates in public.currencies.
-- Returns the debit row; the matching credit row shares its group_id.
create function public.convert_currency(
  p_from text,
  p_to text,
  p_amount_cents bigint,
  p_request_id uuid default null
)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_from char(3) := private.valid_currency(p_from);
  v_to char(3) := private.valid_currency(p_to);
  v_from_rate numeric;
  v_to_rate numeric;
  v_to_amount bigint;
  v_from_wallet public.wallets;
  v_to_wallet public.wallets;
  v_group uuid := gen_random_uuid();
  v_row public.transactions;
begin
  if v_from = v_to then
    raise exception using message = 'Pick two different currencies.', hint = 'same_currency';
  end if;
  perform private.check_amount(p_amount_cents, 100000000);

  select usd_rate into v_from_rate from public.currencies where code = v_from;
  select usd_rate into v_to_rate from public.currencies where code = v_to;
  v_to_amount := floor(p_amount_cents * v_to_rate / v_from_rate)::bigint;
  if v_to_amount <= 0 then
    raise exception using message = 'That amount is too small to convert.', hint = 'amount_too_small';
  end if;

  perform private.ensure_wallet(v_user, v_from);
  perform private.ensure_wallet(v_user, v_to);
  perform w.id from public.wallets w
  where w.user_id = v_user and w.currency in (v_from, v_to)
  order by w.id
  for update;

  select * into v_row from public.transactions
  where user_id = v_user and request_id = p_request_id;
  if found then
    return v_row;
  end if;

  select * into v_from_wallet from public.wallets where user_id = v_user and currency = v_from;
  if v_from_wallet.balance_cents < p_amount_cents then
    raise exception using message = 'Insufficient funds.', hint = 'insufficient_funds';
  end if;

  update public.wallets set balance_cents = balance_cents - p_amount_cents
  where id = v_from_wallet.id
  returning * into v_from_wallet;
  update public.wallets set balance_cents = balance_cents + v_to_amount
  where user_id = v_user and currency = v_to
  returning * into v_to_wallet;

  insert into public.transactions
    (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description,
     group_id, request_id)
  values
    (v_user, v_from_wallet.id, 'conversion_out', p_amount_cents, v_from,
     v_from_wallet.balance_cents, v_from || ' → ' || v_to, v_group, p_request_id)
  returning * into v_row;

  insert into public.transactions
    (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description, group_id)
  values
    (v_user, v_to_wallet.id, 'conversion_in', v_to_amount, v_to,
     v_to_wallet.balance_cents, v_from || ' → ' || v_to, v_group);

  return v_row;
end;
$$;

-- Issue a card on a plan and charge its first annual fee from the plan's
-- currency wallet. Card numbers are not generated or stored: only a random
-- last4 for display.
create function public.order_card(
  p_plan_id text,
  p_request_id uuid default null
)
returns public.cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_plan public.card_plans;
  v_wallet public.wallets;
  v_card public.cards;
  v_expiry date := (now() + interval '4 years')::date;
begin
  select * into v_plan from public.card_plans where id = lower(trim(p_plan_id));
  if not found then
    raise exception using message = 'That card plan doesn''t exist.', hint = 'unknown_plan';
  end if;

  perform private.ensure_wallet(v_user, v_plan.currency);
  select * into v_wallet from public.wallets
  where user_id = v_user and currency = v_plan.currency
  for update;

  select c.* into v_card
  from public.transactions t
  join public.cards c on c.id = t.card_id
  where t.user_id = v_user and t.request_id = p_request_id;
  if found then
    return v_card;
  end if;

  if exists (select 1 from public.cards
             where user_id = v_user and plan_id = v_plan.id and status <> 'cancelled') then
    raise exception using message = 'You already have a ' || v_plan.name || ' card.',
      hint = 'card_exists';
  end if;
  if v_wallet.balance_cents < v_plan.annual_fee_cents then
    raise exception using message = 'Insufficient funds.', hint = 'insufficient_funds';
  end if;

  insert into public.cards (user_id, plan_id, holder_name, last4, expiry_month, expiry_year)
  values (
    v_user,
    v_plan.id,
    coalesce((select nullif(full_name, '') from public.profiles where id = v_user), 'Slate member'),
    lpad(floor(random() * 10000)::int::text, 4, '0'),
    extract(month from v_expiry)::smallint,
    extract(year from v_expiry)::smallint
  )
  returning * into v_card;

  if v_plan.annual_fee_cents > 0 then
    update public.wallets set balance_cents = balance_cents - v_plan.annual_fee_cents
    where id = v_wallet.id
    returning * into v_wallet;

    insert into public.transactions
      (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description,
       card_id, request_id)
    values
      (v_user, v_wallet.id, 'card_fee', v_plan.annual_fee_cents, v_plan.currency,
       v_wallet.balance_cents, v_plan.name || ' card · annual fee', v_card.id, p_request_id);
  end if;

  return v_card;
end;
$$;

create function public.set_card_frozen(p_card_id uuid, p_frozen boolean)
returns public.cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_card public.cards;
begin
  update public.cards
  set status = case when p_frozen then 'frozen' else 'active' end
  where id = p_card_id and user_id = v_user and status <> 'cancelled'
  returning * into v_card;
  if not found then
    raise exception using message = 'Card not found.', hint = 'card_not_found';
  end if;
  return v_card;
end;
$$;

revoke all on function
  public.top_up(bigint, text, uuid),
  public.lookup_recipient(text),
  public.transfer(text, bigint, text, text, uuid),
  public.convert_currency(text, text, bigint, uuid),
  public.order_card(text, uuid),
  public.set_card_frozen(uuid, boolean)
from public, anon;

grant execute on function
  public.top_up(bigint, text, uuid),
  public.lookup_recipient(text),
  public.transfer(text, bigint, text, text, uuid),
  public.convert_currency(text, text, bigint, uuid),
  public.order_card(text, uuid),
  public.set_card_frozen(uuid, boolean)
to authenticated;
