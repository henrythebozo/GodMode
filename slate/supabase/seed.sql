-- Local development data only (`supabase db reset` runs this; `supabase db push` does not).
-- Two members so transfers can be tried end to end:
--   demo@slate.app  / slate1234  Alex Carter: $22,000, €1,306.40 and a Platinum card
--   jamie@slate.app / slate1234  Jamie Rivera: $4,931
-- The ledger rows below add up to those balances.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new
)
values
  ('00000000-0000-0000-0000-000000000000', '5ea7e000-0000-4000-8000-0000000000a1',
   'authenticated', 'authenticated', 'demo@slate.app',
   extensions.crypt('slate1234', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Alex Carter"}', now(), now(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '5ea7e000-0000-4000-8000-0000000000b2',
   'authenticated', 'authenticated', 'jamie@slate.app',
   extensions.crypt('slate1234', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Jamie Rivera"}', now(), now(),
   '', '', '', '');

insert into auth.identities (id, user_id, provider_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.email in ('demo@slate.app', 'jamie@slate.app');

-- The sign-up trigger already made both profiles and USD wallets.
insert into public.wallets (user_id, currency)
values ('5ea7e000-0000-4000-8000-0000000000a1', 'EUR');

insert into public.cards (id, user_id, plan_id, holder_name, last4, expiry_month, expiry_year, created_at)
values ('5ea7ec00-0000-4000-8000-000000000001', '5ea7e000-0000-4000-8000-0000000000a1',
        'platinum', 'Alex Carter', '4821', 10, 2030, now() - interval '8 days');

with
  day as (select date_trunc('day', now()) as d),
  alex as (select '5ea7e000-0000-4000-8000-0000000000a1'::uuid as id),
  jamie as (select '5ea7e000-0000-4000-8000-0000000000b2'::uuid as id),
  w as (
    select user_id, currency, id from public.wallets
    where user_id in ((select id from alex), (select id from jamie))
  ),
  rows (owner, currency, kind, amount, balance_after, description, counterparty, at, grp) as (
    values
      -- Alex, oldest first
      ('alex', 'USD', 'top_up',         2000000, 2000000, 'Added to your balance', null,    interval '-9 days' + interval '10 hours',          'g01'),
      ('alex', 'USD', 'card_fee',         24900, 1975100, 'Platinum card · annual fee', null, interval '-8 days' + interval '11 hours',      'g02'),
      ('alex', 'USD', 'transfer_in',     216900, 2192000, 'Rent share',            'jamie', interval '-7 days' + interval '19 hours 30 minutes', 'g03'),
      ('alex', 'USD', 'conversion_out',   47000, 2145000, 'USD → EUR',             null,    interval '-5 days' + interval '16 hours 40 minutes', 'g04'),
      ('alex', 'EUR', 'conversion_in',    43240,   43240, 'USD → EUR',             null,    interval '-5 days' + interval '16 hours 40 minutes', 'g04'),
      ('alex', 'USD', 'top_up',          120000, 2265000, 'Added to your balance', null,    interval '-4 days' + interval '9 hours 12 minutes',  'g05'),
      ('alex', 'USD', 'transfer_out',    105000, 2160000, 'Dinner',                'jamie', interval '-3 days' + interval '16 hours 7 minutes',  'g06'),
      ('alex', 'USD', 'conversion_out',   95000, 2065000, 'USD → EUR',             null,    interval '-2 days' + interval '16 hours 7 minutes',  'g07'),
      ('alex', 'EUR', 'conversion_in',    87400,  130640, 'USD → EUR',             null,    interval '-2 days' + interval '16 hours 7 minutes',  'g07'),
      ('alex', 'USD', 'top_up',          240000, 2305000, 'Added to your balance', null,    interval '-1 days' + interval '12 hours 7 minutes',  'g08'),
      ('alex', 'USD', 'transfer_out',    105000, 2200000, 'Concert tickets',       'jamie', interval '-1 days' + interval '16 hours 7 minutes',  'g09'),
      -- Jamie's side of the same transfers
      ('jamie', 'USD', 'top_up',         500000,  500000, 'Added to your balance', null,    interval '-10 days' + interval '9 hours',            'g10'),
      ('jamie', 'USD', 'transfer_out',   216900,  283100, 'Rent share',            'alex',  interval '-7 days' + interval '19 hours 30 minutes', 'g03'),
      ('jamie', 'USD', 'transfer_in',    105000,  388100, 'Dinner',                'alex',  interval '-3 days' + interval '16 hours 7 minutes',  'g06'),
      ('jamie', 'USD', 'transfer_in',    105000,  493100, 'Concert tickets',       'alex',  interval '-1 days' + interval '16 hours 7 minutes',  'g09')
  ),
  groups as materialized (select grp, gen_random_uuid() as group_id from (select distinct grp from rows) g)
insert into public.transactions
  (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents, description,
   counterparty_id, counterparty_name, card_id, group_id, created_at)
select
  case r.owner when 'alex' then (select id from alex) else (select id from jamie) end,
  w.id,
  r.kind,
  r.amount,
  r.currency,
  r.balance_after,
  r.description,
  case r.counterparty when 'alex' then (select id from alex) when 'jamie' then (select id from jamie) end,
  case r.counterparty when 'alex' then 'Alex Carter' when 'jamie' then 'Jamie Rivera' end,
  case r.kind when 'card_fee' then '5ea7ec00-0000-4000-8000-000000000001'::uuid end,
  g.group_id,
  (select d from day) + r.at
from rows r
join groups g on g.grp = r.grp
join w on w.user_id = case r.owner when 'alex' then (select id from alex) else (select id from jamie) end
      and w.currency = r.currency;

update public.wallets set balance_cents = 2200000
where user_id = '5ea7e000-0000-4000-8000-0000000000a1' and currency = 'USD';
update public.wallets set balance_cents = 130640
where user_id = '5ea7e000-0000-4000-8000-0000000000a1' and currency = 'EUR';
update public.wallets set balance_cents = 493100
where user_id = '5ea7e000-0000-4000-8000-0000000000b2' and currency = 'USD';
