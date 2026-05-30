import 'package:flutter/material.dart';
import 'package:run_track_app/features/club_hub/presentation/view_models/club_hub_view_model.dart';
import 'package:run_track_app/core/widgets/layout_gaps.dart';
import 'package:run_track_app/core/widgets/premium_card.dart';
import 'package:run_track_app/core/widgets/athlete_avatar.dart';
import 'package:run_track_app/core/theme/club_theme_config.dart';
import 'package:run_track_app/core/theme/premium_typography.dart';

class ClubHubView extends StatelessWidget {
  const ClubHubView({required this.viewModel, super.key});

  final ClubHubViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (viewModel.state == null) {
          return const Center(child: Text("No sessions found."));
        }
        return _ClubHubLayout(
          state: viewModel.state!,
          onRsvpChanged: (sessionId, status) =>
              viewModel.updateRsvp(sessionId, status),
        );
      },
    );
  }
}

class _ClubHubLayout extends StatelessWidget {
  const _ClubHubLayout({required this.state, required this.onRsvpChanged});

  final ClubHubState state;
  final Function(String, String) onRsvpChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: context.spacingTokens.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final session in state.sessions) ...[
              _SessionCard(
                session: session,
                onRsvpChanged: (status) => onRsvpChanged(session.id, status),
              ),
              const VerticalGap(),
            ],
            for (final stagedItem in state.stagedItems)
              _NewsletterStagingCard(item: stagedItem),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onRsvpChanged});

  final ClubSessionItem session;
  final ValueChanged<String> onRsvpChanged;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: Theme.of(context).textTheme.serifSectionTitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (session.athleteName != null)
                      Text(
                        'Organised by ${session.athleteName}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    const VerticalGap(),
                    Text(session.description),
                  ],
                ),
              ),
              const HorizontalGap(),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      session.date,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(session.time, textAlign: TextAlign.right),
                  ],
                ),
              ),
            ],
          ),
          const VerticalGap(),
          Divider(color: ClubThemeTokens.of(context).subtleStrokeColor),
          const VerticalGap(),
          _RSVPSection(
            currentStatus: session.currentUserRsvp,
            onStatusChanged: onRsvpChanged,
          ),
          const VerticalGap(),
          PremiumCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const HorizontalGap(),
                Expanded(
                  child: Text(
                    session.location,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const VerticalGap(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final attendee in session.attendees) ...[
                  _AttendeeWithStatus(attendee: attendee),
                  const HorizontalGap(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RSVPSection extends StatelessWidget {
  const _RSVPSection({
    required this.currentStatus,
    required this.onStatusChanged,
  });
  final String currentStatus;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RSVPButton(
          label: 'YES',
          isSelected: currentStatus == 'yes',
          onPressed: () => onStatusChanged('yes'),
        ),
        const SizedBox(width: 8),
        _RSVPButton(
          label: 'NO',
          isSelected: currentStatus == 'no',
          onPressed: () => onStatusChanged('no'),
        ),
        const SizedBox(width: 8),
        _RSVPButton(
          label: 'MAYBE',
          isSelected: currentStatus == 'maybe',
          onPressed: () => onStatusChanged('maybe'),
        ),
      ],
    );
  }
}

class _RSVPButton extends StatelessWidget {
  const _RSVPButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = ClubThemeTokens.of(context);

    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? colorScheme.primary : null,
          foregroundColor: isSelected
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
          side: BorderSide(
            color: isSelected ? colorScheme.primary : tokens.strokeColor,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.borderRadius / 2),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _AttendeeWithStatus extends StatelessWidget {
  const _AttendeeWithStatus({required this.attendee});
  final ClubSessionAttendee attendee;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (attendee.rsvpStatus) {
      'yes' => Colors.green,
      'maybe' => Colors.orange,
      _ => Colors.grey,
    };

    return Stack(
      children: [
        AthleteAvatar(
          initials: attendee.initials,
          imageUrl: attendee.imageUrl,
          size: 36,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewsletterStagingCard extends StatelessWidget {
  const _NewsletterStagingCard({required this.item});

  final NewsletterStagingItem item;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Newsletter extraction',
                  style: Theme.of(context).textTheme.serifSectionTitle,
                ),
              ),
              const HorizontalGap(),
              _StatusPill(label: item.status),
            ],
          ),
          const VerticalGap(),
          Text(item.description),
          const VerticalGap(),
          _DetailRow(label: 'Date', value: item.date),
          const _SoftDivider(),
          _DetailRow(label: 'Time', value: item.time),
          const _SoftDivider(),
          _DetailRow(label: 'Location', value: item.location),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        const HorizontalGap(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = ClubThemeTokens.of(context);
    final spacingTokens = context.spacingTokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.subtleFillColor,
        border: Border.all(color: tokens.strokeColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacingTokens.tight),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacingTokens.gap),
      child: Divider(color: ClubThemeTokens.of(context).subtleStrokeColor),
    );
  }
}
