import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_auth.dart';
import 'package:ods_flutter_local/models/ods_ownership.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_data_source.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/models/ods_menu_item.dart';
import 'package:ods_flutter_local/models/ods_page.dart';

void main() {
  group('OdsAuth', () {
    test('defaults to single-user mode', () {
      const auth = OdsAuth();
      expect(auth.multiUser, false);
      expect(auth.multiUserOnly, false);
      expect(auth.customRoles, isEmpty);
      expect(auth.defaultRole, 'user');
    });

    test('parses from null as defaults', () {
      final auth = OdsAuth.fromJson(null);
      expect(auth.multiUser, false);
      expect(auth.customRoles, isEmpty);
    });

    test('parses full auth block', () {
      final auth = OdsAuth.fromJson({
        'multiUser': true,
        'multiUserOnly': true,
        'roles': ['manager', 'viewer'],
        'defaultRole': 'viewer',
      });
      expect(auth.multiUser, true);
      expect(auth.multiUserOnly, true);
      expect(auth.customRoles, ['manager', 'viewer']);
      expect(auth.defaultRole, 'viewer');
    });

    test('allRoles includes built-ins plus custom', () {
      final auth = OdsAuth.fromJson({
        'multiUser': true,
        'roles': ['manager'],
      });
      expect(auth.allRoles, containsAll(['guest', 'user', 'admin', 'manager']));
    });

    test('toJson omits defaults', () {
      const auth = OdsAuth();
      final json = auth.toJson();
      expect(json['multiUser'], false);
      expect(json.containsKey('multiUserOnly'), false);
      expect(json.containsKey('roles'), false);
      expect(json.containsKey('defaultRole'), false);
    });

    test('toJson includes non-defaults', () {
      const auth = OdsAuth(
        multiUser: true,
        multiUserOnly: true,
        customRoles: ['editor'],
        defaultRole: 'editor',
      );
      final json = auth.toJson();
      expect(json['multiUser'], true);
      expect(json['multiUserOnly'], true);
      expect(json['roles'], ['editor']);
      expect(json['defaultRole'], 'editor');
    });
  });

  group('OdsOwnership', () {
    test('defaults to disabled', () {
      const ownership = OdsOwnership();
      expect(ownership.enabled, false);
      expect(ownership.ownerField, '_owner');
      expect(ownership.adminOverride, true);
    });

    test('parses from null as defaults', () {
      final ownership = OdsOwnership.fromJson(null);
      expect(ownership.enabled, false);
    });

    test('parses full ownership block', () {
      final ownership = OdsOwnership.fromJson({
        'enabled': true,
        'ownerField': 'createdBy',
        'adminOverride': false,
      });
      expect(ownership.enabled, true);
      expect(ownership.ownerField, 'createdBy');
      expect(ownership.adminOverride, false);
    });

    test('toJson omits defaults when disabled', () {
      const ownership = OdsOwnership();
      final json = ownership.toJson();
      // When disabled, toJson should not include the ownership block
      expect(json.containsKey('ownerField'), false);
    });
  });

  group('Roles on models', () {
    test('OdsApp parses auth', () {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'home',
        'auth': {'multiUser': true, 'roles': ['manager']},
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      expect(app.auth.multiUser, true);
      expect(app.auth.customRoles, ['manager']);
    });

    test('OdsApp defaults auth when absent', () {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'home',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      expect(app.auth.multiUser, false);
    });

    test('OdsMenuItem parses roles', () {
      final item = OdsMenuItem.fromJson({
        'label': 'Admin',
        'mapsTo': 'adminPage',
        'roles': ['admin'],
      });
      expect(item.roles, ['admin']);
    });

    test('OdsMenuItem roles default to null', () {
      final item = OdsMenuItem.fromJson({
        'label': 'Home',
        'mapsTo': 'homePage',
      });
      expect(item.roles, isNull);
    });

    test('OdsPage parses roles', () {
      final page = OdsPage.fromJson({
        'title': 'Admin',
        'roles': ['admin', 'manager'],
        'content': [],
      });
      expect(page.roles, ['admin', 'manager']);
    });

    test('OdsTextComponent parses roles', () {
      final comp = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Secret',
        'roles': ['admin'],
      });
      expect(comp.roles, ['admin']);
    });

    test('OdsButtonComponent parses roles', () {
      final comp = OdsComponent.fromJson({
        'component': 'button',
        'label': 'Delete All',
        'onClick': [{'action': 'navigate', 'target': 'home'}],
        'roles': ['admin'],
      });
      expect(comp.roles, ['admin']);
    });

    test('OdsListColumn parses roles', () {
      final col = OdsListColumn.fromJson({
        'header': 'Salary',
        'field': 'salary',
        'roles': ['admin', 'hr'],
      });
      expect(col.roles, ['admin', 'hr']);
    });

    test('OdsRowAction parses roles', () {
      final action = OdsRowAction.fromJson({
        'label': 'Delete',
        'action': 'delete',
        'dataSource': 'ds',
        'roles': ['admin'],
      });
      expect(action.roles, ['admin']);
    });

    test('OdsFieldDefinition parses roles', () {
      final field = OdsFieldDefinition.fromJson({
        'name': 'secret',
        'type': 'text',
        'roles': ['admin'],
      });
      expect(field.roles, ['admin']);
    });

    test('OdsFieldDefinition includes roles in toJson', () {
      final field = OdsFieldDefinition.fromJson({
        'name': 'secret',
        'type': 'text',
        'roles': ['admin'],
      });
      expect(field.toJson()['roles'], ['admin']);
    });

    test('OdsDataSource parses ownership', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://tasks',
        'method': 'GET',
        'ownership': {'enabled': true, 'adminOverride': true},
      });
      expect(ds.ownership.enabled, true);
      expect(ds.ownership.adminOverride, true);
    });

    test('OdsDataSource defaults ownership when absent', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://tasks',
        'method': 'GET',
      });
      expect(ds.ownership.enabled, false);
    });
  });
}
