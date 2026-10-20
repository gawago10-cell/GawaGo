import 'package:flutter/material.dart';

import '../../core/theme/gawago_colors.dart';
import '../../features/worker/data/worker_models.dart';
import 'async_state.dart';
import 'status_card.dart';

class ReviewHistory extends StatefulWidget {
  const ReviewHistory({
    super.key,
    required this.receivedLoader,
    required this.givenLoader,
    required this.receivedTitle,
    required this.givenTitle,
  });

  final Future<List<GawaGoReview>> Function() receivedLoader;
  final Future<List<GawaGoReview>> Function() givenLoader;
  final String receivedTitle;
  final String givenTitle;

  @override
  State<ReviewHistory> createState() => _ReviewHistoryState();
}

class _ReviewHistoryState extends State<ReviewHistory> {
  late Future<List<List<GawaGoReview>>> _future = _load();
  DateTime? _dateFilter;
  int? _ratingFilter;

  Future<List<List<GawaGoReview>>> _load() async {
    return Future.wait([widget.receivedLoader(), widget.givenLoader()]);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _selectDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value != null) setState(() => _dateFilter = value);
  }

  List<GawaGoReview> _filtered(List<GawaGoReview> reviews) {
    return reviews.where((review) {
      if (_dateFilter != null) {
        final date = review.createdDate;
        if (date == null ||
            date.year != _dateFilter!.year ||
            date.month != _dateFilter!.month ||
            date.day != _dateFilter!.day) {
          return false;
        }
      }
      return _ratingFilter == null || review.rating?.round() == _ratingFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<GawaGoReview>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error, onRetry: _reload);
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final received = _filtered(snapshot.data![0]);
        final given = _filtered(snapshot.data![1]);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      _dateFilter == null
                          ? 'Filter by Date'
                          : '${_dateFilter!.month}/${_dateFilter!.day}/${_dateFilter!.year}',
                    ),
                  ),
                  if (_dateFilter != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _dateFilter = null;
                      }),
                      child: const Text('Clear Filter'),
                    ),
                  DropdownButton<int?>(
                    value: _ratingFilter,
                    hint: const Text('Rating'),
                    items: const [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All ratings'),
                      ),
                      DropdownMenuItem(value: 5, child: Text('5 stars')),
                      DropdownMenuItem(value: 4, child: Text('4 stars')),
                      DropdownMenuItem(value: 3, child: Text('3 stars')),
                      DropdownMenuItem(value: 2, child: Text('2 stars')),
                      DropdownMenuItem(value: 1, child: Text('1 star')),
                    ],
                    onChanged: (value) => setState(() => _ratingFilter = value),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Summary(reviews: received),
              const SizedBox(height: 16),
              _Section(title: widget.receivedTitle, reviews: received),
              const SizedBox(height: 18),
              _Section(title: widget.givenTitle, reviews: given, given: true),
            ],
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.reviews});

  final List<GawaGoReview> reviews;

  @override
  Widget build(BuildContext context) {
    final ratings = reviews.map((item) => item.rating).whereType<double>();
    final count = ratings.length;
    final average = count == 0
        ? null
        : ratings.reduce((left, right) => left + right) / count;
    final distribution = {
      for (final star in [5, 4, 3, 2, 1])
        star: reviews.where((review) => review.rating?.round() == star).length,
    };
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GawaGoColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 36),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      average == null
                          ? 'No ratings yet'
                          : average.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? 'review' : 'reviews'} received',
                    ),
                  ],
                ),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: 14),
              ...distribution.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      SizedBox(width: 48, child: Text('${entry.key} star')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: entry.value / count,
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${entry.value}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.reviews,
    this.given = false,
  });

  final String title;
  final List<GawaGoReview> reviews;
  final bool given;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: GawaGoColors.ink,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        if (reviews.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No reviews available.'),
            ),
          )
        else
          ...reviews.map(
            (review) => StatusCard(
              icon: Icons.reviews_outlined,
              title: given ? review.targetName : review.authorName,
              subtitle:
                  '${review.jobTitle}\n'
                  '${review.feedback.isEmpty ? 'No comment provided.' : review.feedback}\n'
                  '${review.displayDate}',
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber),
                  Text(
                    review.rating == null
                        ? 'Feedback'
                        : '${review.rating!.toStringAsFixed(1)}/5',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
