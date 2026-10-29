# Slate

A black-and-white card and wallet app in Flutter, with a Supabase backend.

- **Login / sign-up** with the liquid wave intro (the black splash lifts into the
  curved header, the wordmark glides to the corner, the form staggers in), email +
  password, Google / Apple / Facebook buttons, and password reset by email.
- **Home**: greeting, available balance, a swipeable row of your cards (Slate's
  own plus cards from other banks) ending in a round **+ Add** button, recent
  transactions, floating pill tab bar.
- **Card carousel**: tap the card on Home and it turns upright into a full-screen
  ring of all your cards. Swiping spins the ring (a flick carries on through
  several cards and lands on one), tapping the front card turns it over to its
  back, **Details** opens freeze / remove, and pulling down or **Close** sends the
  card back to the row.
- **Add a card**: pick Amex Centurion ("the Black Card"), Amex Platinum, Amex Gold,
  Chase Sapphire Reserve, Capital One Venture X, Citi Strata Premier, Discover it,
  or "Other card" with any bank, network and colour, then type the last 4 digits.
  Only those 4 digits are stored; the app never asks for a full number or code and
  can't pay with these cards.
- **Card plans**: Platinum / Silver / Gold carousel with the sliding title and
  "Choose Silver" button; ordering charges the first annual fee.
- **Transfer**: send to another member by email (the name is confirmed before you
  can send), top up, and convert between USD / EUR / GBP wallets.
- **Cards**: every card with details; freeze Slate cards, remove added ones.
  **Profile**: rename, reset password, log out.

The layout was measured from the reference frames (iPhone 17 Pro Max, 440 × 956 pt):
type is Plus Jakarta Sans, icons are Iconsax, and the login wave is a single cubic
Bézier fitted to the frame.

## Read this first

- **Demo and live are separate builds.** Without Supabase settings the app is the
  demo: Alex's account with $22,000, six cards across Slate, Amex, Chase and
  Capital One, and a transaction history, all in memory. With Supabase settings
  it's live: every account starts at $0 with no cards and no transactions, and
  only shows what that member does. The fake accounts in `supabase/seed.sql`
  exist only in a local database (`supabase db reset`); `supabase db push`, which
  sets up a hosted project, never sends them.

- **The money is simulated.** Balances live in your own Postgres. Top-ups don't
  charge anything and cards are pictures with a random last four digits. Moving
  real money needs a banking / card-issuing partner (Stripe Issuing, Marqeta, Unit
  and similar), identity checks (KYC) and the licences that come with them.
- **The bank cards are AI renders of the real ones.** Amex Platinum, Gold and
  Centurion, Sapphire Reserve, Venture X, Strata Premier and Discover it, front
  and back, are photoreal pictures made with an image model from photos of the
  real cards, with no name or number on them. The app writes the member's own
  name and last four digits onto each picture where that card prints them. The
  pictures are in `assets/cards/` (`<design>.webp` and `<design>_back.webp`), and
  where the text goes is in `lib/widgets/card_slots.dart`. Image models misdraw
  very small text: the faint "WORLD SERVICE" microtext in the Amex background
  pattern is not real words up close, though at phone size it reads as texture.
  That suits a demo or a portfolio. Shipping it in the App Store or Play Store
  without the issuers' permission is a trademark risk (Apple's review guideline
  5.2.1 rejects apps that use protected third-party marks without permission): for a
  release, use card art the issuers license to you, or the plain "Other card"
  colours, which carry no issuer marks.
- **The visual design comes from DailyFlutterUI's TikTok videos**, not from your
  other project. Their handle no longer appears anywhere; the card and greeting
  show the member's own name.

## Run it

You need Flutter 3.47 or newer.

```sh
cd slate
flutter pub get
flutter run
```

With no Supabase settings the app runs as the **demo**, on data kept in memory: the
account from the screenshots ($22,000, the Platinum card, cards from other banks).
Any email plus a password of six or more characters logs in; `jamie@slate.app` and
`sam@slate.app` can receive money. Data resets when the app restarts.

### With a local Supabase backend

Needs Docker and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started).

```sh
cd slate
supabase start        # prints the API URL and the publishable key
supabase db reset     # applies the migration and the demo seed
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Log in as `demo@slate.app` / `slate1234` (or `jamie@slate.app` / `slate1234` to
receive transfers). On a real phone, replace `127.0.0.1` with your computer's
address on the Wi-Fi network; the Android emulator reaches your computer at
`10.0.2.2`.

### With a hosted Supabase project

1. Create a project at [supabase.com](https://supabase.com) (the free plan allows
   two active projects).
2. Push the schema:
   ```sh
   cd slate
   supabase login
   supabase link --project-ref YOUR-PROJECT-REF
   supabase db push
   ```
   `db push` applies `supabase/migrations/` only; the demo seed is local-only.
3. In the dashboard, **Authentication → URL Configuration**, add
   `com.henrythebozo.slate://login-callback` to the redirect URLs.
