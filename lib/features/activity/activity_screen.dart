import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Single-hue sequential ramp (light -> dark) used for magnitude.
const _ramp = [Color(0xFFECECEF), Color(0xFFFFD3BF), Color(0xFFFFA67F), Color(0xFFFF6B35), Color(0xFFC94512)];

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(activityProvider);
    final goal = ref.watch(settingsProvider.select((s) => s.dailyGoalMinutes));
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final topPad = MediaQuery.paddingOf(context).top;

    return RefreshIndicator.adaptive(
      onRefresh: () => ref.refresh(activityProvider.future),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TU HÁBITO DE LECTURA',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text('Actividad', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 36)),
                ],
              ),
            ),
          ),
          ...statsAsync.when(
            loading: () => [const SliverFillRemaining(child: Center(child: CupertinoActivityIndicator()))],
            error: (e, _) => [SliverFillRemaining(child: Center(child: Text('Error: $e')))],
            data: (s) => _content(context, s, goal, books),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, ActivityStats s, int goal, List<Book> books) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    final finished = books.where((b) => b.finished).length;
    final inProgress = books.where((b) => b.started && !b.finished).length;

    final ringAndStreak = [
      Expanded(child: _GoalCard(todaySeconds: s.todaySeconds, goalMinutes: goal)),
      const SizedBox(width: 12),
      Expanded(child: _StreakCard(current: s.currentStreak, best: s.bestStreak)),
    ];

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        sliver: SliverToBoxAdapter(
          child: wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...ringAndStreak,
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _WeekCard(days: s.lastWeek, goal: goal)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: ringAndStreak),
                    ),
                    const SizedBox(height: 12),
                    _WeekCard(days: s.lastWeek, goal: goal),
                  ],
                ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        sliver: SliverToBoxAdapter(child: _HeatmapCard(days: s.days, goal: goal)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        sliver: SliverGrid.count(
          crossAxisCount: wide ? 4 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            _StatTile(icon: CupertinoIcons.time, label: 'Tiempo total', value: formatDuration(s.totalSeconds)),
            _StatTile(icon: CupertinoIcons.doc_on_doc, label: 'Páginas vistas', value: NumberFormat.decimalPattern('es').format(s.totalPages)),
            _StatTile(icon: CupertinoIcons.checkmark_seal, label: 'Terminados', value: '$finished'),
            _StatTile(icon: CupertinoIcons.book, label: 'En progreso', value: '$inProgress'),
          ],
        ),
      ),
      if (s.secondsByBook.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: _TopBooksCard(secondsByBook: s.secondsByBook, books: books)),
        ),
    ];
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      boxShadow: softShadow,
    ),
    child: child,
  );
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.inkSecondary),
  );
}

// ------------------------------------------------------------------ goal ring

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.todaySeconds, required this.goalMinutes});

  final int todaySeconds;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final minutes = todaySeconds / 60;
    final pct = (minutes / goalMinutes).clamp(0.0, 1.0);
    final done = pct >= 1;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Hoy'),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 110,
              height: 110,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => CustomPaint(
                  painter: _RingPainter(v),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          minutes.floor().toString(),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1),
                        ),
                        Text('de $goalMinutes min', style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            done ? '¡Meta cumplida! 🎉' : 'Te faltan ${math.max(0, goalMinutes - minutes.floor())} min',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: done ? AppColors.green : AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = AppColors.accentSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    final arc = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFFFF9F68), AppColors.accent, Color(0xFFFF9F68)],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

