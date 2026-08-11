import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FE), // surface
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.sports_basketball, color: Color(0xFF0F3287)),
            const SizedBox(width: 8),
            const Text(
              'ENCBA LOCKER',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNextEventSection(),
            const SizedBox(height: 32),
            _buildCourtStatusSection(),
            const SizedBox(height: 32),
            _buildQuickMenuSection(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: '일정',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.stadium_outlined),
            label: '코트 현황',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            label: '멤버',
          ),
        ],
      ),
    );
  }

  Widget _buildNextEventSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '다음 일정',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF222222), // text-primary
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF003e7e), // primary-container
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFa9c7ff), // inverse-primary
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'D-DAY',
                  style: TextStyle(
                    color: Color(0xFF003e7e), // primary-container
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '정규 훈련',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFFa9c7ff), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '오늘 18:00 - 20:00',
                    style: TextStyle(color: Color(0xFFa9c7ff), fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFa9c7ff), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '71동 체육관 코트 A',
                    style: TextStyle(color: Color(0xFFa9c7ff), fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourtStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '현재 코트 상태',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF222222), // text-primary
              ),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF666666)),
              label: const Text(
                '새로고침',
                style: TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFf9f9fe), // surface
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFc3c6d2).withOpacity(0.3)), // outline-variant
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFe8e8ed), // surface-container-high
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.stadium, color: Color(0xFF222222)),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '71동 체육관',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF222222)),
                      ),
                      const Text(
                        '업데이트: 방금 전',
                        style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFd6e3ff), // primary-fixed
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F3287), // snu-blue-deep
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '사용 가능',
                      style: TextStyle(
                        color: Color(0xFF114686), // on-primary-fixed-variant
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMenuSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '빠른 메뉴',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF222222), // text-primary
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _buildQuickMenuItem(
              icon: Icons.how_to_vote,
              iconBgColor: const Color(0xFFd6e3ff), // primary-fixed
              iconColor: const Color(0xFF003e7e), // primary-container
              title: '참석 투표',
              subtitle: '이번 주 훈련 참석',
            ),
            _buildQuickMenuItem(
              icon: Icons.campaign,
              iconBgColor: const Color(0xFFdce1ff), // secondary-fixed
              iconColor: const Color(0xFF00164e), // on-secondary-fixed
              title: '코트 제보',
              subtitle: '빈 코트 현황 공유',
            ),
            _buildQuickMenuItem(
              icon: Icons.person_search,
              iconBgColor: const Color(0xFFe2e2e2), // tertiary-fixed
              iconColor: const Color(0xFF1a1c1c), // on-tertiary-fixed
              title: '멤버 찾기',
              subtitle: '픽업 게임 인원 모집',
            ),
            _buildQuickMenuItem(
              icon: Icons.bolt,
              iconBgColor: const Color(0xFFffdad6), // error-container
              iconColor: const Color(0xFF93000a), // on-error-container
              title: '번개 알림',
              subtitle: '즉석 모임 푸시 알림',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickMenuItem({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFf9f9fe), // surface
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFc3c6d2).withOpacity(0.2)), // outline-variant
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF222222)),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
