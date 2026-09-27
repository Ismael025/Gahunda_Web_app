import 'notification_gateway.dart';
import 'web_notification_gateway.dart';

NotificationGateway createNotificationGateway() => WebNotificationGateway();
