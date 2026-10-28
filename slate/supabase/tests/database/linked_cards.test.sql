-- Cards added from other banks: validation, limits and isolation.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

insert into auth.users (id, email, raw_user_meta_data, aud, role) values
  ('aaaaaaaa-0000-4000-8000-0000000000c1', 'cy@example.com', '{"full_name":"Cy Young"}', 'authenticated', 'authenticated'),
  ('bbbbbbbb-0000-4000-8000-0000000000c2', 'di@example.com', '{"full_name":"Di Prince"}', 'authenticated', 'authenticated');

select ok((select relrowsecurity from pg_class where oid = 'public.linked_cards'::regclass),
          'row level security is on');

set local role anon;
select throws_ok($$ select * from linked_cards $$, '42501', null, 'anon cannot read cards');
select throws_ok($$ select public.add_linked_card('amex_platinum', 'American Express', 'Platinum', 'amex', '1234', 'X') $$,
                 '42501', null, 'anon cannot add cards');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-4000-8000-0000000000c1","role":"authenticated"}';

select throws_ok($$ select public.add_linked_card('amex_platinum', 'American Express', 'Platinum', 'amex', '12a4', 'Cy Young') $$,
                 'P0001', 'Enter the last 4 digits of the card.', 'last 4 must be digits');
select throws_ok($$ select public.add_linked_card('amex_platinum', 'American Express', 'Platinum', 'amex', '12345', 'Cy Young') $$,
                 'P0001', 'Enter the last 4 digits of the card.', 'last 4 must be four digits');
select throws_ok($$ select public.add_linked_card('amex_platinum', 'American Express', 'Platinum', 'unionpay', '1234', 'Cy Young') $$,
                 'P0001', 'Pick the card network.', 'unknown network');
select throws_ok($$ select public.add_linked_card('Amex Platinum!', 'American Express', 'Platinum', 'amex', '1234', 'Cy Young') $$,
                 'P0001', 'Pick a card design.', 'design keys are slugs');
select throws_ok($$ select public.add_linked_card('custom_blue', ' ', 'Card', 'visa', '1234', 'Cy Young') $$,
                 'P0001', 'Enter the bank and the card name.', 'bank name required');
select throws_ok($$ select public.add_linked_card('custom_blue', 'Bank', 'Card', 'visa', '1234', '') $$,
                 'P0001', 'Enter the name on the card.', 'holder name required');

select is((select (public.add_linked_card(' AMEX_PLATINUM ', ' American Express ', 'Platinum', 'AMEX', ' 2003 ', 'Cy Young', '  ')).design),
          'amex_platinum', 'adds a card with normalised input');
select results_eq(
  $$ select user_id, network, last4::text, nickname from linked_cards $$,
  $$ values ('aaaaaaaa-0000-4000-8000-0000000000c1'::uuid, 'amex', '2003', null::text) $$,
  'the card belongs to the caller, blank nickname stored as null');
select throws_ok($$ select public.add_linked_card('amex_platinum', 'American Express', 'Platinum', 'amex', '2003', 'Cy Young') $$,
                 'P0001', 'You''ve already added this card.', 'the same card only once');
select throws_ok($$ insert into linked_cards (user_id, design, issuer, product, network, last4, holder_name)
                    values ('bbbbbbbb-0000-4000-8000-0000000000c2', 'custom_black', 'x', 'y', 'visa', '0000', 'z') $$,
                 '42501', null, 'cannot insert directly, even for someone else');
select throws_ok($$ update linked_cards set last4 = '9999' $$, '42501', null, 'cannot edit cards directly');

select lives_ok($$
  select public.add_linked_card('custom_black', 'Bank ' || n, 'Card', 'visa', lpad(n::text, 4, '0'), 'Cy Young')
  from generate_series(1, 19) n $$, 'fill up to twenty cards');
select throws_ok($$ select public.add_linked_card('custom_gold', 'One', 'Too many', 'visa', '7777', 'Cy Young') $$,
                 'P0001', 'You can add up to 20 cards.', 'twenty is the limit');

-- Di sees none of Cy's cards and can't remove them. (Cy's card id is read
-- with full privileges; Di's own query would return nothing.)
reset role;
select set_config('test.cy_card', (select id::text from public.linked_cards
                                   where design = 'amex_platinum'
                                     and user_id = 'aaaaaaaa-0000-4000-8000-0000000000c1'), true);
set local role authenticated;
set local request.jwt.claims to '{"sub":"bbbbbbbb-0000-4000-8000-0000000000c2","role":"authenticated"}';
select is((select count(*)::int from linked_cards), 0, 'members only see their own cards');
select throws_ok($$ select public.remove_linked_card(current_setting('test.cy_card')::uuid) $$,
                 'P0001', 'Card not found.', 'cannot remove someone else''s card');

-- Cy removes one of theirs.
set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-4000-8000-0000000000c1","role":"authenticated"}';
select lives_ok($$ select public.remove_linked_card((select id from linked_cards where design = 'amex_platinum')) $$,
                'members can remove their own card');
select is((select count(*)::int from linked_cards), 19, 'and it is gone');

select * from finish();
rollback;
