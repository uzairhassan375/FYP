class StudentUser {
  final String id;
  final String email;
  final String role;
  final String? name;
  final String? studentId;

  const StudentUser({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.studentId,
  });

  factory StudentUser.fromJson(Map<String, dynamic> json) {
    return StudentUser(
      id: '${json['id']}',
      email: '${json['email']}',
      role: '${json['role']}',
      name: json['name'] as String?,
      studentId: json['student_id'] != null ? '${json['student_id']}' : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'name': name,
        'student_id': studentId,
      };
}
