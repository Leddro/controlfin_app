import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/avatar_service.dart';

/// Círculo com a foto: a escolhida no app, senão a do Google, senão a
/// inicial do nome ou do e-mail.
class AvatarCircle extends StatelessWidget {
  final Uint8List? bytes;
  final String? photoUrl;
  final String label;
  final double radius;

  const AvatarCircle({
    super.key,
    this.bytes,
    this.photoUrl,
    required this.label,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ImageProvider? image;
    if (bytes != null) {
      image = MemoryImage(bytes!);
    } else if (photoUrl != null) {
      image = NetworkImage(photoUrl!);
    }
    final initial = label.trim().characters.take(1).toString().toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      foregroundImage: image,
      onForegroundImageError: image == null ? null : (_, __) {},
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Foto do usuário logado, atualizada quando ele troca a foto ou o nome.
class UserAvatar extends StatefulWidget {
  final double radius;

  const UserAvatar({super.key, this.radius = 20});

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  final _userStream = FirebaseAuth.instance.userChanges();
  final _avatarStream = AvatarService().watch();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _userStream,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, userSnap) {
        final user = userSnap.data;
        return StreamBuilder<Uint8List?>(
          stream: _avatarStream,
          builder: (context, avatarSnap) => AvatarCircle(
            bytes: avatarSnap.data,
            photoUrl: user?.photoURL,
            label: user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!
                : user?.email ?? '?',
            radius: widget.radius,
          ),
        );
      },
    );
  }
}
