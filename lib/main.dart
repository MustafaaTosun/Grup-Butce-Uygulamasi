// lib/main.dart
// Tek dosyalık, Cubit tabanlı basit "bakiye/paylaşım" uygulaması
// Özellikler (güncel):
// - 3 kişi varsayılan (düzenlenebilir)
// - Harcama ekle (açıklama, tutar, para birimi [EUR/TND], ödeyen, katılanlar)
// - Eşit bölüşüm (custom split yok — istersen ekleriz)
// - Grup bütçesi: EUR ve TND için ayrı bütçe girişi, toplam harcamadan düşülerek kalan gösterilir
// - Kişi bazında net bakiye: (ödediği - payı) — ayrı ayrı EUR/TND
// - Basit “kim kime borçlu” listesi (para birimi bazında ayrı hesaplanır)
// - Yerel kalıcı kayıt (SharedPreferences JSON)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------- MODELLER -----------------------------

// ─── PARA BİRİMLERİ ────────────────────────────────────────────────────────

class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final String flag;
  const CurrencyInfo(this.code, this.symbol, this.name, this.flag);
  String get label => '$flag  $code — $name';
  String format(double v) => '$symbol ${v.toStringAsFixed(2)}';
  @override bool operator ==(Object o) => o is CurrencyInfo && o.code == code;
  @override int get hashCode => code.hashCode;
}

const kCurrencies = [
  CurrencyInfo('TND', 'د.ت', 'Tunus Dinarı', '🇹🇳'),
  CurrencyInfo('EUR', '€',   'Euro',           '🇪🇺'),
  CurrencyInfo('USD', r'$',  'ABD Doları',     '🇺🇸'),
  CurrencyInfo('TRY', '₺',   'Türk Lirası',    '🇹🇷'),
  CurrencyInfo('GBP', '£',   'İngiliz Sterlini','🇬🇧'),
  CurrencyInfo('CHF', 'Fr',  'İsviçre Frangı', '🇨🇭'),
  CurrencyInfo('JPY', '¥',   'Japon Yeni',     '🇯🇵'),
  CurrencyInfo('CAD', 'C\$', 'Kanada Doları',  '🇨🇦'),
  CurrencyInfo('AUD', 'A\$', 'Avustralya Doları','🇦🇺'),
  CurrencyInfo('SAR', '﷼',  'Suudi Riyali',   '🇸🇦'),
  CurrencyInfo('AED', 'د.إ', 'BAE Dirhemi',    '🇦🇪'),
  CurrencyInfo('EGP', 'E£',  'Mısır Poundu',   '🇪🇬'),
  CurrencyInfo('MAD', 'د.م.','Fas Dirhemi',    '🇲🇦'),
  CurrencyInfo('DZD', 'دج',  'Cezayir Dinarı', '🇩🇿'),
  CurrencyInfo('LYD', 'ل.د', 'Libya Dinarı',   '🇱🇾'),
  CurrencyInfo('CNY', '¥',   'Çin Yuanı',      '🇨🇳'),
  CurrencyInfo('INR', '₹',   'Hindistan Rupisi','🇮🇳'),
  CurrencyInfo('RUB', '₽',   'Rus Rublesi',    '🇷🇺'),
  CurrencyInfo('BRL', 'R\$', 'Brezilya Reali', '🇧🇷'),
  CurrencyInfo('MXN', r'$',  'Meksika Pesosu', '🇲🇽'),
  CurrencyInfo('KWD', 'د.ك', 'Kuveyt Dinarı',  '🇰🇼'),
  CurrencyInfo('QAR', 'ر.ق', 'Katar Riyali',   '🇶🇦'),
  CurrencyInfo('NOK', 'kr',  'Norveç Kronu',   '🇳🇴'),
  CurrencyInfo('SEK', 'kr',  'İsveç Kronu',    '🇸🇪'),
  CurrencyInfo('DKK', 'kr',  'Danimarka Kronu','🇩🇰'),
  CurrencyInfo('PLN', 'zł',  'Polonya Zlotısı','🇵🇱'),
  CurrencyInfo('CZK', 'Kč',  'Çek Kronası',    '🇨🇿'),
  CurrencyInfo('HUF', 'Ft',  'Macar Forinti',  '🇭🇺'),
  CurrencyInfo('RON', 'lei', 'Romen Leyi',     '🇷🇴'),
  CurrencyInfo('BGN', 'лв',  'Bulgar Levası',  '🇧🇬'),
];

