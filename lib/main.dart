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

enum Currency { eur, tnd }

String currencyLabel(Currency c) => c == Currency.eur ? 'EUR' : 'TND';

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
  final double amount; // ham tutar
  final Currency currency;
  final String payerId; // ödeyen
  final List<String> participantIds; // eşit bölünecek kişiler
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.currency,
    required this.payerId,
    required this.participantIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "description": description,
    "amount": amount,
    "currency": currency.index,
    "payerId": payerId,
    "participantIds": participantIds,
    "createdAt": createdAt.toIso8601String(),
  };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'],
    description: j['description'],
    amount: (j['amount'] as num).toDouble(),
    currency: Currency.values[j['currency'] as int],
    payerId: j['payerId'],
    participantIds: (j['participantIds'] as List).cast<String>(),
    createdAt: DateTime.parse(j['createdAt']),
  );
}

class SettlementEdge {
  final String from; // borçlu
  final String to; // alacaklı
  final double amount;
  final Currency currency;
  const SettlementEdge(this.from, this.to, this.amount, this.currency);
}

// ----------------------------- STATE -----------------------------

class BalanceState {
  final List<Member> members;
  final List<Expense> expenses;
  final bool isLoading;
  final double budgetEur; // grup bütçesi (EUR)
  final double budgetTnd; // grup bütçesi (TND)

  const BalanceState({
    required this.members,
    required this.expenses,
    required this.isLoading,
    required this.budgetEur,
    required this.budgetTnd,
  });

  BalanceState copyWith({
    List<Member>? members,
    List<Expense>? expenses,
    bool? isLoading,
    double? budgetEur,
    double? budgetTnd,
  }) => BalanceState(
    members: members ?? this.members,
    expenses: expenses ?? this.expenses,
    isLoading: isLoading ?? this.isLoading,
    budgetEur: budgetEur ?? this.budgetEur,
    budgetTnd: budgetTnd ?? this.budgetTnd,
  );

