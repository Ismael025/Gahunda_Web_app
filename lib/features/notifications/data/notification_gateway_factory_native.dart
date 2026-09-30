import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notification_gateway.dart';
import 'notification_gateway.dart';

NotificationGateway createNotificationGateway({SupabaseClient? client}) =>
    LocalNotificationGateway();
