begin;

-- 이전 가져오기 로직은 엑셀 셀에 적힌 시간을 그대로 저장해, 이미 등록된
-- 배정은 고정 경기 시간(1경기 13:00–14:00, 2경기 14:10–15:10,
-- 3경기 15:20–16:20)과 다를 수 있었다. 이미 저장된 행도 날짜는 그대로 두고
-- 시간만 고정 시간표에 맞춰 다시 계산한다. 장소도 항상 71동 종합체육관이므로
-- 함께 맞춘다.
update public.operation_assignments
set
  starts_at =
    date_trunc('day', starts_at at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    + case left(title, 1)
        when '1' then interval '13 hours'
        when '2' then interval '14 hours 10 minutes'
        else interval '15 hours 20 minutes'
      end,
  ends_at =
    date_trunc('day', starts_at at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    + case left(title, 1)
        when '1' then interval '14 hours'
        when '2' then interval '15 hours 10 minutes'
        else interval '16 hours 20 minutes'
      end,
  location = '71동 종합체육관'
where title ~ '^[123]경기\s+(운영\s+[AB]|심판)\s*$';

commit;
