import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitness/provider/user_provider.dart';
import 'package:fitness/widgets/main_screen_widgets/profile_screen/achievement_container.dart';
import 'package:fitness/widgets/main_screen_widgets/profile_screen/profile_container.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // Future to fetch user details
  Future<DocumentSnapshot<Map<String, dynamic>>> getUserDetails() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    return await FirebaseFirestore.instance
        .collection("Users")
        .doc(currentUser!.email)
        .get();
  }

  // Future to fetch user achievements
  Future<Map<String, dynamic>> getUserAchievements() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return {};

    try {
      final doc = await FirebaseFirestore.instance
          .collection("user_achievements")
          .doc(currentUser.uid)
          .get();

      return doc.exists ? doc.data() ?? {} : {};
    } catch (e) {
      debugPrint("Error fetching achievements: $e");
      return {};
    }
  }

  // Future to fetch weight data
  Future<Map<String, dynamic>> getUserWeightData() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {
        'initialWeight': 0.0,
        'currentWeight': 0.0,
        'measurementSystem': 'Metric'
      };
    }

    try {
      // Get user details to check measurement system
      final userDoc = await FirebaseFirestore.instance
          .collection("Users")
          .doc(currentUser.email)
          .get();

      final measurementSystem =
          userDoc.data()?['measurementSystem'] ?? 'Metric';

      // Get all weight logs for the user, ordered by date
      final querySnapshot = await FirebaseFirestore.instance
          .collection("weight_history")
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('date', descending: false)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return {
          'initialWeight': 0.0,
          'currentWeight': 0.0,
          'measurementSystem': measurementSystem
        };
      }

      // Get initial weight (first document)
      final initialWeight = querySnapshot.docs.first.data()['weight'] ?? 0.0;

      // Get current weight (last document)
      final currentWeight = querySnapshot.docs.last.data()['weight'] ?? 0.0;

      return {
        'initialWeight': initialWeight.toDouble(),
        'currentWeight': currentWeight.toDouble(),
        'measurementSystem': measurementSystem
      };
    } catch (e) {
      debugPrint("Error fetching weight data: $e");
      return {
        'initialWeight': 0.0,
        'currentWeight': 0.0,
        'measurementSystem': 'Metric'
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    return Scaffold(
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: getUserDetails(),
        builder: (context, snapshot) {
          // If data is loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          // If user is not logged in
          if (FirebaseAuth.instance.currentUser == null) {
            return Center(child: Text("Please log in to view profile"));
          }

          // If there's an error
          if (snapshot.hasError) {
            return Center(child: Text("Error loading profile"));
          }

          // If data is available
          if (snapshot.hasData && snapshot.data!.exists) {
            var userData = snapshot.data!.data();
            String username = userData?['username'] ?? "Unknown User";
            final joinedDateRaw = userData?['dateAccountCreated'];
            DateTime joinedDate;
            if (joinedDateRaw is int && joinedDateRaw > 1000000000000) {
              // If it's a timestamp (milliseconds since epoch)
              joinedDate = DateTime.fromMillisecondsSinceEpoch(joinedDateRaw);
            } else if (joinedDateRaw is int) {
              // If it's a simple year or date
              joinedDate = DateTime(joinedDateRaw);
            } else {
              joinedDate = DateTime.now(); // Fallback to current date
            }
            int dayStreak;
            int highestDayStreak;

            return FutureBuilder<Map<String, dynamic>>(
                future: getUserAchievements(),
                builder: (context, achievementSnapshot) {
                  if (achievementSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final achievements = achievementSnapshot.data ?? {};
                  dayStreak = achievements['daily_streak'] ?? 0;
                  highestDayStreak = achievements['highest_streak'] ?? 0;

                  return FutureBuilder<Map<String, dynamic>>(
                    future: getUserWeightData(),
                    builder: (context, weightSnapshot) {
                      if (weightSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      final weightData = weightSnapshot.data ??
                          {
                            'initialWeight': 0.0,
                            'currentWeight': 0.0,
                            'measurementSystem': 'Metric'
                          };
                      final double initialWeight =
                          weightData['initialWeight'] ?? 0.0;
                      final double currentWeight =
                          weightData['currentWeight'] ?? 0.0;
                      final String measurementSystem =
                          weightData['measurementSystem'] ?? 'Metric';

                      // Define achievement data
                      final List<Map<String, dynamic>> achievementList = [
                        {
                          'id': 'daily_tracker',
                          'title': 'Daily Tracker',
                          'description':
                              'Reached a ${_getAchievementLevel(achievements['highest_streak'] ?? 0, [
                                7,
                                14,
                                60,
                                180,
                                365
                              ])} days streak!',
                          'nextStarDescription': _getNextStarDescription(
                              achievements['highest_streak'] ?? 0,
                              [7, 14, 60, 180, 365],
                              'days streak'),
                          'progress':
                              '${achievements['highest_streak'] ?? 0} days',
                          'stars': _getStarCount(
                              achievements['highest_streak'] ?? 0,
                              [7, 14, 60, 180, 365]),
                        },
                        {
                          'id': 'click_eat',
                          'title': 'Click & Eat',
                          'description':
                              'Used image logging ${_getAchievementLevel(achievements['image_logs'] ?? 0, [
                                10,
                                30,
                                50,
                                100,
                                200
                              ])} times.',
                          'nextStarDescription': _getNextStarDescription(
                              achievements['image_logs'] ?? 0,
                              [10, 30, 50, 100, 200],
                              'image logs'),
                          'progress':
                              '${achievements['image_logs'] ?? 0} times',
                          'stars': _getStarCount(
                              achievements['image_logs'] ?? 0,
                              [10, 30, 50, 100, 200]),
                        },
                        {
                          'id': 'food_explorer',
                          'title': 'Food Explorer',
                          'description':
                              'Logged ${_getAchievementLevel(achievements['unique_foods'] ?? 0, [
                                20,
                                50,
                                100,
                                150,
                                250
                              ])} unique foods.',
                          'nextStarDescription': _getNextStarDescription(
                              achievements['unique_foods'] ?? 0,
                              [20, 50, 100, 150, 250],
                              'unique foods'),
                          'progress':
                              '${achievements['unique_foods'] ?? 0} foods',
                          'stars': _getStarCount(
                              achievements['unique_foods'] ?? 0,
                              [20, 50, 100, 150, 250]),
                        },
                        {
                          'id': 'macro_magician',
                          'title': 'Macro Magician',
                          'description':
                              'Hit all 3 macro targets ${_getAchievementLevel(achievements['macro_perfect_days'] ?? 0, [
                                7,
                                14,
                                60,
                                180,
                                365
                              ])} times.',
                          'nextStarDescription': _getNextStarDescription(
                              achievements['macro_perfect_days'] ?? 0,
                              [7, 14, 60, 180, 365],
                              'perfect days'),
                          'progress':
                              '${achievements['macro_perfect_days'] ?? 0} days',
                          'stars': _getStarCount(
                              achievements['macro_perfect_days'] ?? 0,
                              [7, 14, 60, 180, 365]),
                        },
                      ];

                      return Scaffold(
                        backgroundColor:
                            Theme.of(context).scaffoldBackgroundColor,
                        body: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.all(0),
                            child: Column(
                              children: [
                                ProfileContainer(
                                  name: username,
                                  joinedDate: joinedDate,
                                  dayStreak: dayStreak,
                                  highestDayStreak: highestDayStreak,
                                  initialWeight: initialWeight,
                                  currentWeight: currentWeight,
                                  measurementSystem: measurementSystem,
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(height: 10),
                                        Text(
                                          'Achievements',
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 25,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 10),
                                        GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 1,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                            childAspectRatio: 1.5,
                                          ),
                                          itemCount: achievementList.length,
                                          itemBuilder: (context, index) {
                                            final achievement =
                                                achievementList[index];
                                            return AchievementContainer(
                                              title: achievement['title'],
                                              description:
                                                  achievement['description'],
                                              nextStarDescription: achievement[
                                                  'nextStarDescription'],
                                              progress: achievement['progress'],
                                              stars: achievement['stars'],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                });
          }

          // Return if no user found
          return Center(child: Text("User not found"));
        },
      ),
    );
  }

  // Get star count based on progress
  int _getStarCount(int progress, List<int> milestones) {
    for (int i = milestones.length - 1; i >= 0; i--) {
      if (progress >= milestones[i]) {
        return i + 1;
      }
    }
    return 0;
  }

  // Get achievement level description
  String _getAchievementLevel(int progress, List<int> milestones) {
    for (int i = milestones.length - 1; i >= 0; i--) {
      if (progress >= milestones[i]) {
        return milestones[i].toString();
      }
    }
    return progress.toString();
  }

  // Get next star description
  String _getNextStarDescription(
      int progress, List<int> milestones, String unit) {
    for (int i = 0; i < milestones.length; i++) {
      if (progress < milestones[i]) {
        final needed = milestones[i] - progress;
        return 'Need more $needed $unit for next star';
      }
    }
    return 'Max level reached!';
  }
}