CurrencyInfo currencyByCode(String code) =>
    kCurrencies.firstWhere((c) => c.code == code, orElse: () => kCurrencies[0]);

class Member {
  final String id;
  final String name;
  const Member({required this.id, required this.name});

  Member copyWith({String? id, String? name}) =>
      Member(id: id ?? this.id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {"id": id, "name": name};
  factory Member.fromJson(Map<String, dynamic> j) =>
      Member(id: j['id'], name: j['name']);
}

class Expense {
  final String id;
  final String description;
  final double amount;
  final String currencyCode;
  final String payerId;
  final List<String> participantIds;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.currencyCode,
    required this.payerId,
    required this.participantIds,
    required this.createdAt,
  });

  CurrencyInfo get currencyInfo => currencyByCode(currencyCode);

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
    'currencyCode': currencyCode,
    'payerId': payerId,
    'participantIds': participantIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Expense.fromJson(Map<String, dynamic> j) {
    String code;
    if (j.containsKey('currencyCode')) {
      code = j['currencyCode'] as String;
    } else {
      // Eski format: 0=EUR, 1=TND
      code = (j['currency'] as int? ?? 0) == 0 ? 'EUR' : 'TND';
    }
    return Expense(
      id: j['id'],
      description: j['description'],
      amount: (j['amount'] as num).toDouble(),
      currencyCode: code,
      payerId: j['payerId'],
      participantIds: (j['participantIds'] as List).cast<String>(),
      createdAt: DateTime.parse(j['createdAt']),
    );
  }
}

class SettlementEdge {
  final String from;
  final String to;
  final double amount;
  final String currencyCode;
  const SettlementEdge(this.from, this.to, this.amount, this.currencyCode);
  CurrencyInfo get currencyInfo => currencyByCode(currencyCode);
}

// ----------------------------- STATE -----------------------------

class BalanceState {
  final List<Member> members;
  final List<Expense> expenses;
  final bool isLoading;
  final Map<String, double> budgets; // currencyCode -> bütçe

  const BalanceState({
    required this.members,
    required this.expenses,
    required this.isLoading,
    required this.budgets,
  });

  BalanceState copyWith({
    List<Member>? members,
    List<Expense>? expenses,
    bool? isLoading,
    Map<String, double>? budgets,
  }) => BalanceState(
    members: members ?? this.members,
    expenses: expenses ?? this.expenses,
    isLoading: isLoading ?? this.isLoading,
    budgets: budgets ?? this.budgets,
  );

