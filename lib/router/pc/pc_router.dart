import 'package:flutter/material.dart';

import '../../pc/pc_home.dart';

/// 需要引入跳转页面地址

/// 配置路由
final routes = {
  '/': (context) => const PCHomePage(),
  '/home': (context) => const PCHomePage(),
  // 路由表中的函数不需要处理参数
};

Route<dynamic>? pcGenerateRoute(RouteSettings settings) {
  final String? name = settings.name;

  switch (name) {
    case '/':
      return MaterialPageRoute(builder: (context) => const PCHomePage());
    case '/home':
      return MaterialPageRoute(builder: (context) => const PCHomePage());
    default:
      return _errorRoute();
  }
}

Route<dynamic> _errorRoute() {
  return MaterialPageRoute(builder: (context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: const Center(child: Text('Page not found')),
    );
  });
}
