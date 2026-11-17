import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../theme/app_theme.dart';

class ToastUtils {
  static void showError(String message) {
    _showToast(
      message,
      backgroundColor: AppTheme.error,
      textColor: AppTheme.primaryWhite,
    );
  }

  static void showSuccess(String message) {
    _showToast(
      message,
      backgroundColor: AppTheme.success,
      textColor: AppTheme.primaryWhite,
    );
  }

  static void _showToast(
    String message, {
    required Color backgroundColor,
    required Color textColor,
  }) {
    Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.TOP,
      toastLength: Toast.LENGTH_LONG,
      backgroundColor: backgroundColor,
      textColor: textColor,
      fontSize: 14.0,
    );
  }
}
