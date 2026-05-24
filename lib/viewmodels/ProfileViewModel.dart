import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../model/data/UserProfile.dart';
import '../model/service/user_profile_service.dart';
import '../model/Device.helper.dart';

class ProfileViewModel extends ChangeNotifier {
  final UserProfileDao _dao = UserProfileDao();
  final ImagePicker _picker = ImagePicker();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  String bloodType = 'A+';
  UserProfile? profile;
  File? pickedImageFile;

  bool get hasProfile => profile != null;

  get owner => profile?.name;

  String get currentImagePath =>
      pickedImageFile?.path ?? profile?.imagePath ?? '';

  Future<void> loadProfile() async {
    final user = await _dao.getUserProfile();
    if (user != null) {
      profile = user;
      nameController.text = user.name;
      phoneController.text = user.phone;
      bloodType = user.bloodType;
      if (user.imagePath.isNotEmpty) {
        final f = File(user.imagePath);
        if (await f.exists()) pickedImageFile = f;
      }
    }
    notifyListeners();
  }

  Future<void> pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile =
    await File(picked.path).copy(p.join(dir.path, fileName));

    pickedImageFile = savedFile;
    notifyListeners();
  }

  Future<void> saveProfile() async {
    final now = DateTime.now().toIso8601String();
    final imagePath = pickedImageFile?.path ?? profile?.imagePath ?? '';

    if (profile == null) {
      final deviceId = await DeviceIdHelper.getDeviceId();
      profile = UserProfile(
        id: 1,
        deviceId: deviceId,
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        bloodType: bloodType,
        imagePath: imagePath,
        createdAt: now,
        updatedAt: now,
      );
      await _dao.insertUserProfile(profile!);
    } else {
      profile = UserProfile(
        id: profile!.id,
        deviceId: profile!.deviceId,
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        bloodType: bloodType,
        imagePath: imagePath,
        createdAt: profile!.createdAt,
        updatedAt: now,
      );
      await _dao.updateUserProfile(profile!);
    }

    notifyListeners();
  }
}