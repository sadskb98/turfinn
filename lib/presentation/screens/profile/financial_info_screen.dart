import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class FinancialInfoScreen extends StatefulWidget {
  const FinancialInfoScreen({super.key});

  @override
  State<FinancialInfoScreen> createState() => _FinancialInfoScreenState();
}

class _FinancialInfoScreenState extends State<FinancialInfoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Text('Financial Information',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Balance card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0A2E22),
                      const Color(0xFF051A14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: Column(
                  children: [
                    Text('Current Balance',
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('2,450 BDT',
                        style: GoogleFonts.nunito(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BalanceAction(icon: Icons.add, label: 'Add Money'),
                        const SizedBox(width: 12),
                        _BalanceAction(icon: Icons.download, label: ''),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Tabs
            TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle:
                  GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Transactions'),
                Tab(text: 'Rewards'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  // Transactions
                  ListView(
                    padding: const EdgeInsets.all(18),
                    children: const [
                      _TransactionTile(
                          title: 'Turf Booking',
                          subtitle: 'Mar 03, 2026',
                          amount: '-3,000 BDT',
                          isNegative: true),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Booking Refund',
                          subtitle: 'Feb 28, 2026',
                          amount: '+1,500 BDT',
                          isNegative: false),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Cashback Reward',
                          subtitle: 'Feb 26, 2026',
                          amount: '+500 BDT',
                          isNegative: false),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Weekend Match',
                          subtitle: 'Feb 20, 2026',
                          amount: '-2,500 BDT',
                          isNegative: true),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Referral Bonus',
                          subtitle: 'Feb 18, 2026',
                          amount: '+1,000 BDT',
                          isNegative: false),
                    ],
                  ),
                  // Rewards
                  ListView(
                    padding: const EdgeInsets.all(18),
                    children: const [
                      _TransactionTile(
                          title: 'Cashback Earned',
                          subtitle: 'From 12 bookings this month',
                          amount: '+850',
                          isNegative: false),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Referral Bonus',
                          subtitle: '3 friends joined',
                          amount: '+1,500',
                          isNegative: false),
                      SizedBox(height: 8),
                      _TransactionTile(
                          title: 'Tournament Winnings',
                          subtitle: 'Champion of Feb Cup',
                          amount: '+5,000',
                          isNegative: false),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceAction extends StatelessWidget {
  const _BalanceAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: label.isNotEmpty ? 16 : 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ],
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isNegative,
  });
  final String title;
  final String subtitle;
  final String amount;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(amount,
              style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isNegative
                      ? AppColors.textPrimary
                      : AppColors.primary)),
        ],
      ),
    );
  }
}