4. Copy `env.example.json` to `env.json`, fill in the project URL and publishable
   key (**Project Settings → API Keys**), then:
   ```sh
   flutter run --dart-define-from-file=env.json
   ```

Hosted projects ask new members to confirm their email before the first login;
the app tells them to check their inbox.

### Social sign-in

The buttons use Supabase's OAuth flow, which opens the provider in a browser and
returns through `com.henrythebozo.slate://login-callback` (already registered in
`ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml`). Turn each
provider on under **Authentication → Providers** with its client id and secret:
Google (Google Cloud console), Apple (Apple Developer account, Services ID and key),
Facebook (Meta for Developers app). Until a provider is turned on, its button
opens a Supabase error page ("provider is not enabled"). Apple's App Store rules expect Sign in with Apple to be offered
natively when other social logins are present; `sign_in_with_apple` plus
`signInWithIdToken` is the usual way to do that.

If you change the bundle id (`com.henrythebozo.slate`), change the scheme in those
two files, in `lib/main.dart` (`authRedirect`) and in `supabase/config.toml`.

## Backend

Everything is in `supabase/migrations/` (the schema, then the added-cards table).

| Table | What it holds |
| --- | --- |
| `profiles` | Name, one per auth user (created by a sign-up trigger, with an empty USD wallet). |
| `wallets` | Balance per member per currency, in cents. Can't go below zero. |
| `cards` | Plan, holder name, last four digits, expiry, active / frozen. |
| `transactions` | The ledger. Every balance change writes a row with the balance after it. |
| `linked_cards` | Cards a member added from other banks: design, bank, card name, network, last 4. |
| `card_plans`, `currencies` | Plans and prices; demo exchange rates. Edit these to change prices. |

Members can only **read** their own rows (row level security) and change their own
name. Every money movement is a database function called over the API, which
checks the input, locks the wallets involved and writes the balance change and its
ledger rows in one transaction:

| Function | Rules |
| --- | --- |
| `top_up(p_amount_cents, p_currency, p_request_id)` | Up to $25,000 per top-up. |
| `transfer(p_recipient_email, p_amount_cents, p_currency, p_note, p_request_id)` | Recipient must be a member and not you; no overdraft; up to $1,000,000. |
| `convert_currency(p_from, p_to, p_amount_cents, p_request_id)` | Uses `currencies.usd_rate`, rounds down to the cent. |
| `order_card(p_plan_id, p_request_id)` | One live card per plan; charges the annual fee. |
| `set_card_frozen(p_card_id, p_frozen)` | Own cards only. |
| `lookup_recipient(p_email)` | Returns the member's name, or null. |
| `add_linked_card(p_design, p_issuer, p_product, p_network, p_last4, p_holder_name, p_nickname)` | Exactly 4 digits; up to 20 cards; the same card once. |
| `remove_linked_card(p_card_id)` | Own cards only. |

`p_request_id` makes a payment safe to retry: sending the same id twice returns the
first result instead of moving money twice. The app sends a fresh id per attempt
and reuses it when retrying after a network error.

## Tests

```sh
flutter analyze
flutter test                       # unit + widget tests on demo data
supabase test db                   # 87 database tests: rules, RLS, idempotency, added cards
./supabase/tests/concurrency.sh    # many simultaneous transfers: no deadlocks, no overdraft
SUPABASE_TEST_URL=http://127.0.0.1:54321 SUPABASE_TEST_KEY=sb_publishable_... \
  flutter test test/supabase_repository_test.dart   # the app's data layer against local Supabase
```

## Layout

```
lib/
  main.dart                 picks Supabase or demo data, MaterialApp
  theme/app_theme.dart      colours and type measured from the frames
  data/                     models, repository interface, Supabase + demo implementations
  state/app_state.dart      account data and actions (ChangeNotifier, no extra packages)
  screens/                  splash, login, home, card carousel, transactions, card plans, cards, transfer, profile
  widgets/                  card faces (pictures + text slots), network marks, card row and hero,
                            nav bar, wave, buttons, fields, rows
assets/cards/               card pictures, front and back
supabase/
  migrations/               schema, row level security, functions
  seed.sql                  local demo accounts
  tests/                    pgTAP tests and the concurrency script
```

To compare against device screenshots in a browser, build for web with fake
iPhone insets: `flutter build web --dart-define=PREVIEW_SAFE_AREA=62,34`.
