//
//  MockData.swift
//  Static fixtures used by every Slice 0.5 mock view. These represent
//  Carlos's day — one of the three test accounts from the backend seed
//  (carlos@fittracker.dev). Realistic values so screens never look empty.
//

import Foundation

enum MockData {

    // Stable UUIDs so views can cross-reference (e.g. meal plan referring to product).
    // Hex-only UUIDs (0-9, a-f). "user", "food", "exer", "prog" prefixes
    // act as readable namespaces in DEBUG logs.
    private static let _carlosID    = UUID(uuidString: "00000000-0000-0000-0000-000000C00001")!
    private static let _oatmealID   = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
    private static let _eggsID      = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!
    private static let _chickenID   = UUID(uuidString: "00000000-0000-0000-0000-00000000F003")!
    private static let _riceID      = UUID(uuidString: "00000000-0000-0000-0000-00000000F004")!
    private static let _broccoliID  = UUID(uuidString: "00000000-0000-0000-0000-00000000F005")!
    private static let _greekYogurtID = UUID(uuidString: "00000000-0000-0000-0000-00000000F006")!
    private static let _bananaID    = UUID(uuidString: "00000000-0000-0000-0000-00000000F007")!
    private static let _tunaID      = UUID(uuidString: "00000000-0000-0000-0000-00000000F008")!
    private static let _almondID    = UUID(uuidString: "00000000-0000-0000-0000-00000000F009")!
    private static let _avocadoID   = UUID(uuidString: "00000000-0000-0000-0000-00000000F00a")!

    // MARK: - Users

    static let user = MockUser(
        id: _carlosID,
        email: "test1@fittracker.dev",
        displayName: "Carlos",
        createdAt: Date(timeIntervalSince1970: 1_770_000_000)
    )

