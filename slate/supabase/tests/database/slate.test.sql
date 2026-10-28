-- Run with `supabase test db`. Everything happens inside one transaction that is
-- rolled back, so the seed data is untouched.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(67);

-- Two fresh members. The sign-up trigger should give each a profile and a USD wallet.
insert into auth.users (id, email, raw_user_meta_data, aud, role) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'ada@example.com',   '{"full_name":"Ada Lovelace"}', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'grace@example.com', '{"name":"Grace Hopper"}',      'authenticated', 'authenticated'),
  ('cccccccc-0000-4000-8000-000000000003', 'linus@example.com', '{}',                           'authenticated', 'authenticated');

-- ---------------------------------------------------------------- schema
select ok(bool_and(c.relrowsecurity), 'row level security is on for every app table')
from pg_class c
where c.oid in ('public.currencies'::regclass, 'public.card_plans'::regclass, 'public.profiles'::regclass,
                'public.wallets'::regclass, 'public.cards'::regclass, 'public.transactions'::regclass);
select is((select full_name from profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          'Ada Lovelace', 'sign-up stores full_name from metadata');
select is((select full_name from profiles where id = 'bbbbbbbb-0000-4000-8000-000000000002'),
          'Grace Hopper', 'sign-up falls back to the OAuth name');
select is((select full_name from profiles where id = 'cccccccc-0000-4000-8000-000000000003'),
          'linus', 'sign-up falls back to the email name');
select results_eq(
  $$ select currency::text, balance_cents from wallets where user_id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
  $$ values ('USD', 0::bigint) $$,
  'sign-up opens an empty USD wallet');

-- ---------------------------------------------------------------- anonymous visitors
set local role anon;
select is((select count(*)::int from card_plans), 3, 'anon can read card plans');
select is((select count(*)::int from currencies), 3, 'anon can read currencies');
select throws_ok($$ select * from wallets $$, '42501', null, 'anon cannot read wallets');
select throws_ok($$ select * from profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select public.top_up(100) $$, '42501', null, 'anon cannot call top_up');
select throws_ok($$ select public.transfer('ada@example.com', 100) $$, '42501', null, 'anon cannot call transfer');
reset role;

-- ---------------------------------------------------------------- Ada: top-ups
set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}';

select throws_ok($$ select public.top_up(0) $$, 'P0001', 'Enter an amount greater than zero.', 'zero top-up is refused');
select throws_ok($$ select public.top_up(-500) $$, 'P0001', 'Enter an amount greater than zero.', 'negative top-up is refused');
select throws_ok($$ select public.top_up(2500001) $$, 'P0001', 'That amount is over the limit for one payment.', 'top-up over the limit is refused');
select throws_ok($$ select public.top_up(100, 'XYZ') $$, 'P0001', 'That currency isn''t supported.', 'unknown currency is refused');

select is((select (public.top_up(500000)).balance_after_cents), 500000::bigint, 'top-up returns the new balance');
select is((select balance_cents from wallets where currency = 'USD'), 500000::bigint, 'top-up credits the wallet');
select is((select kind || '/' || direction from transactions), 'top_up/credit', 'top-up writes a credit row');

select lives_ok($$ select public.top_up(10000, 'usd', 'dddddddd-0000-4000-8000-000000000001') $$, 'top-up with a request id');
select lives_ok($$ select public.top_up(10000, 'usd', 'dddddddd-0000-4000-8000-000000000001') $$, 'retrying it does not fail');
select is((select balance_cents from wallets where currency = 'USD'), 510000::bigint, 'a retried top-up is only applied once');
select is((select count(*)::int from transactions), 2, 'a retried top-up writes one row');

-- ---------------------------------------------------------------- Ada: direct writes are blocked
select throws_ok($$ insert into wallets (user_id, currency, balance_cents) values ('aaaaaaaa-0000-4000-8000-000000000001', 'GBP', 99999) $$,
                 '42501', null, 'clients cannot create wallets');
select throws_ok($$ update wallets set balance_cents = 99999999 $$, '42501', null, 'clients cannot edit balances');
select throws_ok($$ insert into transactions (user_id, wallet_id, kind, amount_cents, currency, balance_after_cents)
                    select user_id, id, 'top_up', 1, 'USD', 1 from wallets $$,
                 '42501', null, 'clients cannot write ledger rows');
select throws_ok($$ delete from transactions $$, '42501', null, 'clients cannot delete ledger rows');
select throws_ok($$ insert into cards (user_id, plan_id, holder_name, last4, expiry_month, expiry_year)
                    values ('aaaaaaaa-0000-4000-8000-000000000001', 'gold', 'x', '0000', 1, 2030) $$,
                 '42501', null, 'clients cannot issue their own cards');
select throws_ok($$ update profiles set id = 'bbbbbbbb-0000-4000-8000-000000000002' $$, '42501', null,
                 'clients can only update their name');
select lives_ok($$ update profiles set full_name = 'Ada King' $$, 'members can rename themselves');
update profiles set full_name = 'Hacked' where id = 'bbbbbbbb-0000-4000-8000-000000000002';
select is((select count(*)::int from profiles), 1, 'members only see their own profile');

