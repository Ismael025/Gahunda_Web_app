import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_gateway.dart';
import 'web_notification_gateway.dart';

NotificationGateway createNotificationGateway({SupabaseClient? client}) =>
    WebNotificationGateway(client: client);
