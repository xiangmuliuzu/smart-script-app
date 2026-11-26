// 任务发布 → 平台审核 → 末轮验收后看最终作品（App 端契约）。
//
// 口径来源：后端 AppTradeDemandController（POST/PUT /trade/demand、
// GET /trade/demand/{id}/stage/{stageId}/deliverable-work）与 TradeDemandService
// 的 DEMAND_STATUS_PENDING_REVIEW / DEMAND_STATUS_REJECTED。
// 逐轮验收、延时审批、关闭征集都在管理端，App 只提供发布/编辑重交与最终作品查阅。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/constants/api_endpoints.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/trade/data/demand_repository.dart';
import 'package:script_app/features/trade/data/trade_models.dart';

import '../support/scripted_api.dart';

void main() {
  group('审核态模型', () {
    test('待审核/审核未通过有中文标签，且不进广场曝光', () {
      expect(DemandStatus.label(DemandStatus.pendingReview), '待审核');
      expect(DemandStatus.label(DemandStatus.rejected), '审核未通过');
      expect(DemandStatus.isAuditState(DemandStatus.pendingReview), isTrue);
      expect(DemandStatus.isAuditState(DemandStatus.rejected), isTrue);
      expect(DemandStatus.isAuditState(DemandStatus.open), isFalse);
    });

    test('审核态文案优先于逾期：没进广场的单谈不上逾期', () {
      const overdueAudit = DemandTask(
        demandId: 1,
        status: DemandStatus.pendingReview,
        isOverdue: 1,
      );
      expect(overdueAudit.statusLabel, '待审核');
    });

    test('只有审核态允许发布方改单，驳回带书面意见', () {
      const rejected = DemandTask(
        demandId: 2,
        status: DemandStatus.rejected,
        auditRemark: '题材定位不清，请补充每集字数',
      );
      expect(rejected.isEditableByPublisher, isTrue);
      expect(rejected.auditRemark, contains('每集字数'));
      for (final status in [
        DemandStatus.open,
        DemandStatus.inProgress,
        DemandStatus.completed,
      ]) {
        expect(DemandTask(status: status).isEditableByPublisher, isFalse,
            reason: '$status 已过了端上可改的窗口');
      }
    });
  });

  group('发布/编辑入参口径', () {
    test('POST 建单：预算走分、轮次金额走元、首轮时限镜像到整单', () async {
      final api = ScriptedApi();
      api.reply(ApiEndpoints.demandCreate,
          Envelope.ok({'demandId': 9601, 'status': DemandStatus.pendingReview}));
      final repo = DemandRepository(ApiClient(api.buildDio()));

      await repo.createDemand(
        title: '24 集都市甜宠短剧编剧招募',
        budget: 800000, // 分
        totalEpisodes: 24,
        durationHours: 168,
        contactInfo: '13800000000',
        taskType: 'script',
        stages: <Map<String, dynamic>>[
          {'stageOrder': 1, 'episodeTo': 8, 'amount': 3000.0, 'durationHours': 168},
          {'stageOrder': 2, 'episodeTo': 24, 'amount': 5000.0, 'durationHours': 72},
        ],
      );

      final request = api.requests.single;
      expect(request.method, 'POST');
      final body = request.data as Map<String, dynamic>;
      expect(body['budget'], 800000, reason: '整单预算按分下发，后端 fenToYuan 入库');
      expect((body['stages'] as List).first['amount'], 3000.0,
          reason: '轮次金额按元下发，后端 parseStages 不做单位换算');
      expect(body['durationHours'], 168,
          reason: 'sys_demand.duration_hours 是首轮时限镜像列，缺省会落服务端默认值');
      expect(body['contactInfo'], '13800000000');
    });

    test('PUT 改单走同一路径前缀，空字段不覆盖后端', () async {
      final api = ScriptedApi();
      api.reply('/trade/demand/9601',
          Envelope.ok({'demandId': 9601, 'status': DemandStatus.pendingReview}));
      final repo = DemandRepository(ApiClient(api.buildDio()));

      await repo.updateDemand(
        demandId: 9601,
        title: '改后的标题',
        budget: 500000,
        totalEpisodes: 24,
        durationHours: 120,
        stages: const <Map<String, dynamic>>[
          {'stageOrder': 1, 'episodeTo': 24, 'amount': 5000.0, 'durationHours': 120},
        ],
      );

      final request = api.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/trade/demand/9601');
      final body = request.data as Map<String, dynamic>;
      expect(body.containsKey('tags'), isFalse, reason: '_compact 丢弃 null，缺省字段不占位');
      expect(body['contactInfo'], isNull, reason: '未填联系方式时不下发，避免覆盖成空串');
    });

    test('发布页把首轮时限同时写进整单镜像列（发布与编辑两条分支都要）', () {
      final src =
          File('lib/features/trade/pages/demand_post_page.dart').readAsStringSync();
      expect(src, contains('durationHours: firstStageHours'));
      expect(src, contains("stagesPayload.first['durationHours']"),
          reason: 'firstStageHours 取自首轮，而不是最后一轮时限');
      // 轮次金额下发元、整单预算下发分，两条口径不能混
      expect(src, contains("'amount': amtFen / 100.0"));
      expect(src, contains('budget: budgetFen'));
    });
  });

  group('最终作品查阅', () {
    test('走末轮 deliverable-work 端点，正文只到本轮集数', () async {
      final api = ScriptedApi();
      api.reply('/deliverable-work', Envelope.ok({
        'workId': 501,
        'title': '长夜',
        'stageOrder': 3,
        'episodeTo': 24,
        'stageStatus': 'approved',
        'chapters': [
          {'chapterId': 1, 'chapterNo': 23, 'content': '正文甲', 'readable': true},
          {'chapterId': 2, 'chapterNo': 24, 'content': '正文乙', 'readable': true},
          {'chapterId': 3, 'chapterNo': 25, 'readable': false},
        ],
      }));
      final repo = DemandRepository(ApiClient(api.buildDio()));

      final view = await repo.deliverableWork(9601, 3);
      expect(api.requests.single.path,
          '/trade/demand/9601/stage/3/deliverable-work');
      expect(view.stageOrder, 3);
      expect(view.chapters.length, 3);
      expect(view.readableCount, 2, reason: '超出本轮集数的章只有标题，readable=false');
    });

    test('入口只对整单完成后的需求方开放，门槛文案原样透出后端结论', () {
      final detail =
          File('lib/features/trade/pages/demand_detail_page.dart').readAsStringSync();
      expect(detail, contains('task.status == DemandStatus.completed'));
      expect(detail, contains('demandDeliverableWorkUrl'));
      expect(detail, contains('_buildFinalWorkEntry'),
          reason: '末轮 stageId 由页面拼装，端上不另判一套验收规则');

      final workPage = File('lib/features/trade/pages/demand_deliverable_work_page.dart')
          .readAsStringSync();
      expect(workPage, contains('e.message'),
          reason: '「任务尚未完成验收」等后端结论直接展示，不在客户端复述规则');
    });

    test('发布/最终作品路由需登录，审核态可见性交服务端按参与方判定', () {
      expect(ProtectedRoutes.isProtected(RoutePath.demandPost), isTrue);
      expect(ProtectedRoutes.isProtected(RoutePath.demandDeliverableWork), isTrue);
      // 广场浏览路径保持游客可进
      expect(ProtectedRoutes.isProtected(RoutePath.demandDetail), isFalse);
    });
  });

  group('买方端不越权操作', () {
    test('轮次面板按宿主身份决定能否交付，需求方只读进度', () {
      final panel =
          File('lib/features/trade/widgets/demand_stage_panel.dart').readAsStringSync();
      expect(panel, contains('this.canDeliver = false'),
          reason: '默认只读，交付动作必须由宿主显式打开');
      expect(panel, contains('widget.canDeliver &&'));

      final detail =
          File('lib/features/trade/pages/demand_detail_page.dart').readAsStringSync();
      expect(detail, contains('DemandStagePanel(demandId: task.demandId!, canDeliver: isClaimer)'),
          reason: '只有接单人拿到交付能力，需求方看同一份时间线但只读');
    });

    test('App 不再有验收/延时审批/关闭征集的调用', () {
      for (final file in Directory('lib/features/trade')
          .listSync(recursive: true)
          .whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final src = file.readAsStringSync();
        for (final forbidden in ['/review', '/close', '/extend/approve']) {
          expect(src, isNot(contains("'$forbidden'")),
              reason: '${file.path} 仍在调用平台侧动作 $forbidden');
        }
      }
    });
  });
}
