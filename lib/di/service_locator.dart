import 'package:get_it/get_it.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/exam_map.dart';
import 'package:preconnect/api/custom_schedules.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/api/api_client.dart';

final getIt = GetIt.instance;

void setupLocator() {
  getIt.registerLazySingleton<ApiClient>(() => ApiClient());
  getIt.registerLazySingleton<ProfileService>(() => ProfileService.create());
  getIt.registerLazySingleton<AdvisingService>(() => AdvisingService.create());
  getIt.registerLazySingleton<ExamMapService>(() => ExamMapService.create());
  getIt.registerLazySingleton<CustomSchedulesService>(
    () => CustomSchedulesService.create(),
  );
  getIt.registerLazySingleton<SeatStatusService>(
    () => SeatStatusService.create(),
  );
}
