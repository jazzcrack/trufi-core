import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

/// fahrplaner.de fork patch 66: a planner index built elsewhere (server-side
/// regional timetable package) loads straight from a file - gzipped or not -
/// and a wrong fingerprint fails loudly instead of building.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = File(
    '../trufi_core_planner/test/fixtures/sanaa_issue2_mini.gtfs.zip',
  );
  late Directory tempDir;
  late String fingerprint;
  late PlannerIndexBundle built;

  setUpAll(() {
    final zip = fixture.readAsBytesSync();
    fingerprint = PlannerIndexCodec.fingerprint(zip);
    built = PlannerIndexBundle.build(zip);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('planner-snapshot-file-');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<TrufiPlannerDataSource> load(
    String name,
    String fp, {
    bool gz = false,
  }) async {
    final blob = PlannerIndexCodec.encode(built, fingerprint: fingerprint);
    final file = File('${tempDir.path}/$name')
      ..writeAsBytesSync(gz ? gzip.encode(blob) : blob);
    final ds = TrufiPlannerDataSource(
      config: TrufiPlannerConfig.localSnapshot(
        snapshotFile: file.path,
        snapshotFingerprint: fp,
      ),
    );
    await _preloadQuietly(ds);
    return ds;
  }

  test('gzipped snapshot loads without building', () async {
    final ds = await load('region.idx.gz', fingerprint, gz: true);
    expect(ds.status, TrufiPlannerDataStatus.loaded);
    expect(ds.lastIndexLoad!.source, PlannerIndexSource.cache);
    expect(ds.data!.stops.length, built.data.stops.length);
    expect(ds.scheduleIndex, isNotNull);
  });

  test('plain snapshot loads too', () async {
    final ds = await load('region.idx', fingerprint);
    expect(ds.status, TrufiPlannerDataStatus.loaded);
  });

  test(
    'wrong fingerprint or missing file ends in error, never a build',
    () async {
      final wrong = await load('region.idx.gz', 'nicht-passend', gz: true);
      expect(wrong.status, TrufiPlannerDataStatus.error);
      expect(wrong.errorMessage, contains('rejected'));

      final missing = TrufiPlannerDataSource(
        config: TrufiPlannerConfig.localSnapshot(
          snapshotFile: '${tempDir.path}/fehlt.idx.gz',
          snapshotFingerprint: fingerprint,
        ),
      );
      await _preloadQuietly(missing);
      expect(missing.status, TrufiPlannerDataStatus.error);
    },
  );

  test(
    'switchTo: neue Region im selben Objekt, Fehler -> alter Stand bleibt',
    () async {
      final first = await load('a.idx.gz', fingerprint, gz: true);
      expect(first.generation.value, 0);
      final blob = PlannerIndexCodec.encode(built, fingerprint: fingerprint);
      final second = File('${tempDir.path}/b.idx')..writeAsBytesSync(blob);
      await first.switchTo(
        TrufiPlannerConfig.localSnapshot(
          snapshotFile: second.path,
          snapshotFingerprint: fingerprint,
        ),
      );
      expect(first.generation.value, 1);
      expect(first.config.snapshotFile, second.path);
      expect(first.status, TrufiPlannerDataStatus.loaded);

      final stops = first.data!.stops.length;
      await expectLater(
        first.switchTo(
          TrufiPlannerConfig.localSnapshot(
            snapshotFile: '${tempDir.path}/fehlt.idx.gz',
            snapshotFingerprint: fingerprint,
          ),
        ),
        throwsA(anything),
      );
      expect(first.generation.value, 1);
      expect(first.config.snapshotFile, second.path);
      expect(first.status, TrufiPlannerDataStatus.loaded);
      expect(first.data!.stops.length, stops);
      expect(
        first.findNearestStops(
          first.data!.stops.values.first.position,
          maxDistance: 50,
        ),
        isNotEmpty,
      );
    },
  );

  test('config: snapshot mode is local, not remote', () {
    const config = TrufiPlannerConfig.localSnapshot(
      snapshotFile: '/x.idx.gz',
      snapshotFingerprint: 'f',
    );
    expect(config.isLocal, isTrue);
    expect(config.isRemote, isFalse);
    expect(config.gtfsAsset, isNull);
    expect(config.persistIndex, isFalse);
  });
}

/// preload() completes its internal completer with the error as well; in a
/// test zone that surfaces as an unhandled error (same as for a broken asset).
Future<void> _preloadQuietly(TrufiPlannerDataSource ds) {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      await ds.preload();
      if (!done.isCompleted) done.complete();
    },
    (_, _) {
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}
