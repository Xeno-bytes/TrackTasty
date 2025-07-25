import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitness/components/my_buttons.dart';
import 'package:fitness/components/gender_button.dart';
import 'package:fitness/components/selectable_Activity_Button.dart';
import 'package:fitness/theme/app_color.dart';
import 'package:fitness/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class Userpreference3 extends StatefulWidget {
  const Userpreference3({super.key});

  @override
  State<Userpreference3> createState() => _Userpreference3();
}

enum Gender { male, female }

class _Userpreference3 extends State<Userpreference3> {
  Gender? selectedGender;
  int selectedIndex = -1; // Track selected button (-1 means no selection)

  //selectable activity button values
  final List<Map<String, String>> activityLevels = [
    {'title': 'Lose Weight'},
    {'title': 'Maintain Weight'},
    {'title': 'Gain Weight'},
  ];

  // Save user preferences to Firestore
  Future<void> saveUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      await FirebaseFirestore.instance.collection("Users").doc(user.email).set({
        'gender': selectedGender?.name,
        'goal': activityLevels[selectedIndex]['title'],
        'dateAccountCreated': DateTime.now().year,
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      //linear percent indicator?
      appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Color(0xFF121212),
          title: SizedBox(
            width: double.infinity,
            child: LinearPercentIndicator(
              backgroundColor: Color(0xFFe8def8),
              progressColor: Color(0xFF65558F),
              percent: 0.5,
              barRadius: Radius.circular(5),
            ),
          )),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    //text
                    Text(
                      'Start your Nutrition Journey',
                      textAlign: TextAlign.left,
                      style: TextStyle(color: Colors.white, fontSize: 22),
                    ),

                    SizedBox(height: 5),

                    Text(
                      'Welcome to TrackTasty! We’re excited to help you on your nutrition journey. To get started, we need a little information about you.',
                      style: TextStyle(color: Colors.grey),
                    ),

                    SizedBox(
                      height: 20,
                    ),

                    Text(
                      'Please select your gender: \n',
                      style: TextStyle(color: Colors.white),
                    ),

                    // ---------------------
                    // Gender Selection
                    // ---------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GenderIcon(
                            isSelected: selectedGender == Gender.male,
                            iconData: Icons.male,
                            onTap: () =>
                                setState(() => selectedGender = Gender.male),
                            selectedColor: Colors.blue[800]!),
                        SizedBox(
                          width: 40,
                        ),
                        GenderIcon(
                            isSelected: selectedGender == Gender.female,
                            iconData: Icons.female,
                            onTap: () =>
                                setState(() => selectedGender = Gender.female),
                            selectedColor: Colors.pink[800]!)
                      ],
                    ),

                    SizedBox(
                      height: 50,
                    ),

                    Text(
                      'Select your goal on this application: \n',
                      style: TextStyle(color: Colors.white),
                    ),

                    //selectable activity buttons
                    Column(
                      children: List.generate(activityLevels.length, (index) {
                        return Selectableactivitybutton(
                            title: activityLevels[index]['title']!,
                            subtitle: activityLevels[index]['subtitle'],
                            isSelected: selectedIndex == index,
                            onTap: () {
                              setState(() {
                                selectedIndex = index;
                              });
                            });
                      }),
                    ),

                    SizedBox(
                      height: 100,
                    ),
                  ],
                ),
              ),
            ),
            //lower buttons back and continue button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  //back button with gesture detectore
                  CustomTextButton(
                      title: 'Back',
                      onTap: () {
                        context.push('/preference2');
                      },
                      size: 16),

                  SizedBox(width: 50),

                  //continue button
                  Expanded(
                    child: MyButtons(
                      text: 'Next',
                      onTap: () async {
                        if (selectedIndex == -1 && selectedGender == null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Please select your gender and goal'),
                            backgroundColor: AppColors.snackBarBgError,
                          ));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Saved!'),
                            backgroundColor: AppColors.snackBarBgSaved,
                          ));
                          await saveUserPreferences();
                          context.push('/preference4');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
