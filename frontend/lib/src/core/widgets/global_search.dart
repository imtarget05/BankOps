import 'package:flutter/material.dart';

import '../../data/models/dtos.dart';
import '../../data/repositories/bankops_repository.dart';

/// Một kết quả tìm kiếm — bấm vào nhảy tới tab tương ứng trong AppShell.
class SearchHit {
  const SearchHit({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tabIndex,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int tabIndex;
}

/// Mở dialog tìm kiếm toàn cục (nút kính lúp hoặc `Ctrl+K`).
/// Trả về tab index cần chuyển tới, `null` nếu người dùng đóng dialog.
Future<int?> showGlobalSearch(BuildContext context, BankOpsRepository repo) {
  return showDialog<int>(
    context: context,
    builder: (_) => _GlobalSearchDialog(repo: repo),
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({required this.repo});

  final BankOpsRepository repo;

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  Future<_SearchIndex>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _buildIndex(widget.repo);
  }

  static Future<_SearchIndex> _buildIndex(BankOpsRepository repo) async {
    final results = await Future.wait([
      repo.getApprovalInbox(),
      repo.getStockRequests(),
      repo.getCashRequests(),
      repo.getItems(),
      repo.getLocations(),
      repo.getCashboxes(),
    ]);
    return _SearchIndex(
      inbox: results[0] as List<ApprovalItem>,
      stockRequests: results[1] as List<StockRequest>,
      cashRequests: results[2] as List<CashRequest>,
      items: results[3] as List<InventoryItem>,
      locations: results[4] as List<InventoryLocation>,
      cashboxes: results[5] as List<Cashbox>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('global-search-input'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm phiếu, vật tư, kho, quỹ…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<_SearchIndex>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Không tải được dữ liệu tìm kiếm: '
                            '${snapshot.error}'),
                      );
                    }
                    final hits = snapshot.data!.search(_query);
                    if (_query.isEmpty) return _quickLinks(context);
                    if (hits.isEmpty) return _emptyResult();
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: hits.length,
                      itemBuilder: (context, i) {
                        final hit = hits[i];
                        return ListTile(
                          key: Key('global-search-hit-$i'),
                          dense: true,
                          leading: Icon(hit.icon, size: 20),
                          title: Text(hit.title),
                          subtitle: Text(
                            hit.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(hit.tabIndex),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyResult() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_outlined, size: 40),
          SizedBox(height: 8),
          Text('Không tìm thấy kết quả phù hợp'),
          SizedBox(height: 4),
          Text(
            'Thử mã phiếu (vd: sr-0001), SKU (vd: TRA-DEN-SO9) hoặc tên kho.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Chưa gõ gì: hiện lối tắt tới các màn chính.
  Widget _quickLinks(BuildContext context) {
    const links = [
      (Icons.fact_check_outlined, 'Hộp thư duyệt', 4),
      (Icons.receipt_long_outlined, 'Yêu cầu', 3),
      (Icons.inventory_2_outlined, 'Kho', 1),
      (Icons.savings_outlined, 'Quỹ', 2),
      (Icons.hub_outlined, 'Tích hợp', 5),
      (Icons.insert_chart_outlined, 'Báo cáo', 7),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final link in links)
          ActionChip(
            key: Key('global-search-quick-${link.$3}'),
            avatar: Icon(link.$1, size: 18),
            label: Text(link.$2),
            onPressed: () => Navigator.of(context).pop(link.$3),
          ),
      ],
    );
  }
}

class _SearchIndex {
  const _SearchIndex({
    required this.inbox,
    required this.stockRequests,
    required this.cashRequests,
    required this.items,
    required this.locations,
    required this.cashboxes,
  });

  final List<ApprovalItem> inbox;
  final List<StockRequest> stockRequests;
  final List<CashRequest> cashRequests;
  final List<InventoryItem> items;
  final List<InventoryLocation> locations;
  final List<Cashbox> cashboxes;

  static const _perGroup = 5;

  /// Lọc theo query trên mọi nhóm, mỗi nhóm tối đa [_perGroup] kết quả.
  List<SearchHit> search(String query) {
    if (query.isEmpty) return const [];
    final hits = <SearchHit>[];
    for (final item in inbox) {
      if (_match([item.id, item.maker, item.detail, item.impact], query)) {
        hits.add(SearchHit(
          title: 'Chờ duyệt: ${item.id}',
          subtitle: '${item.maker} · ${item.impact}',
          icon: Icons.fact_check_outlined,
          tabIndex: 4,
        ));
      }
      if (hits.length >= _perGroup) break;
    }
    var count = 0;
    for (final r in stockRequests) {
      if (_match([r.id, r.reason, r.createdByName], query)) {
        hits.add(SearchHit(
          title: 'Phiếu kho: ${r.id} [${r.status.name}]',
          subtitle: r.reason.isEmpty ? r.createdByName : r.reason,
          icon: Icons.receipt_long_outlined,
          tabIndex: 3,
        ));
        if (++count >= _perGroup) break;
      }
    }
    count = 0;
    for (final r in cashRequests) {
      if (_match([r.id, r.reason, r.createdByName, r.amount], query)) {
        hits.add(SearchHit(
          title: 'Phiếu quỹ: ${r.id} [${r.status.name}]',
          subtitle: '${r.amount} ${r.currency} · ${r.createdByName}',
          icon: Icons.savings_outlined,
          tabIndex: 3,
        ));
        if (++count >= _perGroup) break;
      }
    }
    count = 0;
    for (final item in items) {
      if (_match([item.sku, item.name, item.unit], query)) {
        hits.add(SearchHit(
          title: '${item.sku} — ${item.name}',
          subtitle: 'Vật tư · Đơn vị: ${item.unit}',
          icon: Icons.inventory_2_outlined,
          tabIndex: 1,
        ));
        if (++count >= _perGroup) break;
      }
    }
    count = 0;
    for (final loc in locations) {
      if (_match([loc.code, loc.name], query)) {
        hits.add(SearchHit(
          title: '${loc.code} — ${loc.name}',
          subtitle: 'Kho / địa điểm',
          icon: Icons.warehouse_outlined,
          tabIndex: 1,
        ));
        if (++count >= _perGroup) break;
      }
    }
    count = 0;
    for (final box in cashboxes) {
      if (_match([box.code, box.name], query)) {
        hits.add(SearchHit(
          title: '${box.code} — ${box.name}',
          subtitle: 'Quỹ mô phỏng · Số dư đầu: ${box.openingBalance}',
          icon: Icons.account_balance_wallet_outlined,
          tabIndex: 2,
        ));
        if (++count >= _perGroup) break;
      }
    }
    return hits;
  }

  bool _match(List<Object?> fields, String query) {
    for (final f in fields) {
      if (f != null && f.toString().toLowerCase().contains(query)) return true;
    }
    return false;
  }
}