    /// Quick-pick buttons in LoginView use these. Emails MUST match the
    /// backend's `seed_test_accounts.py` so production-mode login finds
    /// the seeded users. Password for all three: test1234.
    static let testAccounts: [MockUser] = [
        user,
        MockUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000C00002")!,
                 email: "test2@fittracker.dev", displayName: "María",
                 createdAt: Date(timeIntervalSince1970: 1_770_000_000)),
        MockUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000C00003")!,
                 email: "test3@fittracker.dev", displayName: "Roberto",
                 createdAt: Date(timeIntervalSince1970: 1_770_000_000))
    ]

    static let profile = UserProfile(
        weightKg: 78,
        heightCm: 178,
        age: 30,
        sex: .male,
        activity: .moderate
    )

    static let goal = NutritionGoal(
        dailyCalories: 2400,
        proteinG: 180,
        carbsG: 270,
        fatG: 70,
        fiberG: 35
    )

    // MARK: - Products

    static let products: [Product] = [
        Product(id: _oatmealID, barcode: "7501055302345", name: "Avena tradicional", brand: "Quaker",
                servingSizeG: 40, caloriesPerServing: 150, proteinG: 5, carbsG: 27, fatG: 3, fiberG: 4, category: "Grano"),
        Product(id: _eggsID, barcode: "7501030480012", name: "Huevos blancos", brand: "Bachoco",
                servingSizeG: 50, caloriesPerServing: 70, proteinG: 6, carbsG: 0.5, fatG: 5, fiberG: 0, category: "Proteína"),
        Product(id: _chickenID, barcode: nil, name: "Pechuga de pollo", brand: nil,
                servingSizeG: 100, caloriesPerServing: 165, proteinG: 31, carbsG: 0, fatG: 3.6, fiberG: 0, category: "Proteína"),
        Product(id: _riceID, barcode: "7501020551234", name: "Arroz integral cocido", brand: "Verde Valle",
                servingSizeG: 100, caloriesPerServing: 112, proteinG: 2.6, carbsG: 23, fatG: 0.9, fiberG: 1.8, category: "Grano"),
        Product(id: _broccoliID, barcode: nil, name: "Brócoli al vapor", brand: nil,
                servingSizeG: 100, caloriesPerServing: 35, proteinG: 2.4, carbsG: 7, fatG: 0.4, fiberG: 3.3, category: "Verdura"),
        Product(id: _greekYogurtID, barcode: "7501025451000", name: "Yogur griego natural", brand: "Danone",
                servingSizeG: 170, caloriesPerServing: 100, proteinG: 17, carbsG: 6, fatG: 0.7, fiberG: 0, category: "Lácteo"),
        Product(id: _bananaID, barcode: nil, name: "Plátano", brand: nil,
                servingSizeG: 118, caloriesPerServing: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4, fiberG: 3.1, category: "Fruta"),
        Product(id: _tunaID, barcode: "7501061452399", name: "Atún en agua", brand: "Dolores",
                servingSizeG: 85, caloriesPerServing: 90, proteinG: 20, carbsG: 0, fatG: 1, fiberG: 0, category: "Proteína"),
        Product(id: _almondID, barcode: nil, name: "Almendras", brand: nil,
                servingSizeG: 28, caloriesPerServing: 164, proteinG: 6, carbsG: 6, fatG: 14, fiberG: 3.5, category: "Snack"),
        Product(id: _avocadoID, barcode: nil, name: "Aguacate", brand: nil,
                servingSizeG: 100, caloriesPerServing: 160, proteinG: 2, carbsG: 9, fatG: 15, fiberG: 7, category: "Fruta")
    ]

    // MARK: - Meals (today)

    private static func _mealItem(_ product: Product, servings: Double) -> MealItem {
        MealItem(
            id: UUID(),
            productId: product.id,
            productName: product.name,
            brand: product.brand,
            servings: servings,
            calories: product.caloriesPerServing * servings,
            proteinG: product.proteinG * servings,
            carbsG: product.carbsG * servings,
            fatG: product.fatG * servings
        )
    }

    static let meals: [Meal] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let p = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return [
            Meal(id: UUID(), mealType: .breakfast,
                 mealDate: cal.date(byAdding: .hour, value: 7, to: today)!,
                 items: [
                    _mealItem(p[_oatmealID]!, servings: 1.5),
                    _mealItem(p[_bananaID]!, servings: 1),
                    _mealItem(p[_greekYogurtID]!, servings: 1)
                 ]),
            Meal(id: UUID(), mealType: .lunch,
                 mealDate: cal.date(byAdding: .hour, value: 13, to: today)!,
                 items: [
                    _mealItem(p[_chickenID]!, servings: 1.8),
                    _mealItem(p[_riceID]!, servings: 1.5),
                    _mealItem(p[_broccoliID]!, servings: 1.5),
                    _mealItem(p[_avocadoID]!, servings: 0.5)
                 ]),
            Meal(id: UUID(), mealType: .snack,
                 mealDate: cal.date(byAdding: .hour, value: 16, to: today)!,
                 items: [
                    _mealItem(p[_almondID]!, servings: 1),
                    _mealItem(p[_bananaID]!, servings: 1)
                 ]),
            Meal(id: UUID(), mealType: .dinner,
                 mealDate: cal.date(byAdding: .hour, value: 20, to: today)!,
                 items: [
                    _mealItem(p[_tunaID]!, servings: 1),
                    _mealItem(p[_riceID]!, servings: 1),
                    _mealItem(p[_broccoliID]!, servings: 1)
                 ])
        ]
    }()

    static var dailyNutrition: DailyNutrition {
        let total = meals.reduce(into: (cal: 0.0, p: 0.0, c: 0.0, f: 0.0)) { acc, meal in
            acc.cal += meal.totalCalories
            acc.p   += meal.totalProtein
            acc.c   += meal.totalCarbs
            acc.f   += meal.totalFat
        }
        return DailyNutrition(
            date: Calendar.current.startOfDay(for: Date()),
            calories: total.cal,
            proteinG: total.p,
            carbsG: total.c,
            fatG: total.f,
            fiberG: 22
        )
    }

    // MARK: - Meal plan

    static let mealPlan: MealPlan = {
        let weekStart = Calendar.current.startOfDay(for: Date())
        let items = (0..<7).flatMap { day -> [MealPlanItem] in
            [
                MealPlanItem(id: UUID(), dayIndex: day, mealType: .breakfast,
                             productName: ["Avena con plátano", "Huevos revueltos", "Yogur griego con miel"][day % 3],
                             servings: 1),
                MealPlanItem(id: UUID(), dayIndex: day, mealType: .lunch,
                             productName: ["Pollo + arroz", "Atún + ensalada", "Pollo + brócoli"][day % 3],
                             servings: 1),
                MealPlanItem(id: UUID(), dayIndex: day, mealType: .dinner,
                             productName: ["Salmón + camote", "Pechuga + verduras", "Tilapia + quinoa"][day % 3],
                             servings: 1)
            ]
        }
        return MealPlan(id: UUID(), weekStartDate: weekStart, items: items)
    }()

    // MARK: - Shopping list

    static let shoppingList: [ShoppingItem] = [
        ShoppingItem(id: UUID(), name: "Plátano",       quantity: "7 piezas",  category: .produce, checked: false),
        ShoppingItem(id: UUID(), name: "Brócoli",       quantity: "2 manojos", category: .produce, checked: true),
        ShoppingItem(id: UUID(), name: "Aguacate",      quantity: "4 piezas",  category: .produce, checked: false),
        ShoppingItem(id: UUID(), name: "Yogur griego",  quantity: "1 kg",      category: .dairy,   checked: false),
        ShoppingItem(id: UUID(), name: "Pechuga de pollo", quantity: "1.5 kg", category: .proteins, checked: false),
        ShoppingItem(id: UUID(), name: "Atún en agua",  quantity: "4 latas",   category: .proteins, checked: true),
        ShoppingItem(id: UUID(), name: "Huevos",        quantity: "12 piezas", category: .proteins, checked: false),
        ShoppingItem(id: UUID(), name: "Avena",         quantity: "500 g",     category: .grains,   checked: false),
        ShoppingItem(id: UUID(), name: "Arroz integral",quantity: "1 kg",      category: .grains,   checked: false),
        ShoppingItem(id: UUID(), name: "Almendras",     quantity: "200 g",     category: .pantry,   checked: false)
    ]

    // MARK: - Exercises

    private static let _benchID    = UUID(uuidString: "00000000-0000-0000-0000-0000000E0001")!
    private static let _squatID    = UUID(uuidString: "00000000-0000-0000-0000-0000000E0002")!
    private static let _deadliftID = UUID(uuidString: "00000000-0000-0000-0000-0000000E0003")!
    private static let _ohpID      = UUID(uuidString: "00000000-0000-0000-0000-0000000E0004")!
    private static let _rowID      = UUID(uuidString: "00000000-0000-0000-0000-0000000E0005")!
    private static let _pulldownID = UUID(uuidString: "00000000-0000-0000-0000-0000000E0006")!
    private static let _curlID     = UUID(uuidString: "00000000-0000-0000-0000-0000000E0007")!
    private static let _pushdownID = UUID(uuidString: "00000000-0000-0000-0000-0000000E0008")!
    private static let _legPressID = UUID(uuidString: "00000000-0000-0000-0000-0000000E0009")!
    private static let _plankID    = UUID(uuidString: "00000000-0000-0000-0000-0000000E000a")!
    private static let _lateralID  = UUID(uuidString: "00000000-0000-0000-0000-0000000E000b")!
    private static let _legCurlID  = UUID(uuidString: "00000000-0000-0000-0000-0000000E000c")!

    static let exercises: [Exercise] = [
        Exercise(id: _benchID, name: "Press de banca",
                 primaryMuscle: .chest, secondaryMuscles: [.shoulders, .arms],
                 equipment: .barbell, difficulty: .intermediate, videoURL: nil),
        Exercise(id: _squatID, name: "Sentadilla con barra",
                 primaryMuscle: .legs, secondaryMuscles: [.core],
                 equipment: .barbell, difficulty: .intermediate, videoURL: nil),
        Exercise(id: _deadliftID, name: "Peso muerto",
                 primaryMuscle: .back, secondaryMuscles: [.legs, .core],
                 equipment: .barbell, difficulty: .advanced, videoURL: nil),
        Exercise(id: _ohpID, name: "Press militar",
                 primaryMuscle: .shoulders, secondaryMuscles: [.arms, .core],
                 equipment: .barbell, difficulty: .intermediate, videoURL: nil),
        Exercise(id: _rowID, name: "Remo con barra",
                 primaryMuscle: .back, secondaryMuscles: [.arms],
                 equipment: .barbell, difficulty: .intermediate, videoURL: nil),
        Exercise(id: _pulldownID, name: "Jalón al pecho",
                 primaryMuscle: .back, secondaryMuscles: [.arms],
                 equipment: .cable, difficulty: .beginner, videoURL: nil),
        Exercise(id: _curlID, name: "Curl de bíceps",
                 primaryMuscle: .arms, secondaryMuscles: [],
                 equipment: .dumbbell, difficulty: .beginner, videoURL: nil),
        Exercise(id: _pushdownID, name: "Extensión de tríceps",
                 primaryMuscle: .arms, secondaryMuscles: [],
                 equipment: .cable, difficulty: .beginner, videoURL: nil),
        Exercise(id: _legPressID, name: "Prensa de piernas",
                 primaryMuscle: .legs, secondaryMuscles: [],
                 equipment: .machine, difficulty: .beginner, videoURL: nil),
        Exercise(id: _plankID, name: "Plancha",
                 primaryMuscle: .core, secondaryMuscles: [.shoulders],
                 equipment: .bodyweight, difficulty: .beginner, videoURL: nil),
        Exercise(id: _lateralID, name: "Elevaciones laterales",
                 primaryMuscle: .shoulders, secondaryMuscles: [],
                 equipment: .dumbbell, difficulty: .beginner, videoURL: nil),
        Exercise(id: _legCurlID, name: "Curl femoral",
                 primaryMuscle: .legs, secondaryMuscles: [],
                 equipment: .machine, difficulty: .beginner, videoURL: nil)
    ]

    // MARK: - Programs

    static let programs: [WorkoutProgram] = [
        WorkoutProgram(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!,
            name: "PPL — Push / Pull / Legs",
            summary: "6 días, dividido por movimiento. Ideal para volumen.",
            daysPerWeek: 6, difficulty: .intermediate,
            days: [
                WorkoutProgramDay(id: UUID(), dayName: "Push",
                                  exercises: _spec(_benchID, "Press de banca", 4, 6, 8, 120) +
                                             _spec(_ohpID, "Press militar", 3, 8, 10, 90) +
                                             _spec(_lateralID, "Elevaciones laterales", 3, 12, 15, 60) +
                                             _spec(_pushdownID, "Extensión de tríceps", 3, 10, 12, 60)),
                WorkoutProgramDay(id: UUID(), dayName: "Pull",
                                  exercises: _spec(_deadliftID, "Peso muerto", 3, 5, 6, 180) +
                                             _spec(_rowID, "Remo con barra", 4, 8, 10, 90) +
                                             _spec(_pulldownID, "Jalón al pecho", 3, 10, 12, 60) +
                                             _spec(_curlID, "Curl de bíceps", 3, 10, 12, 60)),
                WorkoutProgramDay(id: UUID(), dayName: "Legs",
                                  exercises: _spec(_squatID, "Sentadilla con barra", 4, 6, 8, 150) +
                                             _spec(_legPressID, "Prensa de piernas", 3, 10, 12, 90) +
                                             _spec(_legCurlID, "Curl femoral", 3, 12, 15, 60) +
                                             _spec(_plankID, "Plancha", 3, 30, 60, 45))
            ]
        ),
        WorkoutProgram(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!,
            name: "Upper / Lower",
            summary: "4 días, balance entre fuerza y volumen.",
            daysPerWeek: 4, difficulty: .intermediate,
            days: []
        ),
        WorkoutProgram(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!,
            name: "Full Body 3x",
            summary: "3 días para principiantes, frecuencia alta.",
            daysPerWeek: 3, difficulty: .beginner,
            days: []
        ),
        WorkoutProgram(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B004")!,
            name: "5/3/1 BBB",
            summary: "Fuerza máxima + accesorios de volumen (Wendler).",
            daysPerWeek: 4, difficulty: .advanced,
            days: []
        )
    ]

    private static func _spec(_ exId: UUID, _ name: String, _ sets: Int,
                              _ low: Int, _ high: Int, _ rest: Int) -> [WorkoutProgramExerciseSpec] {
        [WorkoutProgramExerciseSpec(id: UUID(), exerciseId: exId, exerciseName: name,
                                    sets: sets, repsLow: low, repsHigh: high, restSeconds: rest)]
    }

    // MARK: - Workouts (sessions + sets)

    static let recentSessions: [WorkoutSession] = {
        let now = Date()
        let cal = Calendar.current
        return (0..<8).compactMap { weekOffset -> WorkoutSession? in
            guard let date = cal.date(byAdding: .day, value: -weekOffset * 2, to: now) else { return nil }
            let started = cal.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
            let completed = cal.date(byAdding: .minute, value: 65, to: started)
            return WorkoutSession(
                id: UUID(),
                startedAt: started,
                completedAt: completed,
                programName: "PPL",
                dayName: ["Push", "Pull", "Legs"][weekOffset % 3],
                sets: [
                    WorkoutSet(id: UUID(), exerciseId: _benchID, setNumber: 1, weightKg: 80, reps: 8, isPR: weekOffset == 0),
                    WorkoutSet(id: UUID(), exerciseId: _benchID, setNumber: 2, weightKg: 80, reps: 7, isPR: false),
                    WorkoutSet(id: UUID(), exerciseId: _benchID, setNumber: 3, weightKg: 80, reps: 6, isPR: false),
                    WorkoutSet(id: UUID(), exerciseId: _ohpID, setNumber: 1, weightKg: 50, reps: 8, isPR: false),
                    WorkoutSet(id: UUID(), exerciseId: _ohpID, setNumber: 2, weightKg: 50, reps: 7, isPR: false)
                ]
            )
        }
    }()

    static let personalRecords: [PersonalRecord] = [
        PersonalRecord(id: UUID(), exerciseId: _benchID, exerciseName: "Press de banca",
                       weightKg: 100, reps: 5,
                       achievedAt: Date(timeIntervalSinceNow: -86400 * 14)),
        PersonalRecord(id: UUID(), exerciseId: _squatID, exerciseName: "Sentadilla con barra",
                       weightKg: 140, reps: 5,
                       achievedAt: Date(timeIntervalSinceNow: -86400 * 9)),
        PersonalRecord(id: UUID(), exerciseId: _deadliftID, exerciseName: "Peso muerto",
                       weightKg: 170, reps: 3,
                       achievedAt: Date(timeIntervalSinceNow: -86400 * 21)),
        PersonalRecord(id: UUID(), exerciseId: _ohpID, exerciseName: "Press militar",
                       weightKg: 60, reps: 6,
                       achievedAt: Date(timeIntervalSinceNow: -86400 * 7))
    ]
}
