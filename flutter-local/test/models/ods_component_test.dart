import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_component.dart';

void main() {
  // =========================================================================
  // Text Component
  // =========================================================================

  group('OdsTextComponent.fromJson', () {
    test('parses content', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Hello world',
      });
      expect(c, isA<OdsTextComponent>());
      expect((c as OdsTextComponent).content, 'Hello world');
    });

    test('defaults format to plain', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Hello',
      }) as OdsTextComponent;
      expect(c.format, 'plain');
    });

    test('parses explicit format', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': '# Title',
        'format': 'markdown',
      }) as OdsTextComponent;
      expect(c.format, 'markdown');
    });

    test('parses styleHint', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Styled',
        'styleHint': {'variant': 'heading'},
      }) as OdsTextComponent;
      expect(c.styleHint.variant, 'heading');
    });

    test('parses visibleWhen', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Conditional',
        'visibleWhen': {
          'field': 'status',
          'form': 'myForm',
          'equals': 'active',
        },
      }) as OdsTextComponent;
      expect(c.visibleWhen, isNotNull);
      expect(c.visibleWhen!.field, 'status');
      expect(c.visibleWhen!.form, 'myForm');
      expect(c.visibleWhen!.equals, 'active');
    });

    test('parses roles', () {
      final c = OdsComponent.fromJson({
        'component': 'text',
        'content': 'Admin only',
        'roles': ['admin', 'superuser'],
      }) as OdsTextComponent;
      expect(c.roles, ['admin', 'superuser']);
    });
  });

  // =========================================================================
  // List Component
  // =========================================================================

  group('OdsListComponent.fromJson', () {
    test('parses dataSource and columns', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'tasks',
        'columns': [
          {'header': 'Name', 'field': 'name'},
          {'header': 'Status', 'field': 'status'},
        ],
      }) as OdsListComponent;
      expect(c.dataSource, 'tasks');
      expect(c.columns.length, 2);
      expect(c.columns[0].header, 'Name');
      expect(c.columns[0].field, 'name');
      expect(c.columns[1].header, 'Status');
      expect(c.columns[1].field, 'status');
    });

    test('column defaults: sortable, filterable, currency are false', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
      }) as OdsListComponent;
      final col = c.columns[0];
      expect(col.sortable, false);
      expect(col.filterable, false);
      expect(col.currency, false);
    });

    test('column parses sortable, filterable, currency', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {
            'header': 'Amount',
            'field': 'amount',
            'sortable': true,
            'filterable': true,
            'currency': true,
          },
        ],
      }) as OdsListComponent;
      final col = c.columns[0];
      expect(col.sortable, true);
      expect(col.filterable, true);
      expect(col.currency, true);
    });

    test('parses rowActions', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'rowActions': [
          {
            'label': 'Delete',
            'action': 'delete',
            'dataSource': 'ds',
            'matchField': '_id',
          },
        ],
      }) as OdsListComponent;
      expect(c.rowActions.length, 1);
      expect(c.rowActions[0].label, 'Delete');
      expect(c.rowActions[0].action, 'delete');
      expect(c.rowActions[0].isDelete, true);
    });

    test('rowActions default to empty list', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
      }) as OdsListComponent;
      expect(c.rowActions, isEmpty);
    });

    test('parses summary rules', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'summary': [
          {'column': 'amount', 'function': 'sum', 'label': 'Total'},
        ],
      }) as OdsListComponent;
      expect(c.summary.length, 1);
      expect(c.summary[0].column, 'amount');
      expect(c.summary[0].function, 'sum');
      expect(c.summary[0].label, 'Total');
    });

    test('parses onRowTap', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'onRowTap': {
          'target': 'detailPage',
          'populateForm': 'editForm',
        },
      }) as OdsListComponent;
      expect(c.onRowTap, isNotNull);
      expect(c.onRowTap!.target, 'detailPage');
      expect(c.onRowTap!.populateForm, 'editForm');
    });

    test('defaults searchable to false', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
      }) as OdsListComponent;
      expect(c.searchable, false);
    });

    test('parses searchable true', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'searchable': true,
      }) as OdsListComponent;
      expect(c.searchable, true);
    });

    test('defaults displayAs to table', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
      }) as OdsListComponent;
      expect(c.displayAs, 'table');
    });

    test('parses displayAs cards', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'displayAs': 'cards',
      }) as OdsListComponent;
      expect(c.displayAs, 'cards');
    });

    test('parses defaultSort', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'defaultSort': {'field': 'name', 'direction': 'desc'},
      }) as OdsListComponent;
      expect(c.defaultSort, isNotNull);
      expect(c.defaultSort!.field, 'name');
      expect(c.defaultSort!.direction, 'desc');
    });

    test('parses rowColorField and rowColorMap', () {
      final c = OdsComponent.fromJson({
        'component': 'list',
        'dataSource': 'ds',
        'columns': [
          {'header': 'H', 'field': 'f'},
        ],
        'rowColorField': 'priority',
        'rowColorMap': {'high': 'red', 'low': 'green'},
      }) as OdsListComponent;
      expect(c.rowColorField, 'priority');
      expect(c.rowColorMap, {'high': 'red', 'low': 'green'});
    });
  });

  // =========================================================================
  // Form Component
  // =========================================================================

  group('OdsFormComponent.fromJson', () {
    test('parses id and fields', () {
      final c = OdsComponent.fromJson({
        'component': 'form',
        'id': 'myForm',
        'fields': [
          {'name': 'title', 'type': 'text'},
          {'name': 'count', 'type': 'number'},
        ],
      }) as OdsFormComponent;
      expect(c.id, 'myForm');
      expect(c.fields.length, 2);
      expect(c.fields[0].name, 'title');
      expect(c.fields[0].type, 'text');
      expect(c.fields[1].name, 'count');
      expect(c.fields[1].type, 'number');
    });

    test('parses recordSource', () {
      final c = OdsComponent.fromJson({
        'component': 'form',
        'id': 'quizForm',
        'fields': [
          {'name': 'question', 'type': 'text'},
        ],
        'recordSource': 'questions',
      }) as OdsFormComponent;
      expect(c.recordSource, 'questions');
    });

    test('recordSource defaults to null', () {
      final c = OdsComponent.fromJson({
        'component': 'form',
        'id': 'f1',
        'fields': [
          {'name': 'x', 'type': 'text'},
        ],
      }) as OdsFormComponent;
      expect(c.recordSource, isNull);
    });
  });

  // =========================================================================
  // Button Component
  // =========================================================================

  group('OdsButtonComponent.fromJson', () {
    test('parses label and onClick actions', () {
      final c = OdsComponent.fromJson({
        'component': 'button',
        'label': 'Save',
        'onClick': [
          {'action': 'submit', 'target': 'myForm', 'dataSource': 'tasks'},
          {'action': 'navigate', 'target': 'home'},
        ],
      }) as OdsButtonComponent;
      expect(c.label, 'Save');
      expect(c.onClick.length, 2);
      expect(c.onClick[0].action, 'submit');
      expect(c.onClick[0].target, 'myForm');
      expect(c.onClick[0].dataSource, 'tasks');
      expect(c.onClick[1].action, 'navigate');
      expect(c.onClick[1].target, 'home');
    });
  });

  // =========================================================================
  // Chart Component
  // =========================================================================

  group('OdsChartComponent.fromJson', () {
    test('parses dataSource, labelField, valueField', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'sales',
        'labelField': 'month',
        'valueField': 'revenue',
      }) as OdsChartComponent;
      expect(c.dataSource, 'sales');
      expect(c.labelField, 'month');
      expect(c.valueField, 'revenue');
    });

    test('defaults chartType to bar', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'x',
        'valueField': 'y',
      }) as OdsChartComponent;
      expect(c.chartType, 'bar');
    });

    test('parses explicit chartType', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'chartType': 'pie',
        'labelField': 'x',
        'valueField': 'y',
      }) as OdsChartComponent;
      expect(c.chartType, 'pie');
    });

    test('normalizes aggregate "count"', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'x',
        'valueField': 'y',
        'aggregate': 'Count',
      }) as OdsChartComponent;
      expect(c.aggregate, 'count');
    });

    test('normalizes aggregate "average" to avg', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'x',
        'valueField': 'y',
        'aggregate': 'Average',
      }) as OdsChartComponent;
      expect(c.aggregate, 'avg');
    });

    test('normalizes aggregate "avg"', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'x',
        'valueField': 'y',
        'aggregate': 'avg',
      }) as OdsChartComponent;
      expect(c.aggregate, 'avg');
    });

    test('normalizes aggregate "sum"', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'x',
        'valueField': 'y',
        'aggregate': 'Sum',
      }) as OdsChartComponent;
      expect(c.aggregate, 'sum');
    });

    test('defaults aggregate to count when labelField == valueField', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'category',
        'valueField': 'category',
      }) as OdsChartComponent;
      expect(c.aggregate, 'count');
    });

    test('defaults aggregate to sum when labelField != valueField', () {
      final c = OdsComponent.fromJson({
        'component': 'chart',
        'dataSource': 'ds',
        'labelField': 'category',
        'valueField': 'amount',
      }) as OdsChartComponent;
      expect(c.aggregate, 'sum');
    });
  });

  // =========================================================================
  // Summary Component
  // =========================================================================

  group('OdsSummaryComponent.fromJson', () {
    test('parses label and value', () {
      final c = OdsComponent.fromJson({
        'component': 'summary',
        'label': 'Total Spent',
        'value': '{SUM(expenses, amount)}',
      }) as OdsSummaryComponent;
      expect(c.label, 'Total Spent');
      expect(c.value, '{SUM(expenses, amount)}');
    });

    test('parses icon', () {
      final c = OdsComponent.fromJson({
        'component': 'summary',
        'label': 'Revenue',
        'value': '1000',
        'icon': 'attach_money',
      }) as OdsSummaryComponent;
      expect(c.icon, 'attach_money');
    });

    test('icon defaults to null', () {
      final c = OdsComponent.fromJson({
        'component': 'summary',
        'label': 'Count',
        'value': '42',
      }) as OdsSummaryComponent;
      expect(c.icon, isNull);
    });
  });

  // =========================================================================
  // Tabs Component
  // =========================================================================

  group('OdsTabsComponent.fromJson', () {
    test('parses tabs with label and nested content', () {
      final c = OdsComponent.fromJson({
        'component': 'tabs',
        'tabs': [
          {
            'label': 'Overview',
            'content': [
              {'component': 'text', 'content': 'Welcome'},
            ],
          },
          {
            'label': 'Details',
            'content': [
              {'component': 'text', 'content': 'More info'},
            ],
          },
        ],
      }) as OdsTabsComponent;
      expect(c.tabs.length, 2);
      expect(c.tabs[0].label, 'Overview');
      expect(c.tabs[0].content.length, 1);
      expect(c.tabs[0].content[0], isA<OdsTextComponent>());
      expect((c.tabs[0].content[0] as OdsTextComponent).content, 'Welcome');
      expect(c.tabs[1].label, 'Details');
    });

    test('supports recursive nesting (tabs within tabs)', () {
      final c = OdsComponent.fromJson({
        'component': 'tabs',
        'tabs': [
          {
            'label': 'Outer',
            'content': [
              {
                'component': 'tabs',
                'tabs': [
                  {
                    'label': 'Inner',
                    'content': [
                      {'component': 'text', 'content': 'Nested'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }) as OdsTabsComponent;
      final innerTabs = c.tabs[0].content[0] as OdsTabsComponent;
      expect(innerTabs.tabs[0].label, 'Inner');
      expect(
        (innerTabs.tabs[0].content[0] as OdsTextComponent).content,
        'Nested',
      );
    });
  });

  // =========================================================================
  // Detail Component
  // =========================================================================

  group('OdsDetailComponent.fromJson', () {
    test('defaults dataSource to empty string', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
      }) as OdsDetailComponent;
      expect(c.dataSource, '');
    });

    test('parses dataSource', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
        'dataSource': 'users',
      }) as OdsDetailComponent;
      expect(c.dataSource, 'users');
    });

    test('parses fields list', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
        'dataSource': 'users',
        'fields': ['name', 'email', 'role'],
      }) as OdsDetailComponent;
      expect(c.fields, ['name', 'email', 'role']);
    });

    test('fields defaults to null', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
        'dataSource': 'users',
      }) as OdsDetailComponent;
      expect(c.fields, isNull);
    });

    test('parses labels map', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
        'dataSource': 'users',
        'labels': {'name': 'Full Name', 'email': 'Email Address'},
      }) as OdsDetailComponent;
      expect(c.labels, {'name': 'Full Name', 'email': 'Email Address'});
    });

    test('parses fromForm', () {
      final c = OdsComponent.fromJson({
        'component': 'detail',
        'fromForm': 'editForm',
      }) as OdsDetailComponent;
      expect(c.fromForm, 'editForm');
    });
  });

  // =========================================================================
  // Kanban Component
  // =========================================================================

  group('OdsKanbanComponent.fromJson', () {
    test('parses dataSource, statusField, titleField', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
        'titleField': 'name',
      }) as OdsKanbanComponent;
      expect(c.dataSource, 'tasks');
      expect(c.statusField, 'status');
      expect(c.titleField, 'name');
    });

    test('parses cardFields', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
        'cardFields': ['assignee', 'priority'],
      }) as OdsKanbanComponent;
      expect(c.cardFields, ['assignee', 'priority']);
    });

    test('cardFields defaults to empty list', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
      }) as OdsKanbanComponent;
      expect(c.cardFields, isEmpty);
    });

    test('parses rowActions', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
        'rowActions': [
          {
            'label': 'Archive',
            'action': 'update',
            'dataSource': 'tasks',
            'matchField': '_id',
            'values': {'archived': 'true'},
          },
        ],
      }) as OdsKanbanComponent;
      expect(c.rowActions.length, 1);
      expect(c.rowActions[0].label, 'Archive');
    });

    test('defaults searchable to false', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
      }) as OdsKanbanComponent;
      expect(c.searchable, false);
    });

    test('parses searchable true', () {
      final c = OdsComponent.fromJson({
        'component': 'kanban',
        'dataSource': 'tasks',
        'statusField': 'status',
        'searchable': true,
      }) as OdsKanbanComponent;
      expect(c.searchable, true);
    });
  });

  // =========================================================================
  // Unknown Component
  // =========================================================================

  group('OdsUnknownComponent.fromJson', () {
    test('preserves type and rawJson for unknown component', () {
      final json = {
        'component': 'futuristic-widget',
        'foo': 'bar',
        'count': 42,
      };
      final c = OdsComponent.fromJson(json);
      expect(c, isA<OdsUnknownComponent>());
      final unknown = c as OdsUnknownComponent;
      expect(unknown.component, 'futuristic-widget');
      expect(unknown.rawJson, json);
      expect(unknown.rawJson['foo'], 'bar');
      expect(unknown.rawJson['count'], 42);
    });
  });

  // =========================================================================
  // OdsRowActionHideWhen.matches()
  // =========================================================================

  group('OdsRowActionHideWhen.matches', () {
    test('equals match returns true', () {
      final hw = OdsRowActionHideWhen(field: 'status', equals: 'done');
      expect(hw.matches({'status': 'done'}), true);
    });

    test('equals no match returns false', () {
      final hw = OdsRowActionHideWhen(field: 'status', equals: 'done');
      expect(hw.matches({'status': 'open'}), false);
    });

    test('notEquals match returns true when value differs', () {
      final hw = OdsRowActionHideWhen(field: 'status', notEquals: 'open');
      expect(hw.matches({'status': 'done'}), true);
    });

    test('notEquals returns false when value matches', () {
      final hw = OdsRowActionHideWhen(field: 'status', notEquals: 'open');
      expect(hw.matches({'status': 'open'}), false);
    });

    test('no match returns false when neither equals nor notEquals set', () {
      final hw = OdsRowActionHideWhen(field: 'status');
      expect(hw.matches({'status': 'anything'}), false);
    });

    test('missing field treats value as empty string', () {
      final hw = OdsRowActionHideWhen(field: 'status', equals: '');
      expect(hw.matches({}), true);
    });

    test('missing field with notEquals empty string returns false', () {
      final hw = OdsRowActionHideWhen(field: 'status', notEquals: '');
      expect(hw.matches({}), false);
    });
  });

  // =========================================================================
  // OdsDefaultSort
  // =========================================================================

  group('OdsDefaultSort', () {
    test('parses field and direction', () {
      final s = OdsDefaultSort.fromJson({'field': 'name', 'direction': 'desc'});
      expect(s.field, 'name');
      expect(s.direction, 'desc');
    });

    test('defaults direction to asc', () {
      final s = OdsDefaultSort.fromJson({'field': 'name'});
      expect(s.direction, 'asc');
    });

    test('isDescending is true for desc', () {
      final s = OdsDefaultSort.fromJson({'field': 'x', 'direction': 'desc'});
      expect(s.isDescending, true);
    });

    test('isDescending is false for asc', () {
      final s = OdsDefaultSort.fromJson({'field': 'x', 'direction': 'asc'});
      expect(s.isDescending, false);
    });

    test('isDescending is false for default', () {
      final s = OdsDefaultSort.fromJson({'field': 'x'});
      expect(s.isDescending, false);
    });
  });

  // =========================================================================
  // Base fields parsed on every component type
  // =========================================================================

  group('base fields on every component type', () {
    test('styleHint is parsed on all types', () {
      for (final json in [
        {'component': 'text', 'content': 'hi', 'styleHint': {'color': 'red'}},
        {
          'component': 'list',
          'dataSource': 'ds',
          'columns': [{'header': 'H', 'field': 'f'}],
          'styleHint': {'density': 'compact'},
        },
        {
          'component': 'form',
          'id': 'f',
          'fields': [{'name': 'x', 'type': 'text'}],
          'styleHint': {'size': 'large'},
        },
        {
          'component': 'button',
          'label': 'Go',
          'onClick': [{'action': 'navigate', 'target': 'p'}],
          'styleHint': {'emphasis': 'primary'},
        },
        {
          'component': 'chart',
          'dataSource': 'ds',
          'labelField': 'x',
          'valueField': 'y',
          'styleHint': {'elevation': 2},
        },
        {
          'component': 'summary',
          'label': 'L',
          'value': 'V',
          'styleHint': {'icon': 'star'},
        },
        {
          'component': 'tabs',
          'tabs': [{'label': 'T', 'content': []}],
          'styleHint': {'align': 'center'},
        },
        {
          'component': 'detail',
          'styleHint': {'variant': 'heading'},
        },
        {
          'component': 'kanban',
          'dataSource': 'ds',
          'statusField': 's',
          'styleHint': {'color': 'blue'},
        },
      ]) {
        final c = OdsComponent.fromJson(json);
        expect(c.styleHint.isEmpty, false,
            reason: '${json['component']} should have non-empty styleHint');
      }
    });

    test('visibleWhen is parsed on all types', () {
      final vw = {'field': 'f', 'form': 'fm', 'equals': 'v'};
      for (final json in [
        {'component': 'text', 'content': 'hi', 'visibleWhen': vw},
        {
          'component': 'list',
          'dataSource': 'ds',
          'columns': [{'header': 'H', 'field': 'f'}],
          'visibleWhen': vw,
        },
        {
          'component': 'form',
          'id': 'f',
          'fields': [{'name': 'x', 'type': 'text'}],
          'visibleWhen': vw,
        },
        {
          'component': 'button',
          'label': 'Go',
          'onClick': [{'action': 'navigate', 'target': 'p'}],
          'visibleWhen': vw,
        },
        {
          'component': 'chart',
          'dataSource': 'ds',
          'labelField': 'x',
          'valueField': 'y',
          'visibleWhen': vw,
        },
        {
          'component': 'summary',
          'label': 'L',
          'value': 'V',
          'visibleWhen': vw,
        },
        {
          'component': 'tabs',
          'tabs': [{'label': 'T', 'content': []}],
          'visibleWhen': vw,
        },
        {
          'component': 'detail',
          'visibleWhen': vw,
        },
        {
          'component': 'kanban',
          'dataSource': 'ds',
          'statusField': 's',
          'visibleWhen': vw,
        },
      ]) {
        final c = OdsComponent.fromJson(json);
        expect(c.visibleWhen, isNotNull,
            reason: '${json['component']} should have visibleWhen');
      }
    });

    test('visible is parsed on all types', () {
      for (final json in [
        {'component': 'text', 'content': 'hi', 'visible': '{x} == "1"'},
        {
          'component': 'list',
          'dataSource': 'ds',
          'columns': [{'header': 'H', 'field': 'f'}],
          'visible': '{x} == "1"',
        },
        {
          'component': 'form',
          'id': 'f',
          'fields': [{'name': 'x', 'type': 'text'}],
          'visible': '{x} == "1"',
        },
        {
          'component': 'button',
          'label': 'Go',
          'onClick': [{'action': 'navigate', 'target': 'p'}],
          'visible': '{x} == "1"',
        },
        {
          'component': 'chart',
          'dataSource': 'ds',
          'labelField': 'x',
          'valueField': 'y',
          'visible': '{x} == "1"',
        },
        {
          'component': 'summary',
          'label': 'L',
          'value': 'V',
          'visible': '{x} == "1"',
        },
        {
          'component': 'tabs',
          'tabs': [{'label': 'T', 'content': []}],
          'visible': '{x} == "1"',
        },
        {
          'component': 'detail',
          'visible': '{x} == "1"',
        },
        {
          'component': 'kanban',
          'dataSource': 'ds',
          'statusField': 's',
          'visible': '{x} == "1"',
        },
      ]) {
        final c = OdsComponent.fromJson(json);
        expect(c.visible, '{x} == "1"',
            reason: '${json['component']} should have visible');
      }
    });

    test('roles is parsed on all types', () {
      final roles = ['admin'];
      for (final json in [
        {'component': 'text', 'content': 'hi', 'roles': roles},
        {
          'component': 'list',
          'dataSource': 'ds',
          'columns': [{'header': 'H', 'field': 'f'}],
          'roles': roles,
        },
        {
          'component': 'form',
          'id': 'f',
          'fields': [{'name': 'x', 'type': 'text'}],
          'roles': roles,
        },
        {
          'component': 'button',
          'label': 'Go',
          'onClick': [{'action': 'navigate', 'target': 'p'}],
          'roles': roles,
        },
        {
          'component': 'chart',
          'dataSource': 'ds',
          'labelField': 'x',
          'valueField': 'y',
          'roles': roles,
        },
        {
          'component': 'summary',
          'label': 'L',
          'value': 'V',
          'roles': roles,
        },
        {
          'component': 'tabs',
          'tabs': [{'label': 'T', 'content': []}],
          'roles': roles,
        },
        {
          'component': 'detail',
          'roles': roles,
        },
        {
          'component': 'kanban',
          'dataSource': 'ds',
          'statusField': 's',
          'roles': roles,
        },
      ]) {
        final c = OdsComponent.fromJson(json);
        expect(c.roles, ['admin'],
            reason: '${json['component']} should have roles');
      }
    });
  });
}