-- ---------------------------------------------------------------- Ada: transfers
select throws_ok($$ select public.transfer('nobody@example.com', 100) $$, 'P0001', 'No Slate account uses that email.', 'unknown recipient');
select throws_ok($$ select public.transfer('ADA@example.com', 100) $$, 'P0001', 'You can''t send money to yourself.', 'self transfer, any email case');
select throws_ok($$ select public.transfer('grace@example.com', 510001) $$, 'P0001', 'Insufficient funds.', 'cannot overdraw');
select throws_ok($$ select public.transfer('grace@example.com', 0) $$, 'P0001', 'Enter an amount greater than zero.', 'zero transfer is refused');
select is(public.lookup_recipient(' Grace@Example.com '), 'Grace Hopper', 'lookup finds a member by email');
select is(public.lookup_recipient('ada@example.com'), null::text, 'lookup does not return yourself');
select is(public.lookup_recipient('nobody@example.com'), null::text, 'lookup returns null for strangers');

select is((select (public.transfer('grace@example.com', 150000, 'USD', 'Lunch')).kind), 'transfer_out', 'transfer returns the sender row');
select is((select balance_cents from wallets where currency = 'USD'), 360000::bigint, 'sender is debited');
select lives_ok($$ select public.transfer('grace@example.com', 1000, 'USD', null, 'dddddddd-0000-4000-8000-000000000002') $$, 'transfer with a request id');
select lives_ok($$ select public.transfer('grace@example.com', 1000, 'USD', null, 'dddddddd-0000-4000-8000-000000000002') $$, 'retrying the transfer');
select is((select balance_cents from wallets where currency = 'USD'), 359000::bigint, 'a retried transfer is only debited once');
select is((select count(*)::int from transactions where kind = 'transfer_in'), 0, 'the sender cannot see the recipient row');

-- ---------------------------------------------------------------- Ada: conversion
select throws_ok($$ select public.convert_currency('USD', 'usd', 100) $$, 'P0001', 'Pick two different currencies.', 'same-currency conversion');
select throws_ok($$ select public.convert_currency('USD', 'EUR', 359001) $$, 'P0001', 'Insufficient funds.', 'cannot convert more than you have');
select throws_ok($$ select public.convert_currency('USD', 'EUR', 1) $$, 'P0001', 'That amount is too small to convert.', 'conversion that rounds to zero');
select lives_ok($$ select public.convert_currency('USD', 'EUR', 100000) $$, 'convert $1,000 to euros');
select results_eq(
  $$ select currency::text, balance_cents from wallets order by currency $$,
  $$ values ('EUR', 92000::bigint), ('USD', 259000::bigint) $$,
  'conversion opens a EUR wallet at the demo rate');
select is((select count(distinct group_id)::int from transactions where kind like 'conversion%'), 1,
          'both conversion rows share a group id');

-- ---------------------------------------------------------------- Ada: cards
select throws_ok($$ select public.order_card('titanium') $$, 'P0001', 'That card plan doesn''t exist.', 'unknown plan');
select is((select (public.order_card('Silver', 'dddddddd-0000-4000-8000-000000000003')).holder_name), 'Ada King', 'card carries the member name');
select is((select (public.order_card('silver', 'dddddddd-0000-4000-8000-000000000003')).plan_id), 'silver', 'retrying an order returns the same card');
select is((select count(*)::int from cards), 1, 'a retried order issues one card');
select is((select balance_cents from wallets where currency = 'USD'), 249100::bigint, 'the Silver fee ($99) is charged once');
select ok((select last4 ~ '^[0-9]{4}$' and status = 'active' from cards), 'new card is active with a 4 digit last4');
select is((select t.card_id from transactions t where t.kind = 'card_fee'), (select id from cards), 'fee row links to the card');
select throws_ok($$ select public.order_card('silver') $$, 'P0001', 'You already have a Silver card.', 'one live card per plan');

select is((select (public.set_card_frozen((select id from cards), true)).status), 'frozen', 'members can freeze a card');
select is((select (public.set_card_frozen((select id from cards), false)).status), 'active', 'and unfreeze it');

-- ---------------------------------------------------------------- Grace: isolation
set local request.jwt.claims to '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}';
select is((select full_name from profiles), 'Grace Hopper', 'another member''s update did not touch Grace');
select is((select balance_cents from wallets where currency = 'USD'), 151000::bigint, 'recipient got both transfers once');
select results_eq(
  $$ select counterparty_name, description from transactions where kind = 'transfer_in' order by amount_cents desc $$,
  $$ values ('Ada King', 'Lunch'), ('Ada King', '') $$,
  'recipient sees who paid them, by the name they had when paying');
select is((select count(*)::int from cards), 0, 'Grace cannot see Ada''s cards');
select throws_ok($$ select public.set_card_frozen('5ea7ec00-0000-4000-8000-000000000001', true) $$, 'P0001', 'Card not found.',
                 'members cannot freeze someone else''s card');

set local request.jwt.claims to '{"sub":"cccccccc-0000-4000-8000-000000000003","role":"authenticated"}';
select throws_ok($$ select public.order_card('platinum') $$, 'P0001', 'Insufficient funds.', 'card fee needs enough balance');
select is((select count(*)::int from cards), 0, 'a refused order issues no card');
reset role;

-- ---------------------------------------------------------------- ledger invariant
select is(
  (select count(*)::int from wallets w
   where w.balance_cents <> coalesce((
     select sum(case when t.direction = 'credit' then t.amount_cents else -t.amount_cents end)
     from transactions t where t.wallet_id = w.id), 0)),
  0, 'every wallet balance equals the sum of its ledger rows');

select * from finish();
rollback;