  Map<String, dynamic> toJson() => {
    'members': members.map((m) => m.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'budgets': budgets,
  };

  factory BalanceState.fromJson(Map<String, dynamic> j) {
    Map<String, double> budgets;
    if (j.containsKey('budgets')) {
      budgets = (j['budgets'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    } else {
      // Eski v1/v2 verisi taşıma
      budgets = {};
      final eur = (j['budgetEur'] as num?)?.toDouble() ?? 0.0;
      final tnd = (j['budgetTnd'] as num?)?.toDouble() ?? 0.0;
      if (eur > 0) budgets['EUR'] = eur;
      if (tnd > 0) budgets['TND'] = tnd;
    }
    return BalanceState(
      members: (j['members'] as List).map((e) => Member.fromJson(e)).toList(),
      expenses: (j['expenses'] as List).map((e) => Expense.fromJson(e)).toList(),
      isLoading: false,
      budgets: budgets,
    );
  }
}

// ----------------------------- CUBIT -----------------------------

class BalanceCubit extends Cubit<BalanceState> {
  BalanceCubit()
    : super(
        const BalanceState(
          members: [
            Member(id: 'm1', name: 'Kişi 1'),
            Member(id: 'm2', name: 'Kişi 2'),
            Member(id: 'm3', name: 'Kişi 3'),
          ],
          expenses: [],
          isLoading: true,
          budgets: {},
        ),
      ) {
    _load();
  }

  static const _kKey = 'balance_data_v3';

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    final data = jsonEncode(state.toJson());
    await sp.setString(_kKey, data);
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey)
        ?? sp.getString('balance_data_v2')
        ?? sp.getString('balance_data_v1');
    if (raw == null) { emit(state.copyWith(isLoading: false)); return; }
    try {
      emit(BalanceState.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (_) {
      emit(state.copyWith(isLoading: false));
    }
  }

  void addMember(String name) {
    if (name.trim().isEmpty) return;
    final newMember = Member(id: UniqueKey().toString(), name: name.trim());
    final members = [...state.members, newMember];
    emit(state.copyWith(members: members));
    _save();
  }

  void renameMember(String id, String newName) {
    final members = state.members
        .map((m) => m.id == id ? m.copyWith(name: newName) : m)
        .toList();
    emit(state.copyWith(members: members));
    _save();
  }

  void removeMember(String id) {
    final members = state.members.where((m) => m.id != id).toList();
    final expenses = state.expenses
        .where((e) => e.payerId != id && !e.participantIds.contains(id))
        .toList();
    emit(state.copyWith(members: members, expenses: expenses));
    _save();
  }

  void addExpense({
    required String description,
    required double amount,
    required String currencyCode,
    required String payerId,
    required List<String> participantIds,
  }) {
    if (amount <= 0 || participantIds.isEmpty) return;
    emit(state.copyWith(expenses: [
      ...state.expenses,
      Expense(
        id: UniqueKey().toString(),
        description: description.trim(),
        amount: amount,
        currencyCode: currencyCode,
        payerId: payerId,
        participantIds: participantIds,
        createdAt: DateTime.now(),
      ),
    ]));
    _save();
  }

  void deleteExpense(String id) {
    emit(state.copyWith(expenses: state.expenses.where((e) => e.id != id).toList()));
    _save();
  }

  void setBudget(String currencyCode, double amount) {
    final b = Map<String, double>.from(state.budgets);
    if (amount <= 0) b.remove(currencyCode); else b[currencyCode] = amount;
    emit(state.copyWith(budgets: b));
    _save();
  }

  Set<String> get activeCurrencies {
    final s = state.expenses.map((e) => e.currencyCode).toSet();
    s.addAll(state.budgets.keys);
    return s;
  }

  Map<String, double> netByMember(String currencyCode) {
    final map = <String, double>{for (final m in state.members) m.id: 0.0};
    for (final e in state.expenses.where((e) => e.currencyCode == currencyCode)) {
      map[e.payerId] = (map[e.payerId] ?? 0) + e.amount;
      final share = e.amount / e.participantIds.length;
      for (final pid in e.participantIds) {
        map[pid] = (map[pid] ?? 0) - share;
      }
    }
    return map.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2))));
  }

  double totalByCurrency(String code) =>
      state.expenses.where((e) => e.currencyCode == code).fold(0.0, (s, e) => s + e.amount);

  double remainingByCurrency(String code) =>
      double.parse(((state.budgets[code] ?? 0.0) - totalByCurrency(code)).toStringAsFixed(2));

  List<SettlementEdge> settlements(String currencyCode) {
    final net = netByMember(currencyCode);
    final cred = [for (final e in net.entries) if (e.value > 0.005) [e.key, e.value]];
    final debt = [for (final e in net.entries) if (e.value < -0.005) [e.key, e.value.abs()]];
    cred.sort((a, b) => (b[1] as double).compareTo(a[1] as double));
    debt.sort((a, b) => (b[1] as double).compareTo(a[1] as double));
    final res = <SettlementEdge>[];
    int i = 0, j = 0;
    while (i < debt.length && j < cred.length) {
      double dAmt = debt[i][1] as double;
      double cAmt = cred[j][1] as double;
      final pay = dAmt < cAmt ? dAmt : cAmt;
      if (pay > 0) res.add(SettlementEdge(debt[i][0] as String, cred[j][0] as String, double.parse(pay.toStringAsFixed(2)), currencyCode));
      debt[i][1] = dAmt - pay;
      cred[j][1] = cAmt - pay;
      if ((debt[i][1] as double) <= 0.001) i++;
      if ((cred[j][1] as double) <= 0.001) j++;
    }
    return res;
  }
}

// ----------------------------- UYGULAMA -----------------------------

void main() {
  runApp(const BakiyeApp());
}

