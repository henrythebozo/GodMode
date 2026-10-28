#!/usr/bin/env bash
# Hammers the transfer function from many connections at once and checks that
# no money is created or lost and no wallet goes negative.
#
#   supabase start && supabase db reset && ./supabase/tests/concurrency.sh
#
# Uses the two seeded members (demo@slate.app and jamie@slate.app).
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
WORKERS="${WORKERS:-16}"
ROUNDS="${ROUNDS:-25}"
ALEX=5ea7e000-0000-4000-8000-0000000000a1
JAMIE=5ea7e000-0000-4000-8000-0000000000b2

total() {
  psql "$DB_URL" -At -c "select sum(balance_cents) from public.wallets
                         where user_id in ('$ALEX', '$JAMIE') and currency = 'USD'"
}

pay() { # pay <from-uuid> <to-email> <cents>
  psql "$DB_URL" -q -v ON_ERROR_STOP=0 -At <<SQL 2>&1 | grep -v '^$' || true
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"$1","role":"authenticated"}';
select public.transfer('$2', $3);
commit;
SQL
}

before=$(total)
echo "USD held by both members before: $before"

worker() {
  for ((i = 0; i < ROUNDS; i++)); do
    if (((RANDOM + i) % 2)); then
      pay "$ALEX" jamie@slate.app $((RANDOM % 90000 + 1000))
    else
      pay "$JAMIE" demo@slate.app $((RANDOM % 90000 + 1000))
    fi
  done
}

log=$(mktemp)
for ((w = 0; w < WORKERS; w++)); do worker >>"$log" & done
wait

after=$(total)
ok=$(grep -c '^(' "$log" || true)
short=$(grep '^ERROR' "$log" | grep -c 'Insufficient funds' || true)
other=$(grep '^ERROR' "$log" | grep -vc 'Insufficient funds' || true)
negative=$(psql "$DB_URL" -At -c "select count(*) from public.wallets where balance_cents < 0")
drift=$(psql "$DB_URL" -At -c "
  select count(*) from public.wallets w
  where w.balance_cents <> coalesce((select sum(case when t.direction = 'credit'
                                                     then t.amount_cents else -t.amount_cents end)
                                    from public.transactions t where t.wallet_id = w.id), 0)")

echo "transfers: $ok succeeded, $short refused for insufficient funds, $other other errors"
echo "USD held by both members after:  $after"
echo "wallets below zero: $negative, wallets out of step with their ledger: $drift"
if [[ "$before" != "$after" || "$negative" != 0 || "$drift" != 0 || "$other" != 0 ]]; then
  echo "FAIL" && grep '^ERROR' "$log" | grep -v 'Insufficient funds' | sort | uniq -c | head
  exit 1
fi

# Overdraft race: every worker tries to send Jamie's money at the same moment.
# Exactly floor(balance / amount) payments may succeed.
amount=40000
psql "$DB_URL" -q -At >/dev/null <<SQL
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"$JAMIE","role":"authenticated"}';
select public.top_up(400000);
commit;
SQL
jamie_before=$(psql "$DB_URL" -At -c "select balance_cents from public.wallets
                                     where user_id = '$JAMIE' and currency = 'USD'")
expected=$((jamie_before / amount))
attempts=$((expected + WORKERS * 2))
log2=$(mktemp)
for ((n = 0; n < attempts; n++)); do pay "$JAMIE" demo@slate.app "$amount" >>"$log2" & done
wait
won=$(grep -c '^(' "$log2" || true)
jamie_after=$(psql "$DB_URL" -At -c "select balance_cents from public.wallets
                                    where user_id = '$JAMIE' and currency = 'USD'")
echo "overdraft race: $attempts attempts of $amount from $jamie_before, $won succeeded (expected $expected), left $jamie_after"
if [[ "$won" != "$expected" || "$jamie_after" != $((jamie_before - expected * amount)) ]]; then
  echo "FAIL" && exit 1
fi
echo "PASS"
