-- Supabase Schema for Link26
-- Run this in the Supabase SQL Editor to create the required tables

-- Enable Row Level Security
create extension if not exists "uuid-ossp";

-- Saves table for storing game state
create table if not exists saves (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  state jsonb not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id)
);

-- Enable Row Level Security on saves
alter table saves enable row level security;

-- Policy: Users can only see their own saves
create policy "Users can view own saves"
  on saves for select
  using (auth.uid() = user_id);

-- Policy: Users can insert their own saves
create policy "Users can insert own saves"
  on saves for insert
  with check (auth.uid() = user_id);

-- Policy: Users can update their own saves
create policy "Users can update own saves"
  on saves for update
  using (auth.uid() = user_id);

-- Policy: Users can delete their own saves
create policy "Users can delete own saves"
  on saves for delete
  using (auth.uid() = user_id);

-- Index for faster lookups
create index if not exists saves_user_id_idx on saves(user_id);

-- Function to automatically update updated_at
create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$ language plpgsql;

-- Trigger to auto-update updated_at
create trigger update_saves_updated_at
  before update on saves
  for each row
  execute function update_updated_at_column();