  Map<String, dynamic> toJson() => {
    'members': members.map((m) => m.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'budgetEur': budgetEur,
    'budgetTnd': budgetTnd,
  };

  factory BalanceState.fromJson(Map<String, dynamic> j) => BalanceState(
    members: (j['members'] as List)
        .map((e) => Member.fromJson(e))
        .toList(growable: false),
    expenses: (j['expenses'] as List)
        .map((e) => Expense.fromJson(e))
        .toList(growable: false),
    isLoading: false,
    budgetEur: (j['budgetEur'] as num?)?.toDouble() ?? 0.0,
    budgetTnd: (j['budgetTnd'] as num?)?.toDouble() ?? 0.0,
  );
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
          budgetEur: 0.0,
          budgetTnd: 0.0,
        ),
      ) {
    _load();
  }

  static const _kKey = 'balance_data_v2';

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    final data = jsonEncode(state.toJson());
    await sp.setString(_kKey, data);
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) {
      // v1'den taşıma: önceki anahtar varsa onu da okumayı dene
      final legacy = sp.getString('balance_data_v1');
      if (legacy != null) {
        try {
          final j = jsonDecode(legacy) as Map<String, dynamic>;
          final members = (j['members'] as List)
              .map((e) => Member.fromJson(e))
              .toList(growable: false);
          final expenses = (j['expenses'] as List)
              .map((e) => Expense.fromJson(e))
              .toList(growable: false);
          emit(
            BalanceState(
              members: members,
              expenses: expenses,
              isLoading: false,
              budgetEur: 0.0,
              budgetTnd: 0.0,
            ),
          );
          await _save();
          return;
        } catch (_) {}
      }
      emit(state.copyWith(isLoading: false));
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      emit(BalanceState.fromJson(j));
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
    required Currency currency,
    required String payerId,
    required List<String> participantIds,
  }) {
    if (amount <= 0) return;
    if (participantIds.isEmpty) return;

    final expense = Expense(
      id: UniqueKey().toString(),
      description: description.trim(),
      amount: amount,
      currency: currency,
      payerId: payerId,
      participantIds: participantIds,
      createdAt: DateTime.now(),
    );

    final expenses = [...state.expenses, expense];
    emit(state.copyWith(expenses: expenses));
    _save();
  }

  void deleteExpense(String id) {
    final expenses = state.expenses.where((e) => e.id != id).toList();
    emit(state.copyWith(expenses: expenses));
    _save();
  }

  void setBudgets({double? eur, double? tnd}) {
    emit(
      state.copyWith(
        budgetEur: eur ?? state.budgetEur,
        budgetTnd: tnd ?? state.budgetTnd,
      ),
    );
    _save();
  }

  // Kişi başına netler (para birimi bazında ayrı)
  Map<String, double> netByMember(Currency c) {
    final map = <String, double>{};
    for (final m in state.members) {
      map[m.id] = 0.0;
    }
    for (final e in state.expenses.where((e) => e.currency == c)) {
      // ödeyen alacaklı (+)
      map[e.payerId] = (map[e.payerId] ?? 0) + e.amount;
      // katılımcılar borçlu (- pay)
      final share = e.amount / e.participantIds.length;
      for (final pid in e.participantIds) {
        map[pid] = (map[pid] ?? 0) - share;
      }
    }
    map.updateAll((key, value) => double.parse(value.toStringAsFixed(2)));
    return map;
  }

  double totalByCurrency(Currency c) => state.expenses
      .where((e) => e.currency == c)
      .fold(0.0, (sum, e) => sum + e.amount);

  double remainingByCurrency(Currency c) {
    final total = totalByCurrency(c);
    final budget = c == Currency.eur ? state.budgetEur : state.budgetTnd;
    return double.parse((budget - total).toStringAsFixed(2));
  }

  // Basit borç kapatma algoritması (greedy) — para birimi bazında
  List<SettlementEdge> settlements(Currency c) {
    final net = netByMember(c);
    final creditors = <String>[];
    final debtors = <String>[];

    net.forEach((id, amount) {
      if (amount > 0) creditors.add(id);
      if (amount < 0) debtors.add(id);
    });

    final cred = [
      for (final id in creditors) [id, net[id]!.abs()],
    ]..sort((a, b) => (b[1] as double).compareTo(a[1] as double));

    final debt = [
      for (final id in debtors) [id, net[id]!.abs()],
    ]..sort((a, b) => (b[1] as double).compareTo(a[1] as double));

    final res = <SettlementEdge>[];
    int i = 0, j = 0;
    while (i < debt.length && j < cred.length) {
      final dId = debt[i][0] as String;
      final cId = cred[j][0] as String;
      final dAmt = debt[i][1] as double;
      final cAmt = cred[j][1] as double;
      final pay = dAmt < cAmt ? dAmt : cAmt;

      if (pay > 0.0) {
        res.add(
          SettlementEdge(dId, cId, double.parse(pay.toStringAsFixed(2)), c),
        );
      }
      debt[i][1] = dAmt - pay;
      cred[j][1] = cAmt - pay;
      if ((debt[i][1] as double) <= 0.0001) i++;
      if ((cred[j][1] as double) <= 0.0001) j++;
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
        title: const Text('Bakiye — EUR & TND'),
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
                    '${currencyLabel(e.currency)} ${(e.amount).toStringAsFixed(2)} — ödeyen: $payer\n'
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
        if (state.isLoading)
          return const Center(child: CircularProgressIndicator());
        final cubit = context.read<BalanceCubit>();
        final eurNet = cubit.netByMember(Currency.eur);
        final tndNet = cubit.netByMember(Currency.tnd);

        final totalEUR = cubit.totalByCurrency(Currency.eur);
        final totalTND = cubit.totalByCurrency(Currency.tnd);
        final leftEUR = cubit.remainingByCurrency(Currency.eur);
        final leftTND = cubit.remainingByCurrency(Currency.tnd);

        // Özet kartları
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: 8,
                children: [
                  Column(
                    children: [
                      _totalCard(
                        'Bütçe EUR',
                        '€ ${state.budgetEur.toStringAsFixed(2)}',
                      ),
                      _totalCard(
                        'Harcanan EUR',
                        '€ ${totalEUR.toStringAsFixed(2)}',
                      ),
                      _totalCard(
                        'Kalan EUR',
                        '€ ${leftEUR.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      _totalCard(
                        'Bütçe TND',
                        'د.ت ${state.budgetTnd.toStringAsFixed(2)}',
                      ),
                      _totalCard(
                        'Harcanan TND',
                        'د.ت ${totalTND.toStringAsFixed(2)}',
                      ),
                      _totalCard(
                        'Kalan TND',
                        'د.ت ${leftTND.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Kişi Bazında Netler',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final m in state.members)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(m.name),
                        subtitle: Text(
                          'EUR: ${eurNet[m.id]?.toStringAsFixed(2) ?? '0.00'}  |  '
                          'TND: ${tndNet[m.id]?.toStringAsFixed(2) ?? '0.00'}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hızlı Uzlaştırma Önerileri (EUR)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _settlementList(
                context,
                cubit.settlements(Currency.eur),
                state.members,
              ),
              const SizedBox(height: 16),
              Text(
                'Hızlı Uzlaştırma Önerileri (TND)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _settlementList(
                context,
                cubit.settlements(Currency.tnd),
                state.members,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _totalCard(String title, String value) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settlementList(
    BuildContext context,
    List<SettlementEdge> edges,
    List<Member> members,
  ) {
    if (edges.isEmpty) {
      return const Card(child: ListTile(title: Text('Uzlaştırma gerekmiyor.')));
    }
    final names = {for (final m in members) m.id: m.name};
    return Card(
      child: Column(
        children: [
          for (final e in edges)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text('${names[e.from]} → ${names[e.to]}'),
              subtitle: Text(
                '${currencyLabel(e.currency)} ${e.amount.toStringAsFixed(2)} ödesin',
              ),
            ),
        ],
      ),
    );
  }
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
                          final rename = await showDialog<String>(
                            context: context,
                            builder: (_) => const _RenameDialogLauncher(),
                          );
                          if (rename != null && rename.trim().isNotEmpty) {
                            context.read<BalanceCubit>().renameMember(
                              m.id,
                              rename.trim(),
                            );
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
  Currency _currency = Currency.tnd;
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
                  Row(
                    children: [
                      const Text('Para birimi:'),
                      const SizedBox(width: 12),
                      DropdownButton<Currency>(
                        value: _currency,
                        items: const [
                          DropdownMenuItem(
                            value: Currency.tnd,
                            child: Text('TND'),
                          ),
                          DropdownMenuItem(
                            value: Currency.eur,
                            child: Text('EUR'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _currency = v ?? Currency.tnd),
                      ),
                    ],
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
                  currency: _currency,
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
  final _eur = TextEditingController();
  final _tnd = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<BalanceCubit>().state;
    _eur.text = s.budgetEur == 0 ? '' : s.budgetEur.toStringAsFixed(2);
    _tnd.text = s.budgetTnd == 0 ? '' : s.budgetTnd.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Grup Bütçesi (EUR & TND)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _eur,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'EUR Bütçe'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tnd,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'TND Bütçe'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            final eur = double.tryParse(_eur.text.replaceAll(',', '.')) ?? 0.0;
            final tnd = double.tryParse(_tnd.text.replaceAll(',', '.')) ?? 0.0;
            context.read<BalanceCubit>().setBudgets(eur: eur, tnd: tnd);
            Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
