import 'dart:async';
import 'dart:convert';
import 'package:fitness/provider/user_provider.dart';
import 'package:fitness/widgets/main_screen_widgets/chat_bot_widgets/meal_suggestion_container.dart';
import 'package:fitness/widgets/main_screen_widgets/chat_bot_widgets/recipe_container.dart';

import 'package:flutter/material.dart';
import 'package:fitness/services/deepseek_api_service.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatBot extends StatefulWidget {
  const ChatBot({super.key});

  @override
  State<ChatBot> createState() => _ChatBotState();
}

class _ChatBotState extends State<ChatBot> with AutomaticKeepAliveClientMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageNode = FocusNode();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  Map<String, dynamic>? _currentUserData;
  static const String _chatStorageKey = 'chatbot_conversation';
  bool _showResetButton = false;
  bool isMetric = false;

  // Text field height management
  final double _minTextFieldHeight = 56.0;
  final double _maxTextFieldHeight = 120.0;
  double _currentTextFieldHeight = 56.0;

  // Nutrition data state
  Map<String, dynamic>? _nutritionData;
  Map<String, dynamic>? _userGoals;

  @override
  bool get wantKeepAlive => true; // Changed to true to preserve state

  @override
  void initState() {
    super.initState();
    _initializeUserData();
    _loadNutritionData();
    _loadConversationHistory();

    // Listen to text changes to adjust height
    _messageController.addListener(_adjustTextFieldHeight);

    _scrollController.addListener(() {
      // Check if the user is at the very bottom of the screen
      final atBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent;

      // Check if the user has scrolled up from the bottom
      final hasScrolledUp =
          _scrollController.offset < _scrollController.position.maxScrollExtent;

      // The buttons should be visible when the user has scrolled up from the bottom, and hidden when they are at the bottom.
      final shouldShowButtons = hasScrolledUp;

      if (shouldShowButtons != _showResetButton) {
        setState(() {
          _showResetButton = shouldShowButtons;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Adjust text field height based on content
  void _adjustTextFieldHeight() {
    final text = _messageController.text;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      maxLines: 4,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 120);

    final desiredHeight = textPainter.size.height + 24; // Add padding

    setState(() {
      _currentTextFieldHeight =
          desiredHeight.clamp(_minTextFieldHeight, _maxTextFieldHeight);
    });
  }

  // Initialize user data using UserProvider
  Future<void> _initializeUserData() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();

      // Fetch the latest user data from Firestore
      await userProvider.fetchUserData();

      // Get the updated user data
      _currentUserData = userProvider.userData;

      // Load user goals after fetching user data
      await _loadUserGoals();

      debugPrint("USER DATA INITIALIZED: $_currentUserData");
      debugPrint("USER GOALS INITIALIZED: $_userGoals");
    } catch (e) {
      debugPrint('ERROR INITIALIZING USER DATA: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load saved conversation from local storage
  Future<void> _loadConversationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedConversation = prefs.getString(_chatStorageKey);

      if (savedConversation != null) {
        final List<dynamic> decodedMessages = jsonDecode(savedConversation);
        setState(() {
          _messages.addAll(
              decodedMessages.map((msg) => Map<String, dynamic>.from(msg)));
        });

        // Scroll to bottom after loading messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      } else {
        // If no saved conversation, add welcome message
        _addWelcomeMessage();
      }
    } catch (e) {
      debugPrint('ERROR LOADING CONVERSATION: $e');
      _addWelcomeMessage();
    }
  }

  // Save conversation to local storage
  Future<void> _saveConversation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chatStorageKey, jsonEncode(_messages));
    } catch (e) {
      debugPrint('ERROR SAVING CONVERSATION: $e');
    }
  }

  // Reset conversation but keep the MacroExpert introduction
  Future<void> _resetConversation() async {
    // Find the MacroExpert introduction message
    final introMessageIndex = _messages.indexWhere((msg) =>
        msg["role"] == "assistant" &&
        (msg["content"] as String).contains("Macro Tracking Assistant"));

    // Keep only the introduction message if found
    if (introMessageIndex != -1) {
      final introMessage = _messages[introMessageIndex];
      setState(() {
        _messages.clear();
        _messages.add(introMessage);
      });
    } else {
      // If no intro found, clear all and add welcome message
      setState(() {
        _messages.clear();
      });
      _addWelcomeMessage();
    }

    // Clear from storage and save the new state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatStorageKey, jsonEncode(_messages));

    // Scroll to top to show the intro message
    _scrollToTop();
  }

  // Load user's nutrition goals using UserProvider
  Future<void> _loadUserGoals() async {
    try {
      final userProvider = context.read<UserProvider>();
      final userData = userProvider.userData;

      if (userData != null) {
        setState(() {
          _userGoals = {
            'calorieGoal': _convertToInt(userData['dailyCalories']),
            'proteinGoal': _convertToInt(userData['proteinGram']),
            'carbsGoal': _convertToInt(userData['carbsGram']),
            'fatGoal': _convertToInt(userData['fatsGram']),
          };
        });
        debugPrint("USER GOALS LOADED: $_userGoals");
      } else {
        // Fallback to default values if user data is null
        setState(() {
          _userGoals = {
            'calorieGoal': 2000,
            'proteinGoal': 100,
            'carbsGoal': 250,
            'fatGoal': 70,
          };
        });
        debugPrint("USER DATA IS NULL, USING DEFAULT GOALS: $_userGoals");
      }
    } catch (e) {
      debugPrint('ERROR LOADING USER GOALS: $e');
      // Fallback to default values on error
      setState(() {
        _userGoals = {
          'calorieGoal': 2000,
          'proteinGoal': 100,
          'carbsGoal': 250,
          'fatGoal': 70,
        };
      });
    }
  }

  // Load today's nutrition data (unchanged - this is working properly)
  Future<void> _loadNutritionData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final foodLogId = '${user.uid}_${today.year}-${today.month}-${today.day}';

    try {
      final foodLogDoc = await FirebaseFirestore.instance
          .collection('food_logs')
          .doc(foodLogId)
          .get();

      if (foodLogDoc.exists) {
        setState(() {
          _nutritionData = {
            'totalCalories': _convertToInt(foodLogDoc.data()?['totalCalories']),
            'totalProtein': _convertToInt(foodLogDoc.data()?['totalProtein']),
            'totalCarbs': _convertToInt(foodLogDoc.data()?['totalCarbs']),
            'totalFat': _convertToInt(foodLogDoc.data()?['totalFat']),
          };
        });
        debugPrint("NUTRITION DATA LOADED: $_nutritionData");
      } else {
        setState(() {
          _nutritionData = {
            'totalCalories': 0,
            'totalProtein': 0,
            'totalCarbs': 0,
            'totalFat': 0,
          };
        });
        debugPrint("NO NUTRITION DATA FOUND, USING DEFAULT: $_nutritionData");
      }
    } catch (e) {
      debugPrint('ERROR LOADING NUTRITION DATA: $e');
      setState(() {
        _nutritionData = {
          'totalCalories': 0,
          'totalProtein': 0,
          'totalCarbs': 0,
          'totalFat': 0,
        };
      });
    }
  }

  // Helper function to convert any value to int
  int _convertToInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void _addWelcomeMessage() {
    _messages.add({
      "role": "assistant",
      "content": ":wave: Hi! I'm your Macro Tracking Assistant!\n\n"
          "I can help you with:\n"
          "• Provide nutritional information of a food\n"
          "• Tracking meals and nutrients\n"
          "• Planning meals for your goals\n"
          "• Share recipes that you are interested in\n\n"
          "Try asking:\n"
          "• \"What is the recipe of Chicken Adobo?\"\n"
          "• \"What's the macro of chicken breast?\"\n"
          "• \"Plan a high-protein meal for the whole day.\""
    });

    // Save the conversation after adding welcome message
    _saveConversation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _refreshUserData() async {
    setState(() => _isLoading = true);
    debugPrint("REFRESHING USER DATA...");

    // Simulate a small delay for better UX
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final userProvider = context.read<UserProvider>();

      // Fetch the latest user data from Firestore
      await userProvider.fetchUserData();

      // Get the updated user data
      final newUserData = userProvider.userData;

      // Reload nutrition data and goals
      await _loadNutritionData();
      await _loadUserGoals();

      setState(() {
        _currentUserData = newUserData;
        _isLoading = false;
      });

      debugPrint("USER DATA REFRESHED: $_currentUserData");
      debugPrint("USER GOALS REFRESHED: $_userGoals");

      // Show confirmation message
      _showRefreshConfirmation();
    } catch (e) {
      debugPrint('ERROR REFRESHING USER DATA: $e');
      setState(() => _isLoading = false);

      // Show error message
      setState(() {
        _messages.add({
          "role": "error",
          "content": "Failed to refresh user data. Please try again.",
        });
      });
      _saveConversation();
      _scrollToBottom();
    }
  }

  void _showRefreshConfirmation() {
    final newUserData = _currentUserData;
    if (newUserData != null) {
      // Calculate remaining macros
      final remainingCalories = (_userGoals?['calorieGoal'] ?? 2000) -
          (_nutritionData?['totalCalories'] ?? 0);
      final remainingProtein = (_userGoals?['proteinGoal'] ?? 100) -
          (_nutritionData?['totalProtein'] ?? 0);
      final remainingCarbs = (_userGoals?['carbsGoal'] ?? 250) -
          (_nutritionData?['totalCarbs'] ?? 0);
      final remainingFat =
          (_userGoals?['fatGoal'] ?? 70) - (_nutritionData?['totalFat'] ?? 0);

      isMetric = newUserData['measurementSystem'] == "Metric";

      // Helper variables for unit conversion
      final weightUnit = isMetric ? 'kg' : 'lbs';
      final heightUnit = isMetric ? 'cm' : 'inches';

      _messages.add({
        "role": "system",
        "content": "🔄 Profile updated! I now know:\n"
            "• Age: ${newUserData['age']?.toString() ?? 'Not set'}\n"
            "• Weight: ${newUserData['weight']?.toString() ?? 'Not set'} $weightUnit\n"
            "• Height: ${newUserData['height']?.toString() ?? 'Not set'} $heightUnit\n"
            "• Goal: ${newUserData['goal']?.toString() ?? 'Not set'}\n"
            "• Dietary Preference: ${newUserData['dietaryPreference']?.toString() ?? 'None'}\n"
            "• Allergies: ${newUserData['allergies']?.toString() ?? "None"}\n\n"
            "📊 Today's Progress:\n"
            "• Calories: ${_nutritionData?['totalCalories'] ?? 0}/${_userGoals?['calorieGoal'] ?? 2000} "
            "(${remainingCalories > 0 ? '$remainingCalories remaining' : '${-remainingCalories} over'})\n"
            "• Protein: ${_nutritionData?['totalProtein'] ?? 0}/${_userGoals?['proteinGoal'] ?? 100}g "
            "(${remainingProtein > 0 ? '$remainingProtein g remaining' : '${-remainingProtein}g over'})\n"
            "• Carbs: ${_nutritionData?['totalCarbs'] ?? 0}/${_userGoals?['carbsGoal'] ?? 250}g "
            "(${remainingCarbs > 0 ? '$remainingCarbs g remaining' : '${-remainingCarbs}g over'})\n"
            "• Fat: ${_nutritionData?['totalFat'] ?? 0}/${_userGoals?['fatGoal'] ?? 70}g "
            "(${remainingFat > 0 ? '$remainingFat g remaining' : '${-remainingFat}g over'})"
      });

      // Save the conversation after adding system message
      _saveConversation();

      _scrollToBottom();
    }
  }

  // Parsing JSON response (unchanged)
  Map<String, dynamic> _parseMixedResponse(String content) {
    try {
      // First, try to parse the entire content as JSON
      final jsonData = jsonDecode(content);
      if (jsonData is List) {
        return {
          'meals': jsonData.whereType<Map<String, dynamic>>().toList(),
          'recipes': [],
          'nutritional_info': [],
          'text': ''
        };
      }
      if (jsonData is Map<String, dynamic>) {
        // Check the meal_type to determine the response type
        final mealType = jsonData['meal_type']?.toString() ?? '';

        if (mealType == 'recipe') {
          return {
            'meals': [],
            'recipes': [jsonData],
            'nutritional_info': [],
            'text': ''
          };
        } else if (mealType == 'nutritional_info') {
          return {
            'meals': [],
            'recipes': [],
            'nutritional_info': [jsonData],
            'text': ''
          };
        } else {
          return {
            'meals': [jsonData],
            'recipes': [],
            'nutritional_info': [],
            'text': ''
          };
        }
      }
    } catch (e) {
      // If not pure JSON, look for JSON objects within text
      final jsonPattern = r'\{.*?\}';
      final matches = RegExp(jsonPattern, multiLine: true).allMatches(content);

      if (matches.isNotEmpty) {
        final meals = <Map<String, dynamic>>[];
        final recipes = <Map<String, dynamic>>[];
        final nutritionalInfo = <Map<String, dynamic>>[];
        var remainingText = content;

        for (final match in matches) {
          try {
            final jsonStr = match.group(0);
            if (jsonStr != null) {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;

              // Check the meal_type to determine the response type
              final mealType = data['meal_type']?.toString() ?? '';

              if (mealType == 'recipe') {
                recipes.add(data);
              } else if (mealType == 'nutritional_info') {
                nutritionalInfo.add(data);
              } else {
                meals.add(data);
              }

              remainingText = remainingText.replaceAll(jsonStr, '').trim();
            }
          } catch (e) {
            // Skip invalid JSON matches
          }
        }

        return {
          'meals': meals,
          'recipes': recipes,
          'nutritional_info': nutritionalInfo,
          'text': remainingText.isNotEmpty ? remainingText : ''
        };
      }
    }

    return {
      'meals': [],
      'recipes': [],
      'nutritional_info': [],
      'text': content
    };
  }

  Future<void> _sendMessage() async {
    final userMessage = _messageController.text.trim();
    if (userMessage.isEmpty || _isLoading) return;

    // Debug print for user input
    debugPrint("USER INPUT: \"$userMessage\"");

    setState(() {
      _messages.add({"role": "user", "content": userMessage});
      _messageController.clear();
      _isLoading = true;
      _currentTextFieldHeight =
          _minTextFieldHeight; // Reset height after sending
    });

    // Save the conversation after adding user message
    _saveConversation();

    try {
      // Debug print for API request data
      debugPrint('''
      --------------------------------------------------
      CALLING DEEPSEEK API WITH THE FOLLOWING DATA:
      - Prompt: $userMessage
      - User Data:
        - username: ${_currentUserData?['username']?.toString() ?? 'Guest'}
        - age: ${_currentUserData?['age']?.toString() ?? '25'}
        - allergies: ${List<String>.from(_currentUserData?['allergies'] ?? [])}
        - weight: ${_currentUserData?['weight']?.toString() ?? '65'}
        - height: ${_currentUserData?['height']?.toString() ?? '170'}
        - goal: ${_currentUserData?['goal']?.toString() ?? 'maintenance'}
        - goalWeight: ${_currentUserData?['goalWeight']?.toString() ?? '0'}
        - gender: ${_currentUserData?['gender']?.toString() ?? 'prefer not to say'}
        - dietaryPreference: ${_currentUserData?['dietaryPreference']?.toString() ?? 'none'}
      - Nutrition Data:
        - totalCalories: ${_nutritionData?['totalCalories'] ?? 0}
        - totalProtein: ${_nutritionData?['totalProtein'] ?? 0}
        - totalCarbs: ${_nutritionData?['totalCarbs'] ?? 0}
        - totalFat: ${_nutritionData?['totalFat'] ?? 0}
      - Goals:
        - calorieGoal: ${_userGoals?['calorieGoal'] ?? 2000}
        - proteinGoal: ${_userGoals?['proteinGoal'] ?? 100}
        - carbsGoal: ${_userGoals?['carbsGoal'] ?? 250}
        - fatGoal: ${_userGoals?['fatGoal'] ?? 70}
      --------------------------------------------------
      ''');

      // Convert history to the correct type (Map<String, String>)
      final List<Map<String, String>> history = _messages
          .sublist(1, _messages.length - 1)
          .where((msg) =>
              msg["role"] != "meal_suggestion" &&
              msg["role"] != "system" &&
              msg["role"] != "error")
          .map((msg) => {
                "role": msg["role"] as String,
                "content": msg["content"] is String
                    ? msg["content"] as String
                    : msg["content"].toString(),
              })
          .toList();

      final aiMessage = await DeepSeekApi.getChatResponse(
        prompt: userMessage,
        username: _currentUserData?['username']?.toString() ?? 'Guest',
        age: _currentUserData?['age']?.toString() ?? '25',
        allergies: List<String>.from(_currentUserData?['allergies'] ?? []),
        weight: _currentUserData?['weight']?.toString() ?? '65',
        height: _currentUserData?['height']?.toString() ?? '170',
        goal: _currentUserData?['goal']?.toString() ?? 'maintenance',
        goalWeight: _currentUserData?['goalWeight']?.toString() ?? '0',
        gender: _currentUserData?['gender']?.toString() ?? 'prefer not to say',
        dietaryPreference:
            _currentUserData?['dietaryPreference']?.toString() ?? 'none',
        totalCalories: _nutritionData?['totalCalories'] ?? 0,
        totalProtein: _nutritionData?['totalProtein'] ?? 0,
        totalCarbs: _nutritionData?['totalCarbs'] ?? 0,
        totalFat: _nutritionData?['totalFat'] ?? 0,
        calorieGoal: _userGoals?['calorieGoal'] ?? 2000,
        proteinGoal: _userGoals?['proteinGoal'] ?? 100,
        carbsGoal: _userGoals?['carbsGoal'] ?? 250,
        fatGoal: _userGoals?['fatGoal'] ?? 70,
      ).timeout(const Duration(seconds: 30));

      // Parse for JSON meals + normal text
      final parsedResponse = _parseMixedResponse(aiMessage);

      // Debug print for chatbot output
      debugPrint("PARSED RESPONSE: ${parsedResponse['meals'].length} meals, "
          "${parsedResponse['recipes'].length} recipes, "
          "${parsedResponse['nutritional_info'].length} nutritional info, "
          "text: '${parsedResponse['text']}'");

      debugPrint(aiMessage);

      // Add meal suggestions if any
      if (parsedResponse['meals'].isNotEmpty) {
        for (final meal in parsedResponse['meals']) {
          setState(() {
            _messages.add({
              "role": "meal_suggestion",
              "content": meal,
            });
          });
        }
      }

      // Add recipes if any
      if (parsedResponse['recipes'].isNotEmpty) {
        for (final recipe in parsedResponse['recipes']) {
          setState(() {
            _messages.add({
              "role": "recipe",
              "content": recipe,
            });
          });
        }
      }

      if (parsedResponse['nutritional_info'].isNotEmpty) {
        for (final info in parsedResponse['nutritional_info']) {
          setState(() {
            _messages.add({
              "role": "nutritional_info",
              "content": info,
            });
          });
        }
      }

      // Add text response if exists
      if (parsedResponse['text'].isNotEmpty) {
        setState(() {
          _messages
              .add({"role": "assistant", "content": parsedResponse['text']});
        });
      }

      // Save the conversation after adding AI response
      _saveConversation();
    } catch (e) {
      // Debug print for error
      debugPrint("API ERROR: $e");

      String errorMessage;
      if (e is TimeoutException) {
        errorMessage = "Request timed out. Please try again.";
        debugPrint("ERROR TYPE: TimeoutException");
      } else if (e.toString().contains("401") || e.toString().contains("403")) {
        errorMessage = "Authentication failed. Please check your API key.";
        debugPrint("ERROR TYPE: Authentication Error");
      } else if (e.toString().contains("429")) {
        errorMessage = "Too many requests. Please wait a moment.";
        debugPrint("ERROR TYPE: Rate Limit Error");
      } else if (e.toString().contains("500") ||
          e.toString().contains("502") ||
          e.toString().contains("503")) {
        errorMessage = "Server error. Please try again later.";
        debugPrint("ERROR TYPE: Server Error");
      } else {
        errorMessage =
            "Sorry, I couldn't process your request. Please try again.";
        debugPrint("ERROR TYPE: Unknown Error");
      }

      debugPrint("ERROR MESSAGE DISPLAYED TO USER: \"$errorMessage\"");

      setState(() {
        _messages.add({
          "role": "error",
          "content": errorMessage,
        });
      });

      // Save the conversation after adding error message
      _saveConversation();
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Show settings popup menu
  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.refresh, color: Colors.blue[300]),
                title: Text('Reload User Data',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _refreshUserData();
                },
              ),
              ListTile(
                leading: Icon(Icons.restart_alt, color: Colors.red[300]),
                title:
                    Text('Reset Chat', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _resetConversation();
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: TextStyle(color: Colors.grey[400])),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // Removed the App Bar section
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message["role"] == "user";
                    final isError = message["role"] == "error";
                    final isSystem = message["role"] == "system";
                    final isMealSuggestion =
                        message["role"] == "meal_suggestion";
                    final isRecipe = message["role"] == "recipe";
                    final isNutritionalInfo =
                        message["role"] == "nutritional_info";

                    if (isMealSuggestion) {
                      try {
                        final mealData =
                            message["content"] as Map<String, dynamic>;

                        // Validate that the meal data has the required fields
                        if (mealData['meal_name'] == null) {
                          throw FormatException(
                              'Invalid meal data: missing meal_name');
                        }

                        return Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          child: MealSuggestionContainer(
                            mealData: mealData,
                            onAdded: _refreshUserData,
                          ),
                        );
                      } catch (e) {
                        // Log the error and show an error message instead
                        debugPrint('Error rendering meal suggestion: $e');
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[900],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Error: Invalid meal data format',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }
                    }

                    if (isRecipe) {
                      try {
                        final recipeData =
                            message["content"] as Map<String, dynamic>;

                        // Validate that the recipe data has the required fields
                        if (recipeData['recipe_name'] == null) {
                          throw FormatException(
                              'Invalid recipe data: missing recipe_name');
                        }

                        return Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          child: RecipeContainer(
                            recipeData: recipeData,
                          ),
                        );
                      } catch (e) {
                        // Log the error and show an error message instead
                        debugPrint('Error rendering recipe: $e');
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[900],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Error: Invalid recipe data format',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }
                    }

                    // Add handling for nutritional info
                    if (isNutritionalInfo) {
                      try {
                        final infoData =
                            message["content"] as Map<String, dynamic>;

                        // Validate that the nutritional info has the required fields
                        if (infoData['meal_name'] == null) {
                          throw FormatException(
                              'Invalid nutritional info: missing meal_name');
                        }

                        // Use the same MealSuggestionContainer for nutritional info
                        return Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          child: MealSuggestionContainer(
                            mealData: infoData,
                            onAdded: _refreshUserData,
                          ),
                        );
                      } catch (e) {
                        // Log the error and show an error message instead
                        debugPrint('Error rendering nutritional info: $e');
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.85,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[900],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Error: Invalid nutritional info format',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }
                    }

                    // Handle regular messages with error checking
                    try {
                      final content = message["content"];
                      final messageText =
                          content is String ? content : content.toString();

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isError
                                ? Colors.red[900]
                                : isSystem
                                    ? Colors.green[800]
                                    : isUser
                                        ? Colors.blue[800]
                                        : Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            messageText,
                            style: TextStyle(
                              color: isError
                                  ? Colors.red[200]
                                  : isSystem
                                      ? Colors.green[100]
                                      : Colors.white,
                            ),
                          ),
                        ),
                      );
                    } catch (e) {
                      // Fallback for any message rendering errors
                      debugPrint('Error rendering message: $e');
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[900],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Error displaying message: $e',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              // Updated input area with settings button and expandable text field
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Settings button

                    // Expandable text field
                    Expanded(
                      child: Container(
                        height: _currentTextFieldHeight,
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageNode,
                          autofocus: false,
                          style: const TextStyle(color: Colors.white),
                          maxLines: null, // Allow unlimited lines
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[800],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showSettingsMenu(context),
                      icon: Icon(Icons.settings, color: Colors.grey[400]),
                      tooltip: 'Settings',
                    ),
                    const SizedBox(width: 4),
                    // Send button
                    IconButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      icon: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
