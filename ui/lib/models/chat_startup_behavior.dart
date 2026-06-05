enum ChatStartupBehavior {
  resumeLast('resume_last'),
  newConversation('new_conversation');

  const ChatStartupBehavior(this.storageValue);

  final String storageValue;

  static ChatStartupBehavior fromStorageValue(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final behavior in ChatStartupBehavior.values) {
      if (behavior.storageValue == normalized) {
        return behavior;
      }
    }
    return ChatStartupBehavior.resumeLast;
  }

  String get legacyLabel => switch (this) {
    ChatStartupBehavior.resumeLast => '恢复上次关闭对话',
    ChatStartupBehavior.newConversation => '新对话',
  };
}