class BakiyeApp extends StatelessWidget {
  const BakiyeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tunus Bakiye',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: BlocProvider(
        create: (_) => BalanceCubit(),
        child: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bakiye'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Harcama'),
            Tab(text: 'Bakiyeler'),
            Tab(text: 'Kişiler'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bütçe Ayarla',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => showDialog(
              context: context,
              builder: (dialogContext) => BlocProvider.value(
                value: context.read<BalanceCubit>(),
                child: const SetBudgetDialog(),
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [ExpensesTab(), BalancesTab(), MembersTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (dialogContext) => BlocProvider.value(
            value: context.read<BalanceCubit>(),
            child: const AddExpenseDialog(),
          ),
        ),
        label: const Text('Harcama Ekle'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

// ----------------------------- TABS & UI -----------------------------

class ExpensesTab extends StatelessWidget {
  const ExpensesTab({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceCubit, BalanceState>(
      builder: (context, state) {
        if (state.isLoading)
          return const Center(child: CircularProgressIndicator());
        if (state.expenses.isEmpty) {
          return const Center(
            child: Text('Henüz harcama yok. Sağ alttan ekleyebilirsin.'),
          );
        }
        final membersById = {for (final m in state.members) m.id: m};
        final items = state.expenses.reversed.toList();
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final e = items[i];
            final payer = membersById[e.payerId]?.name ?? '??';
            return Dismissible(
              key: ValueKey(e.id),
              background: Container(color: Colors.redAccent),
              onDismissed: (_) =>
                  context.read<BalanceCubit>().deleteExpense(e.id),
              child: Card(
                child: ListTile(
                  title: Text(
                    e.description.isEmpty ? 'Harcama' : e.description,
                  ),
                  subtitle: Text(
                    '${e.currencyInfo.flag} ${e.currencyInfo.code} ${e.amount.toStringAsFixed(2)} — ödeyen: $payer\n'
                    'katılan: ${e.participantIds.map((id) => membersById[id]?.name ?? '?').join(', ')}',
                  ),
                  trailing: Text(
                    '${e.createdAt.day.toString().padLeft(2, '0')}.${e.createdAt.month.toString().padLeft(2, '0')}.${e.createdAt.year}',
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class BalancesTab extends StatelessWidget {
  const BalancesTab({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceCubit, BalanceState>(
      builder: (context, state) {
        if (state.isLoading) return const Center(child: CircularProgressIndicator());
        final cubit = context.read<BalanceCubit>();
        final codes = cubit.activeCurrencies.toList();
        if (codes.isEmpty) {
          return const Center(child: Text('Henüz harcama veya bütçe yok.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: codes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final code = codes[idx];
            final info = currencyByCode(code);
            final total = cubit.totalByCurrency(code);
            final budget = state.budgets[code] ?? 0.0;
            final remaining = cubit.remainingByCurrency(code);
            final net = cubit.netByMember(code);
            final settlements = cubit.settlements(code);
            final names = {for (final m in state.members) m.id: m.name};
            return Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(info.flag, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text('${info.code} — ${info.name}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _Stat('Bütçe', budget > 0 ? info.format(budget) : '—'),
                      _Stat('Harcanan', info.format(total)),
                      if (budget > 0)
                        _Stat('Kalan', info.format(remaining),
                            color: remaining < 0 ? Colors.red : Colors.green),
                    ]),
                    const Divider(),
                    Text('Kişi Bazında Netler', style: Theme.of(context).textTheme.labelLarge),
                    for (final m in state.members)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person, size: 18),
                        title: Text(m.name),
                        trailing: Text(
                          info.format(net[m.id] ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (net[m.id] ?? 0) >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    if (settlements.isNotEmpty) ...[
                      const Divider(),
                      Text('Uzlaştırma Önerileri', style: Theme.of(context).textTheme.labelLarge),
                      for (final e in settlements)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.swap_horiz, size: 18),
                          title: Text('${names[e.from]} → ${names[e.to]}'),
                          trailing: Text(info.format(e.amount),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: Theme.of(context).textTheme.labelSmall),
    Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
  ]);
}

class MembersTab extends StatefulWidget {
  const MembersTab({super.key});
  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceCubit, BalanceState>(
      builder: (context, state) {
        if (state.isLoading)
          return const Center(child: CircularProgressIndicator());
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Yeni kişi adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      context.read<BalanceCubit>().addMember(_ctrl.text);
                      _ctrl.clear();
                    },
                    child: const Text('Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: state.members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = state.members[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(m.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              context.read<BalanceCubit>().removeMember(m.id),
                        ),
                        onTap: () async {
                          final cubit = context.read<BalanceCubit>();
                          final rename = await showDialog<String>(
                            context: context,
                            builder: (_) => const _RenameDialogLauncher(),
                          );
                          if (rename != null && rename.trim().isNotEmpty) {
                            cubit.renameMember(m.id, rename.trim());
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RenameDialogLauncher extends StatelessWidget {
  const _RenameDialogLauncher();
  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: context.read<BalanceCubit>(),
      child: _RenameDialog(old: ''),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String old;
  const _RenameDialog({required this.old});
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _c;
  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.old);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kişi ismi düzenle'),
      content: TextField(controller: _c, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});
  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  String _currencyCode = 'TND';
  String? _payerId;
  final Set<String> _participants = {};

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceCubit, BalanceState>(
      builder: (context, state) {
        final members = state.members;
        _payerId ??= members.isNotEmpty ? members.first.id : null;
        if (_participants.isEmpty && members.isNotEmpty) {
          _participants.addAll(members.map((m) => m.id));
        }

        return AlertDialog(
          title: const Text('Harcama Ekle'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _desc,
                    decoration: const InputDecoration(labelText: 'Açıklama'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Tutar'),
                    validator: (v) {
                      final x = double.tryParse(v ?? '');
                      if (x == null || x <= 0) return 'Geçerli bir tutar girin';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final code = await showDialog<String>(
                        context: context,
                        builder: (_) => _CurrencyPickerDialog(selectedCode: _currencyCode),
                      );
                      if (code != null) setState(() => _currencyCode = code);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Para Birimi',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(() {
                            final c = currencyByCode(_currencyCode);
                            return '${c.flag}  ${c.code} — ${c.name}';
                          }()),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Ödeyen:'),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _payerId,
                        items: [
                          for (final m in members)
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: (v) => setState(() => _payerId = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Katılanlar (${_participants.length}/${members.length})',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in members)
                        FilterChip(
                          label: Text(m.name),
                          selected: _participants.contains(m.id),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _participants.add(m.id);
                            } else {
                              _participants.remove(m.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                if (_payerId == null) return;
                if (_participants.isEmpty) return;

                context.read<BalanceCubit>().addExpense(
                  description: _desc.text,
                  amount: double.parse(_amount.text.replaceAll(',', '.')),
                  currencyCode: _currencyCode,
                  payerId: _payerId!,
                  participantIds: _participants.toList(),
                );
                Navigator.pop(context);
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }
}

class SetBudgetDialog extends StatefulWidget {
  const SetBudgetDialog({super.key});
  @override
  State<SetBudgetDialog> createState() => _SetBudgetDialogState();
}

class _SetBudgetDialogState extends State<SetBudgetDialog> {
  String _selectedCode = 'TND';
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalanceCubit, BalanceState>(
      builder: (context, state) {
        final budgets = state.budgets;
        return AlertDialog(
          title: const Text('Grup Bütçesi'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (budgets.isNotEmpty) ...[
                  Text('Mevcut Bütçeler', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  for (final entry in budgets.entries)
                    ListTile(
                      dense: true,
                      leading: Text(currencyByCode(entry.key).flag,
                          style: const TextStyle(fontSize: 20)),
                      title: Text('${entry.key}: ${currencyByCode(entry.key).format(entry.value)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => context.read<BalanceCubit>().setBudget(entry.key, 0),
                      ),
                    ),
                  const Divider(),
                ],
                Text('Yeni Bütçe Ekle', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final code = await showDialog<String>(
                      context: context,
                      builder: (_) => _CurrencyPickerDialog(selectedCode: _selectedCode),
                    );
                    if (code != null) setState(() => _selectedCode = code);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Para Birimi',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(() {
                          final c = currencyByCode(_selectedCode);
                          return '${c.flag}  ${c.code} — ${c.name}';
                        }()),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Bütçe Tutarı (${currencyByCode(_selectedCode).symbol})',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
                if (amount > 0) {
                  context.read<BalanceCubit>().setBudget(_selectedCode, amount);
                  _amountCtrl.clear();
                  setState(() {});
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }
}

class _CurrencyPickerDialog extends StatefulWidget {
  final String selectedCode;
  const _CurrencyPickerDialog({required this.selectedCode});
  @override
  State<_CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends State<_CurrencyPickerDialog> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = kCurrencies
        .where((c) =>
            c.code.toLowerCase().contains(_query.toLowerCase()) ||
            c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('Para Birimi Seç'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ara...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(c.name),
                    trailing: c.code == widget.selectedCode
                        ? const Icon(Icons.check_circle, color: Colors.teal)
                        : null,
                    onTap: () => Navigator.pop(context, c.code),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
