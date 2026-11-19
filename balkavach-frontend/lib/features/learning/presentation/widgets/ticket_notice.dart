import '../../../../l10n/app_localizations.dart';
import '../../data/play_ticket_client.dart';
import '../../data/ticketed_playback.dart';

/// What a player shows instead of the video while play tickets keep it from
/// playing, or null when nothing ticket-related blocks playback. Exhaustion is
/// not here: the players open the lock page for it, as before.
String? ticketNotice(AppLocalizations l10n, TicketedPlayback tickets) {
  if (tickets.waiting) return l10n.videoTicketStarting;
  if (tickets.phase != TicketPhase.stopped) return null;
  return switch (tickets.stopReason) {
    TicketStop.superseded => l10n.videoTicketSuperseded,
    TicketStop.revoked => l10n.videoTicketRevoked,
    TicketStop.offline => l10n.videoOfflinePaused,
    TicketStop.exhausted => l10n.videoAllowanceLocked,
    TicketStop.expired || TicketStop.invalid || null => l10n.videoTicketStopped,
  };
}

/// Whether the child may retry from this ticket state (a new ticket).
bool ticketRetryable(TicketedPlayback tickets) =>
    tickets.phase == TicketPhase.stopped &&
    tickets.stopReason != TicketStop.exhausted &&
    tickets.stopReason != TicketStop.revoked;
