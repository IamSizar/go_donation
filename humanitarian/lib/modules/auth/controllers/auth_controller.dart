import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';

import '../models/user_model.dart';

class AuthController extends GetxController {
  final isLoading = false.obs;
  final currentUser = Rxn<UserModel>();
  final authError = RxnString();

  /// Attempt to login via API.
  /// Returns the UserModel on success, null on failure.
  Future<UserModel?> login({
    required String phone,
    required String password,
  }) async {
    isLoading.value = true;
    authError.value = null;
    try {
      final uri = Uri.parse('YOUR_LOGIN_API_URL_HERE'); // Replace with your actual endpoint
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'phone': phone.trim(),
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success' && data['user'] != null) {
          final userData = data['user'];
          final user = UserModel(
            id: userData['id']?.toString() ?? '',
            name: userData['name']?.toString() ?? '',
            email: userData['email']?.toString() ?? '',
            phone: userData['phone']?.toString() ?? phone,
            // Add/fix fields per your UserModel
          );
          currentUser.value = user;
          isLoading.value = false;
          return user;
        } else {
          authError.value =
              data['error']?.toString() ?? 'Failed to login. Try again.';
        }
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        final data = jsonDecode(response.body);
        authError.value =
            data['error']?.toString() ?? 'Invalid credentials or missing fields.';
      } else {
        authError.value =
            'Unexpected error (${response.statusCode}). Please try again.';
      }
    } catch (e) {
      authError.value = 'Login failed. Please check your internet or try again.';
    }

    currentUser.value = null;
    isLoading.value = false;
    return null;
  }
}
