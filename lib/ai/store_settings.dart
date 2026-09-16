import '../packs/pack_store.dart';
import 'assistant.dart';

/// Keeps the assistant's settings in the store's registry database, next to
/// everything else the app remembers between runs.
class StoreAssistantSettings implements AssistantSettings {
  const StoreAssistantSettings(this.store);

  final PackStore store;

  @override
  String? read(String key) => store.setting(key);

  @override
  void write(String key, String? value) => store.saveSetting(key, value);
}