// --------------------------------------------------------------------- streak

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.current, required this.best});

  final int current;
  final int best;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Racha'),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                CupertinoIcons.flame_fill,
                size: 34,
                color: current > 0 ? AppColors.accent : AppColors.inkTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                '$current',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(current == 1 ? 'día seguido' : 'días seguidos', style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('Mejor racha: $best días', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- week bars

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.days, required this.goal});

  final List<DayStat> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (a, d) => a + d.seconds);
    final maxMin = days.fold<double>(goal.toDouble(), (a, d) => math.max(a, d.minutes));
    final top = (maxMin * 1.15).ceilToDouble();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Últimos 7 días'),
          const SizedBox(height: 4),
          Text(formatDuration(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: top,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: goal.toDouble(),
                      color: AppColors.inkTertiary,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: const TextStyle(fontSize: 10, color: AppColors.inkSecondary),
                        labelResolver: (_) => 'meta',
                      ),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final d = days[v.toInt()];
                        final isToday = v.toInt() == days.length - 1;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            const ['L', 'M', 'X', 'J', 'V', 'S', 'D'][d.day.weekday - 1],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                              color: isToday ? AppColors.ink : AppColors.inkSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.ink,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItem: (group, _, rod, _) {
                      final d = days[group.x];
                      return BarTooltipItem(
                        '${DateFormat('EEE d', 'es').format(d.day)}\n',
                        const TextStyle(color: Colors.white70, fontSize: 11),
                        children: [
                          TextSpan(
                            text: '${d.minutes.round()} min · ${d.pages} págs',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: math.max(days[i].minutes, top * 0.015),
                          width: 22,
                          color: days[i].minutes >= goal
                              ? AppColors.accent
                              : (days[i].seconds > 0 ? const Color(0xFFFFA67F) : const Color(0xFFECECEF)),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 500),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- heatmap

class _HeatmapCard extends StatefulWidget {
  const _HeatmapCard({required this.days, required this.goal});

  final List<DayStat> days;
  final int goal;

  @override
  State<_HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<_HeatmapCard> {
  DayStat? _selected;

  int _level(DayStat d) {
    if (d.seconds == 0) return 0;
    final f = d.minutes / widget.goal;
    if (f < 0.34) return 1;
    if (f < 0.67) return 2;
    if (f < 1) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    // Align columns to weeks starting on Monday.
    final first = widget.days.first.day;
    final lead = first.weekday - 1;
    final cells = <DayStat?>[...List.filled(lead, null), ...widget.days];
    final weeks = (cells.length / 7).ceil();
    final activeDays = widget.days.where((d) => d.seconds > 0).length;
    final sel = _selected;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CardLabel('Constancia · 20 semanas')),
              Text('$activeDays días activos', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              sel == null
                  ? 'Toca un día para ver el detalle'
                  : '${DateFormat("EEEE d 'de' MMMM", 'es').format(sel.day)} · '
                        '${sel.seconds == 0 ? 'sin lectura' : '${sel.minutes.round()} min, ${sel.pages} págs'}',
              key: ValueKey(sel?.day),
              style: TextStyle(
                fontSize: 13,
                fontWeight: sel == null ? FontWeight.w400 : FontWeight.w600,
                color: sel == null ? AppColors.inkSecondary : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 4.0;
              final size = math.min(22.0, (box.maxWidth - 18 - gap * (weeks - 1)) / weeks);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      for (final l in ['L', '', 'X', '', 'V', '', 'D'])
                        SizedBox(
                          height: size + gap,
                          width: 18,
                          child: Text(l, style: const TextStyle(fontSize: 9, color: AppColors.inkTertiary)),
                        ),
                    ],
                  ),
                  for (var w = 0; w < weeks; w++)
                    Padding(
                      padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
                      child: Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            () {
                              final i = w * 7 + d;
                              final stat = i < cells.length ? cells[i] : null;
                              final selected = stat != null && sel != null && stat.day == sel.day;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: gap),
                                child: GestureDetector(
                                  onTap: stat == null ? null : () => setState(() => _selected = selected ? null : stat),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: size,
                                    height: size,
                                    decoration: BoxDecoration(
                                      color: stat == null ? Colors.transparent : _ramp[_level(stat)],
                                      borderRadius: BorderRadius.circular(size * 0.28),
                                      border: selected ? Border.all(color: AppColors.ink, width: 2) : null,
                                    ),
                                  ),
                                ),
                              );
                            }(),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Menos', style: TextStyle(fontSize: 10, color: AppColors.inkSecondary)),
              const SizedBox(width: 6),
              for (final c in _ramp)
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                ),
              const SizedBox(width: 6),
              const Text('Meta+', style: TextStyle(fontSize: 10, color: AppColors.inkSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- stat tiles

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.inkSecondary),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- top books

class _TopBooksCard extends StatelessWidget {
  const _TopBooksCard({required this.secondsByBook, required this.books});

  final Map<String, int> secondsByBook;
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final b in books) b.id: b};
    final entries = secondsByBook.entries.where((e) => byId.containsKey(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final max = top.first.value;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Más leídos · 30 días'),
          const SizedBox(height: 14),
          for (final e in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(width: 34, height: 48, child: BookCover(book: byId[e.key]!, radius: 5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          byId[e.key]!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ProgressLine(value: e.value / max, color: AppColors.accent, height: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(formatDuration(e.value), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
