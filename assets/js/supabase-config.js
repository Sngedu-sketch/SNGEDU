// ============================================================
// Cấu hình Supabase DÙNG CHUNG cho toàn bộ site (frontend + admin).
// Sau này đổi project Supabase khác (đổi Project URL + API key mới)
// thì CHỈ CẦN sửa 2 dòng bên dưới — KHÔNG cần sửa code ở bất kỳ file
// nào khác trong toàn bộ dự án.
//
// Lấy 2 giá trị này ở: Supabase Dashboard > Project Settings > API Keys
//   - Project URL              -> SNG_SUPABASE_URL
//   - "Publishable key" (anon) -> SNG_SUPABASE_ANON_KEY
//     (KHÔNG dùng "Secret key" ở đây — secret key chỉ dùng trong
//     Edge Functions phía server, không bao giờ được để lộ ra frontend)
//
// File này phải được nạp (<script src="...supabase-config.js">) TRƯỚC
// mọi script khác có dùng SUPABASE_URL / SUPABASE_ANON_KEY.
// ============================================================
window.SNG_SUPABASE_URL = 'https://qdecktzyiuxtupkxkfkw.supabase.co';
window.SNG_SUPABASE_ANON_KEY = 'sb_publishable_hYr1Yrhaxh1EwrwtSz8oEg_p4hjY5wO';

// Tự thêm <link rel="preconnect"> tới đúng domain Supabase hiện tại — để các trang
// không cần tự khai preconnect cứng theo domain cũ (đỡ phải sửa khi đổi project).
(function(){
    try{
        var link = document.createElement('link');
        link.rel = 'preconnect';
        link.href = window.SNG_SUPABASE_URL;
        document.head.appendChild(link);
    }catch(e){}
})();
