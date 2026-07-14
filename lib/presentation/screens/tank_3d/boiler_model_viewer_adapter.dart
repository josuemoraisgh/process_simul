// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart';
import 'package:flutter_3d_controller/src/data/datasources/i_flutter_3d_datasource.dart';
import 'package:flutter_3d_controller/src/data/repositories/flutter_3d_repository.dart';
import 'package:flutter_3d_controller/src/utils/utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void initializeBoilerControllerForWeb(Flutter3DController controller, String id,
    {bool isWeb = kIsWeb}) {
  if (isWeb) {
    controller.init(Flutter3DRepository(IFlutter3DDatasource(id, null, false)));
  }
}

Widget buildBoilerModelViewer({
  required String id,
  required Flutter3DController controller,
  required Utils utils,
  required String cameraOrbit,
  required String? cameraTarget,
  required String? fieldOfView,
  required ValueChanged<String> onLoad,
  required ValueChanged<Object> onError,
  required void Function(List<dynamic>) onCameraChange,
  VoidCallback? onEscapePressed,
  VoidCallback? onDoubleClick,
}) {
  InAppWebViewController? webView;
  return ModelViewer(
    id: id,
    src: 'assets/models/tank.glb',
    backgroundColor: const Color(0xFF1a1a2e),
    environmentImage: 'neutral',
    exposure: 1.2,
    shadowIntensity: 1.0,
    shadowSoftness: 0.8,
    cameraControls: true,
    autoRotate: false,
    cameraOrbit: cameraOrbit,
    cameraTarget: cameraTarget,
    fieldOfView: fieldOfView,
    interactionPrompt: InteractionPrompt.none,
    disableTap: true,
    ar: false,
    autoPlay: false,
    debugLogging: false,
    activeGestureInterceptor: true,
    relatedCss: '''
        model-viewer {
          --poster-color: #1a1a2e;
          --progress-bar-color: #4fc3f7;
        }
      ''',
    relatedJs: utils.injectedJS(id, 'flutter-3d-controller'),
    onLoad: (address) {
      final controller = webView;
      if (controller != null) {
        for (final source in _javascriptSources(
            escape: onEscapePressed != null,
            doubleClick: onDoubleClick != null)) {
          controller.evaluateJavascript(source: source);
        }
      }
      onLoad(address);
    },
    onError: onError,
    onWebViewCreated: kIsWeb
        ? null
        : (InAppWebViewController webViewController) {
            webView = webViewController;
            controller.init(Flutter3DRepository(
                IFlutter3DDatasource(id, webViewController, true)));
            webViewController.addJavaScriptHandler(
                handlerName: 'onCameraChange', callback: onCameraChange);
            if (onEscapePressed != null) {
              webViewController.addJavaScriptHandler(
                  handlerName: 'onEscapePressed',
                  callback: (_) => onEscapePressed());
            }
            if (onDoubleClick != null) {
              webViewController.addJavaScriptHandler(
                  handlerName: 'onDoubleClick',
                  callback: (_) => onDoubleClick());
            }
          },
  );
}

List<String> _javascriptSources(
    {required bool escape, required bool doubleClick}) {
  final result = <String>[
    '''
      var mv = document.querySelector('model-viewer');
      if (mv) {
        mv.setAttribute('tone-mapping', 'commerce');
        mv.setAttribute('environment-intensity', '1.8');
        mv.setAttribute('shadow-intensity', '2');
        mv.addEventListener('camera-change', function(e) {
          if (e.detail && e.detail.source === 'user-interaction') {
            var co = mv.getCameraOrbit();
            var ct = mv.getCameraTarget();
            var fov = mv.getFieldOfView();
            var data = co.toString() + '||' + ct.toString() + '||' + fov.toString() + 'deg';
            window.flutter_inappwebview.callHandler('onCameraChange', data);
          }
        });
      }
    ''',
  ];
  if (escape) {
    result.add('''
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
          e.preventDefault();
          window.flutter_inappwebview.callHandler('onEscapePressed');
        }
      });
    ''');
  }
  if (doubleClick) {
    result.add('''
      document.addEventListener('dblclick', function(e) {
        e.preventDefault();
        window.flutter_inappwebview.callHandler('onDoubleClick');
      });
    ''');
  }
  return result;
}
