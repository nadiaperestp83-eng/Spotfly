import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/ui/widgets/search_related_widgets.dart';

import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreenBN extends StatelessWidget {
  const SearchResultScreenBN({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchResultScreenController controller =
        Get.find<SearchResultScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 80.0;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          children: [
            _buildHeader(context, controller),
            Expanded(
              child: Obx(() {
                if (controller.isResultContentFetced.isTrue &&
                    controller.railItems.isEmpty) {
                  return _buildEmptyState(context, controller);
                } else if (controller.isResultContentFetced.isTrue) {
                  return _buildContent(context, controller);
                } else {
                  return const Center(child: LoadingIndicator());
                }
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SearchResultScreenController c) {
    return Row(
      children: [
        SizedBox(
          width: 55,
          child: Center(
            child: IconButton(
              onPressed: () => Get.nestedKey(ScreenNavigationSetup.id)!
                  .currentState!
                  .pop(),
              icon: const Icon(Icons.arrow_back_ios_new),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "searchRes".tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Obx(
                () => Text(
                  "${"for1".tr} \"${c.queryString.value}\"",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, SearchResultScreenController c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "nomatch".tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text("'${c.queryString.value}'"),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SearchResultScreenController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 15.0, top: 10),
          child: ButtonsTabBar(
            onTap: c.onDestinationSelected,
            controller: c.tabController,
            contentPadding: const EdgeInsets.only(left: 15, right: 15),
            backgroundColor: Theme.of(context).textTheme.titleMedium?.color!,
            unselectedBackgroundColor: Theme.of(context).colorScheme.secondary,
            borderWidth: 0,
            buttonMargin: const EdgeInsets.only(
                right: 10, left: 4, top: 4, bottom: 4),
            borderColor: Colors.black,
            labelStyle: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: TextStyle(
              color: Theme.of(context).textTheme.titleMedium?.color!,
              fontWeight: FontWeight.bold,
            ),
            tabs: [
              Tab(text: "results".tr),
              ...c.railItems.map((item) => Tab(
                    text: item.toLowerCase().removeAllWhitespace.tr,
                  )),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 15.0),
            child: TabBarView(
              controller: c.tabController,
              children: [
                const ResultWidget(isv2Used: true),
                ...c.railItems.map((tabName) {
                  // 🔥 Passa os dados diretamente via Obx no widget filho
                  return SeparateTabItemWidget(
                    title: tabName,
                    hideTitle: true,
                    // Injeção direta dos dados – o widget usará esses itens
                    items: c.separatedResultContent[tabName] ?? [],
                    scrollController: c.scrollControllers[tabName],
                    isResultWidget: (tabName == "Songs" || tabName == "Videos"),
                    isCompleteList: true,
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
