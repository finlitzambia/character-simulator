-- db/seed_instruments.sql
-- Run this once after schema.sql, in the Supabase SQL editor.
-- Starting prices are illustrative/rounded, matching the real LuSE
-- companies already referenced across your course content (Module U2,
-- U3, 2.1) so learners recognise names they've studied.

insert into instruments (ticker, name, kind, current_price) values
  ('ZSUGAR', 'Zambia Sugar Plc',              'share',        12.80),
  ('CECA',   'Copperbelt Energy Corporation', 'share',        169.98),
  ('AIRTEL', 'Airtel Zambia Plc',             'share',        175.00),
  ('ZANACO', 'Zambia National Commercial Bank','share',       6.50),
  ('DCZ',    'Dot Com Zambia Plc (Alt-M)',    'share',        12.30),
  ('REIZ',   'Real Estate Investments Zambia','share',        4.10),
  ('ZMBEEF', 'Zambeef Products Plc',          'share',        3.20),
  ('TBILL91','91-Day Treasury Bill',          't_bill',       1.00),
  ('GRZ5Y',  '5-Year Government Bond',        'bond',         1.00),
  ('MMKT',   'Money Market Fund (pooled)',    'money_market', 1.00);
