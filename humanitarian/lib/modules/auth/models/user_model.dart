class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
  });

  final String id;
  final String name;
  final String email;
  final String phone;
}
