-- ============================================================
-- SNGEDU — Mã giảm giá (coupons) + Giới thiệu bạn bè (referrals)
-- Chạy file này trong Supabase SQL Editor (sau 0001, 0002 đã có sẵn trên project).
--
-- Lưu ý: file này KHÔNG đụng tới bảng profiles/balance_transactions đã có sẵn,
-- chỉ thêm cột mới (add column if not exists) nên an toàn để chạy trên DB đang chạy thật.
-- ============================================================

-- ------------------------------------------------------------
-- 0) profiles.role — PHÂN QUYỀN ADMIN (user thường / admin)
-- ------------------------------------------------------------
-- Migration 0002 mới chỉ tạo profiles.balance, CHƯA có cột role — nhưng từ
-- phần dưới của file này trở đi (và các file 0004→0016 sau này) đều cần
-- profiles.role để kiểm tra quyền admin, nên phải thêm ở đây trước khi dùng.
-- Mặc định mọi user là 'user'; muốn cấp quyền admin cho ai thì chạy tay:
--   update public.profiles set role = 'admin' where id = '<uuid-cua-user-do>';
alter table public.profiles add column if not exists role text not null default 'user';
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('user','admin'));
create index if not exists idx_profiles_role on public.profiles (role);

-- ------------------------------------------------------------
-- 1) MÃ GIẢM GIÁ (coupons)
-- ------------------------------------------------------------
create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,                 -- mã người dùng nhập, luôn lưu dạng IN HOA
  description text,                          -- ghi chú nội bộ, hiển thị cho admin
  discount_type text not null default 'percent' check (discount_type in ('percent','fixed')),
  discount_value numeric not null check (discount_value > 0), -- % (vd 10) hoặc số tiền cố định (vd 20000)
  applies_to text not null default 'subscription' check (applies_to in ('all','subscription','document','product','course')),
  max_uses int,                              -- null = không giới hạn số lượt dùng
  used_count int not null default 0,         -- tăng lên mỗi khi có 1 đơn dùng mã này thanh toán THÀNH CÔNG
  min_amount numeric not null default 0,     -- đơn hàng phải >= số tiền này mới áp dụng được (0 = không yêu cầu)
  max_discount_amount numeric,               -- trần giảm giá khi discount_type = 'percent' (null = không giới hạn)
  active boolean not null default true,
  starts_at timestamptz,                     -- null = có hiệu lực ngay
  expires_at timestamptz,                    -- null = không hết hạn
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_coupons_code on public.coupons (upper(code));

alter table public.coupons enable row level security;

-- Không cho client (kể cả user đã đăng nhập) đọc trực tiếp toàn bộ bảng coupons,
-- để tránh lộ danh sách mã ra ngoài — việc kiểm tra/áp dụng mã đi qua Edge Function
-- (sepay-validate-coupon, sepay-create-checkout) chạy bằng service_role nên bỏ qua RLS.
-- Chỉ admin (profiles.role = 'admin') được thao tác trực tiếp từ trang quản trị.
drop policy if exists "coupons_admin_all" on public.coupons;
create policy "coupons_admin_all" on public.coupons
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Lưu vết mã giảm giá đã dùng trên từng đơn hàng
alter table public.sepay_orders add column if not exists coupon_code text;
alter table public.sepay_orders add column if not exists discount_amount numeric not null default 0;
alter table public.sepay_orders add column if not exists original_amount numeric;

-- ------------------------------------------------------------
-- 2) GIỚI THIỆU BẠN BÈ (referrals)
-- ------------------------------------------------------------
-- Mỗi user được giới thiệu (referred) chỉ được gắn với đúng 1 người giới thiệu (referrer),
-- và chỉ được thưởng 1 lần duy nhất khi referred_id nâng cấp Pro thành công lần đầu tiên.
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references auth.users(id) on delete cascade,
  referred_id uuid unique not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','rewarded')),
  reward_amount numeric,                     -- số tiền (VNĐ) đã cộng cho referrer khi rewarded
  referred_reward_amount numeric,            -- số tiền (VNĐ) đã cộng cho referred_id khi rewarded
  created_at timestamptz not null default now(),
  rewarded_at timestamptz
);

create index if not exists idx_referrals_referrer on public.referrals (referrer_id);

alter table public.referrals enable row level security;

-- User xem được các dòng liên quan tới chính mình (mình là người giới thiệu HOẶC được giới thiệu)
drop policy if exists "referrals_select_own" on public.referrals;
create policy "referrals_select_own" on public.referrals
  for select using (auth.uid() = referrer_id or auth.uid() = referred_id);

-- User mới được phép TỰ tạo 1 dòng referral duy nhất ngay sau khi đăng ký (referred_id = chính mình),
-- không được tự ý sửa/xoá hay tự thưởng — việc update status/reward chỉ Edge Function (sepay-ipn) làm bằng service_role.
drop policy if exists "referrals_insert_own" on public.referrals;
create policy "referrals_insert_own" on public.referrals
  for insert with check (auth.uid() = referred_id and referrer_id <> referred_id);

-- Admin xem toàn bộ để theo dõi hiệu quả chương trình giới thiệu
drop policy if exists "referrals_admin_select_all" on public.referrals;
create policy "referrals_admin_select_all" on public.referrals
  for select using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Cấu hình mức thưởng (VNĐ) cho chương trình giới thiệu — đọc/ghi qua site_settings có sẵn,
-- key = 'referral_settings', payload vd: {"referrer_reward": 20000, "referred_reward": 10000, "enabled": true}
-- (không cần bảng riêng, dùng chung cơ chế site_settings admin đang có sẵn cho usage_limits/nav_tabs...)

-- Đánh dấu ai đã được ai giới thiệu (dùng khi hiển thị + đối soát, không bắt buộc phải có mới chạy được referral)
alter table public.profiles add column if not exists referred_by uuid references auth.users(id);
