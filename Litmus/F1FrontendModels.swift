// Frontend model types taken from the Prototype MVP (Models.swift) so the F1 views build in this target.
import SwiftUI
import Foundation

public enum StudentCountry: String, CaseIterable, Identifiable, Codable, Sendable {
    case india = "🇮🇳 India (PARAKH)"
    case usa = "🇺🇸 USA (NGSS)"
    case international = "🌍 International (IB)"
    
    public var id: String { rawValue }
    
    public var frameworkName: String {
        switch self {
        case .india: return "PARAKH"
        case .usa: return "NGSS"
        case .international: return "IB"
        }
    }
    
    public var pillar1Title: String {
        switch self {
        case .india: return "PARAKH: Core Concept"
        case .usa: return "NGSS: Core Idea (DCI)"
        case .international: return "IB: Knowing & Understanding"
        }
    }
    
    public var pillar2Title: String {
        switch self {
        case .india: return "PARAKH: Cause & Effect"
        case .usa: return "NGSS: Cause & Effect (CCC)"
        case .international: return "IB: Application & Reasoning"
        }
    }
}

extension StudentCountry {
    public static func from(nationality: String) -> StudentCountry {
        let lower = nationality.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("cbse") || lower.contains("icse") || lower.contains("india") || lower.contains("indian") || lower.contains("parakh") || lower == "in" {
            return .india
        } else if lower.contains("ngss") || lower.contains("usa") || lower.contains("united states") || lower.contains("america") || lower == "us" {
            return .usa
        } else {
            return .international
        }
    }
}

public struct F1Theme {
    /// Official F1 Racing Red (#E10600 / #E10800)
    public static let racingRed = Color(red: 225/255, green: 6/255, blue: 0/255)
    public static let racingRedGlow = Color(red: 255/255, green: 24/255, blue: 1/255)
    
    /// Official F1 Website Deep Carbon Canvas (#0E0E10 / #0A0A0C) - Neutral, ZERO blue tint
    public static let trackAsphalt = Color(red: 14/255, green: 14/255, blue: 16/255)
    public static let carbonBlack = Color(red: 10/255, green: 10/255, blue: 12/255)
    
    /// Official F1 Website Card Base (#131316) - Deep Graphite Carbon
    public static let cardSurface = Color(red: 19/255, green: 19/255, blue: 22/255)
    
    /// Official F1 Website Diagonal Carbon Stripe Highlight (#19191C)
    public static let carbonStripe = Color(red: 25/255, green: 25/255, blue: 28/255)
    public static let cardBorder = Color.white.opacity(0.08)
    
    /// Timing & Telemetry Colors
    public static let sectorPurple = Color(red: 177/255, green: 56/255, blue: 221/255) // Fastest Lap (#B138DD)
    public static let sectorGreen = Color(red: 0/255, green: 215/255, blue: 85/255)  // Personal Best (#00D755) - True Motorsport Green
    public static let sectorYellow = Color(red: 255/255, green: 235/255, blue: 0/255) // Caution / Delta (#FFEB00)
    public static let speedTrapGold = Color(red: 255/255, green: 215/255, blue: 0/255) // Speed Trap (#FFD700)
    
    /// Official F1 High-Contrast Typography Colors
    public static let pureWhite = Color.white
    public static let typographyYellow = Color(red: 255/255, green: 215/255, blue: 0/255) // Official Motorsport Yellow (#FFD700)
    public static let textSecondary = Color(red: 160/255, green: 160/255, blue: 164/255) // High-contrast readable secondary
}

public struct LearnerUserProfile: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var age: Int
    public var academicYear: String
    public var curriculum: String
    public var nationality: String
    public var driverNumber: Int
    public var avatarSymbol: String
    public var avatarColor: Color
    public var pilotRank: String
    public var coins: Int
    public var xp: Int
    public var totalFlights: Int

    public init(
        id: UUID = UUID(),
        name: String,
        age: Int = 14,
        academicYear: String = "Grade 10",
        curriculum: String = "CBSE",
        nationality: String = "India",
        driverNumber: Int = 24,
        avatarSymbol: String = "person.crop.circle.fill",
        avatarColor: Color = F1Theme.racingRed,
        pilotRank: String = "Grade 10 • CBSE",
        coins: Int = 5,
        xp: Int = 340,
        totalFlights: Int = 42
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.academicYear = academicYear
        self.curriculum = curriculum
        self.nationality = nationality
        self.driverNumber = driverNumber
        self.avatarSymbol = avatarSymbol
        self.avatarColor = avatarColor
        self.pilotRank = "\(academicYear) • \(curriculum)"
        self.coins = coins
        self.xp = xp
        self.totalFlights = totalFlights
    }

    public var ageProfile: LearnerAgeProfile {
        LearnerAgeProfile(age: age)
    }

    public var driverRank: String {
        "\(academicYear) • \(curriculum)"
    }

    public var totalLaps: Int {
        get { totalFlights }
        set { totalFlights = newValue }
    }

    public var totalStudyHours: Double {
        max(14.5, Double(totalFlights) * 0.45)
    }

    public var badgesCount: Int {
        F1SessionProgressManager.shared.badgesCount
    }
}

public struct F1RaceEngineer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let shortName: String
    public let driverNumber: String
    public let team: String
    public let teamColor: Color
    public let teamLiveryHex: String
    public let helmetIcon: String
    public let coachingPersona: String
    public let coachingStyle: String
    public let radioCallsign: String
    public let defaultRadioPrompt: String
    public let catchphrase: String

    public init(
        id: String,
        name: String,
        shortName: String,
        driverNumber: String,
        team: String,
        teamColor: Color,
        teamLiveryHex: String,
        helmetIcon: String,
        coachingPersona: String,
        coachingStyle: String,
        radioCallsign: String,
        defaultRadioPrompt: String,
        catchphrase: String
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.driverNumber = driverNumber
        self.team = team
        self.teamColor = teamColor
        self.teamLiveryHex = teamLiveryHex
        self.helmetIcon = helmetIcon
        self.coachingPersona = coachingPersona
        self.coachingStyle = coachingStyle
        self.radioCallsign = radioCallsign
        self.defaultRadioPrompt = defaultRadioPrompt
        self.catchphrase = catchphrase
    }
    
    public var coachingQuote: String {
        catchphrase
    }
}
public let sampleLearnerProfiles: [LearnerUserProfile] = [
    LearnerUserProfile(
        name: "Leo",
        age: 15,
        academicYear: "Grade 10",
        curriculum: "CBSE",
        nationality: "India",
        driverNumber: 24,
        avatarSymbol: "person.crop.circle.fill",
        avatarColor: F1Theme.racingRed,
        pilotRank: "Grade 10 • CBSE",
        coins: 5,
        xp: 340,
        totalFlights: 42
    ),
    LearnerUserProfile(
        name: "Aarushi",
        age: 14,
        academicYear: "Grade 9",
        curriculum: "CBSE",
        nationality: "India",
        driverNumber: 13,
        avatarSymbol: "person.crop.circle.fill",
        avatarColor: F1Theme.racingRed,
        pilotRank: "Grade 9 • CBSE",
        coins: 5,
        xp: 520,
        totalFlights: 58
    ),
    LearnerUserProfile(
        name: "Maya",
        age: 13,
        academicYear: "Grade 8",
        curriculum: "CBSE",
        nationality: "India",
        driverNumber: 44,
        avatarSymbol: "person.crop.circle.fill",
        avatarColor: Color.mint,
        pilotRank: "Grade 8 • CBSE",
        coins: 5,
        xp: 180,
        totalFlights: 18
    ),
    LearnerUserProfile(
        name: "Sam",
        age: 12,
        academicYear: "Grade 7",
        curriculum: "CBSE",
        nationality: "India",
        driverNumber: 81,
        avatarSymbol: "person.crop.circle.fill",
        avatarColor: Color.purple,
        pilotRank: "Grade 7 • CBSE",
        coins: 5,
        xp: 620,
        totalFlights: 76
    ),
    LearnerUserProfile(
        name: "Elena",
        age: 16,
        academicYear: "Year 11",
        nationality: "Italy",
        driverNumber: 16,
        avatarSymbol: "person.crop.circle.fill",
        avatarColor: Color.blue,
        pilotRank: "World Champion",
        xp: 1250,
        totalFlights: 140
    )
]

public let sampleRaceEngineers: [F1RaceEngineer] = [
    F1RaceEngineer(
        id: "hamilton",
        name: "Lewis Hamilton",
        shortName: "HAM",
        driverNumber: "44",
        team: "Mercedes-AMG Petronas",
        teamColor: Color(red: 0/255, green: 210/255, blue: 190/255),
        teamLiveryHex: "00D2BE",
        helmetIcon: "crown.fill",
        coachingPersona: "Hammer Time Focus",
        coachingStyle: "Deep calm concentration, surgical breathing, and relentless discipline.",
        radioCallsign: "Bono / Lewis",
        defaultRadioPrompt: "Radio check: keep your head down, manage your cognitive tyres, and hit every conceptual apex.",
        catchphrase: "Still We Rise • Maximum Focus"
    ),
    F1RaceEngineer(
        id: "verstappen",
        name: "Max Verstappen",
        shortName: "VER",
        driverNumber: "1",
        team: "Red Bull Racing",
        teamColor: Color(red: 54/255, green: 113/255, blue: 198/255),
        teamLiveryHex: "3671C6",
        helmetIcon: "bolt.fill",
        coachingPersona: "Aggressive Telemetry",
        coachingStyle: "Direct first-principles attack. No fluff, full throttle clarity, and apex precision.",
        radioCallsign: "GP / Max",
        defaultRadioPrompt: "The telemetry looks clear. Attack the hardest question first. Full send into Sector 1.",
        catchphrase: "Simply Lovely • Full Attack"
    ),
    F1RaceEngineer(
        id: "leclerc",
        name: "Charles Leclerc",
        shortName: "LEC",
        driverNumber: "16",
        team: "Scuderia Ferrari",
        teamColor: Color(red: 232/255, green: 0/255, blue: 45/255),
        teamLiveryHex: "E8002D",
        helmetIcon: "flame.fill",
        coachingPersona: "Passionate Precision",
        coachingStyle: "High-tempo analytical rigor, deep mathematical passion, and sector perfection.",
        radioCallsign: "Bryan / Charles",
        defaultRadioPrompt: "Telemetry confirm. We are checking the concept models. You are P1 on cognitive pace.",
        catchphrase: "Forza • Precision Apex"
    ),
    F1RaceEngineer(
        id: "alonso",
        name: "Fernando Alonso",
        shortName: "ALO",
        driverNumber: "14",
        team: "Aston Martin Aramco",
        teamColor: Color(red: 34/255, green: 153/255, blue: 113/255),
        teamLiveryHex: "229971",
        helmetIcon: "shield.fill",
        coachingPersona: "Master Tactician",
        coachingStyle: "Stamina pacing, ruthless energy conservation, and strategic endurance.",
        radioCallsign: "Mike / Fernando",
        defaultRadioPrompt: "Always leave the space for first principles. Manage the lap pace and we take victory.",
        catchphrase: "Always Leave The Space"
    ),
    F1RaceEngineer(
        id: "norris",
        name: "Lando Norris",
        shortName: "NOR",
        driverNumber: "4",
        team: "McLaren Formula 1",
        teamColor: Color(red: 255/255, green: 128/255, blue: 0/255),
        teamLiveryHex: "FF8000",
        helmetIcon: "sparkles",
        coachingPersona: "Iterative High Energy",
        coachingStyle: "Rapid problem deconstruction, high dopamine, and smooth intuitive breakdown.",
        radioCallsign: "Will / Lando",
        defaultRadioPrompt: "Let's cook! Deconstruct this concept into bite-sized corners and nail the exit speed.",
        catchphrase: "Smooth Operator • Let's Cook"
    )
]


public struct FlashcardItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let content: String
    public let highlightedTerms: [String]
    public let promptQuestion: String
    
    public init(
        id: String,
        title: String,
        content: String,
        highlightedTerms: [String] = [],
        promptQuestion: String = ""
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.highlightedTerms = highlightedTerms
        self.promptQuestion = promptQuestion.isEmpty ? "What is the core principle behind \(title)?" : promptQuestion
    }
}

public struct ReviseChapter: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let subject: String
    public let imageName: String
    public let cardCount: Int
    public let cards: [FlashcardItem]
    public let dueBadge: String
    public let intervalDays: Int
    
    public init(
        id: String,
        title: String,
        subject: String,
        imageName: String,
        cardCount: Int,
        cards: [FlashcardItem],
        dueBadge: String = "DUE TODAY",
        intervalDays: Int = 1
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.imageName = imageName
        self.cardCount = cardCount
        self.cards = cards
        self.dueBadge = dueBadge
        self.intervalDays = intervalDays
    }
}

public struct F1Circuit: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var trackNameLine1: String
    public var trackNameLine2: String
    public var location: String
    public var countryFlag: String
    public var lapLengthKm: Double
    public var cornersCount: Int
    public var speedTrapPosition: Double
    public var speedTrapLabel: String
    public var lapRecordTime: String
    public var lapRecordHolder: String
    public var grandPrixLaps: Int
    public var firstGrandPrixYear: Int
    public var drsZonesCount: Int
    public var elevationDeltaMeters: Double
    public var topSpeedRecordKmh: Int
    public var cornerNodes: [F1CornerNode]
    public var sectors: [F1TrackSector]

    public init(
        id: String,
        name: String,
        trackNameLine1: String,
        trackNameLine2: String,
        location: String,
        countryFlag: String,
        lapLengthKm: Double,
        cornersCount: Int,
        speedTrapPosition: Double = 0.22,
        speedTrapLabel: String = "354 km/h",
        lapRecordTime: String = "1:17.774",
        lapRecordHolder: String = "Valtteri Bottas (2021)",
        grandPrixLaps: Int = 71,
        firstGrandPrixYear: Int = 1963,
        drsZonesCount: Int = 3,
        elevationDeltaMeters: Double = 2.8,
        topSpeedRecordKmh: Int = 354,
        cornerNodes: [F1CornerNode] = [],
        sectors: [F1TrackSector]
    ) {
        self.id = id
        self.name = name
        self.trackNameLine1 = trackNameLine1
        self.trackNameLine2 = trackNameLine2
        self.location = location
        self.countryFlag = countryFlag
        self.lapLengthKm = lapLengthKm
        self.cornersCount = cornersCount
        self.speedTrapPosition = speedTrapPosition
        self.speedTrapLabel = speedTrapLabel
        self.lapRecordTime = lapRecordTime
        self.lapRecordHolder = lapRecordHolder
        self.grandPrixLaps = grandPrixLaps
        self.firstGrandPrixYear = firstGrandPrixYear
        self.drsZonesCount = drsZonesCount
        self.elevationDeltaMeters = elevationDeltaMeters
        self.topSpeedRecordKmh = topSpeedRecordKmh
        self.cornerNodes = cornerNodes
        self.sectors = sectors
    }

    public var shortCode: String {
        switch id {
        case "mexico_city": return "MEX"
        case "silverstone": return "GBR"
        case "spa": return "BEL"
        case "monaco": return "MON"
        default: return "GP"
        }
    }

    public static let autodromoHermanosRodriguez = F1Circuit(
        id: "mexico_city",
        name: "Autódromo Hermanos Rodríguez",
        trackNameLine1: "Autódromo",
        trackNameLine2: "Hermanos Rodríguez",
        location: "Mexico City",
        countryFlag: "🇲🇽",
        lapLengthKm: 4.304,
        cornersCount: 17,
        speedTrapPosition: 0.22,
        speedTrapLabel: "354 km/h Speed Trap",
        lapRecordTime: "1:17.774",
        lapRecordHolder: "Valtteri Bottas (2021)",
        grandPrixLaps: 71,
        firstGrandPrixYear: 1963,
        drsZonesCount: 3,
        elevationDeltaMeters: 2.8,
        topSpeedRecordKmh: 354,
        cornerNodes: [
            F1CornerNode(turnNumber: 1, name: "Moisés Solana Apex", gear: 3, apexSpeedKmh: 138, gForce: 4.2, cognitivePhase: "Concept Intake Prime", normalizedPosition: 0.24),
            F1CornerNode(turnNumber: 4, name: "Nigel Mansell Turn", gear: 2, apexSpeedKmh: 85, gForce: 3.8, cognitivePhase: "Baseline Definitions", normalizedPosition: 0.38),
            F1CornerNode(turnNumber: 8, name: "Technical Esses Flow", gear: 6, apexSpeedKmh: 240, gForce: 4.8, cognitivePhase: "Feynman Translation", normalizedPosition: 0.52),
            F1CornerNode(turnNumber: 12, name: "Foro Sol Stadium Entry", gear: 1, apexSpeedKmh: 68, gForce: 2.9, cognitivePhase: "Application & Pressure", normalizedPosition: 0.78),
            F1CornerNode(turnNumber: 17, name: "Peraltada High Velocity", gear: 7, apexSpeedKmh: 265, gForce: 4.1, cognitivePhase: "Race Pace Mastery", normalizedPosition: 0.94)
        ],
        sectors: [
            F1TrackSector(
                id: 1,
                name: "Sector 1 (Main Straight & Turns 1-3)",
                studyPhase: "Concept Intake & Core Mental Models",
                description: "Absorb prime formulas, baseline definitions, and core intuition.",
                normalizedRange: 0.0...0.33,
                iconName: "bolt.fill",
                colorHex: "E10600"
            ),
            F1TrackSector(
                id: 2,
                name: "Sector 2 (Technical Esses & Hairpin)",
                studyPhase: "The Feynman Translation",
                description: "Synthesize and explain concepts simply without technical jargon.",
                normalizedRange: 0.33...0.66,
                iconName: "waveform.path",
                colorHex: "FF8000"
            ),
            F1TrackSector(
                id: 3,
                name: "Sector 3 (Foro Sol Stadium & Peraltada)",
                studyPhase: "Application & Socratic Pressure",
                description: "High-stress problem solving under race pace conditions.",
                normalizedRange: 0.66...1.0,
                iconName: "flag.checkered",
                colorHex: "00D2BE"
            )
        ]
    )

    public static let silverstone = F1Circuit(
        id: "silverstone",
        name: "Silverstone Circuit",
        trackNameLine1: "Silverstone",
        trackNameLine2: "Circuit",
        location: "Northamptonshire, UK",
        countryFlag: "🇬🇧",
        lapLengthKm: 5.891,
        cornersCount: 18,
        speedTrapPosition: 0.45,
        speedTrapLabel: "328 km/h Hangar Straight",
        lapRecordTime: "1:27.097",
        lapRecordHolder: "Max Verstappen (2020)",
        grandPrixLaps: 52,
        firstGrandPrixYear: 1950,
        drsZonesCount: 2,
        elevationDeltaMeters: 11.3,
        topSpeedRecordKmh: 332,
        cornerNodes: [
            F1CornerNode(turnNumber: 1, name: "Abbey High-G Turn", gear: 7, apexSpeedKmh: 290, gForce: 4.9, cognitivePhase: "High Speed Intake", normalizedPosition: 0.12),
            F1CornerNode(turnNumber: 9, name: "Copse Flat-Out Apex", gear: 7, apexSpeedKmh: 285, gForce: 5.1, cognitivePhase: "Rapid Priming", normalizedPosition: 0.48),
            F1CornerNode(turnNumber: 11, name: "Maggotts & Becketts", gear: 6, apexSpeedKmh: 260, gForce: 5.4, cognitivePhase: "Technical Precision", normalizedPosition: 0.62),
            F1CornerNode(turnNumber: 15, name: "Stowe Braking Zone", gear: 5, apexSpeedKmh: 205, gForce: 4.5, cognitivePhase: "Complex Synthesis", normalizedPosition: 0.78),
            F1CornerNode(turnNumber: 16, name: "Vale Chicane Exit", gear: 2, apexSpeedKmh: 95, gForce: 3.2, cognitivePhase: "Tactical Execution", normalizedPosition: 0.88)
        ],
        sectors: [
            F1TrackSector(id: 1, name: "Sector 1 (Copse & Maggotts)", studyPhase: "High Speed Intake", description: "Rapid cognitive priming.", normalizedRange: 0.0...0.33),
            F1TrackSector(id: 2, name: "Sector 2 (Becketts & Chapel)", studyPhase: "Technical Precision", description: "Complex concept chaining.", normalizedRange: 0.33...0.66),
            F1TrackSector(id: 3, name: "Sector 3 (Stowe & Club)", studyPhase: "Tactical Execution", description: "Active recall and testing.", normalizedRange: 0.66...1.0)
        ]
    )

    public static let spaFrancorchamps = F1Circuit(
        id: "spa",
        name: "Circuit de Spa-Francorchamps",
        trackNameLine1: "Circuit de",
        trackNameLine2: "Spa-Francorchamps",
        location: "Stavelot, Belgium",
        countryFlag: "🇧🇪",
        lapLengthKm: 7.004,
        cornersCount: 19,
        speedTrapPosition: 0.28,
        speedTrapLabel: "345 km/h Kemmel Straight",
        lapRecordTime: "1:46.286",
        lapRecordHolder: "Valtteri Bottas (2018)",
        grandPrixLaps: 44,
        firstGrandPrixYear: 1950,
        drsZonesCount: 2,
        elevationDeltaMeters: 102.2,
        topSpeedRecordKmh: 348,
        cornerNodes: [
            F1CornerNode(turnNumber: 1, name: "La Source Hairpin", gear: 1, apexSpeedKmh: 72, gForce: 3.1, cognitivePhase: "First Insight", normalizedPosition: 0.08),
            F1CornerNode(turnNumber: 3, name: "Eau Rouge / Raidillon", gear: 7, apexSpeedKmh: 305, gForce: 5.2, cognitivePhase: "Vertical Cognitive Leap", normalizedPosition: 0.22),
            F1CornerNode(turnNumber: 8, name: "Bruxelles Hairpin", gear: 2, apexSpeedKmh: 110, gForce: 3.6, cognitivePhase: "Conceptual Flow", normalizedPosition: 0.50),
            F1CornerNode(turnNumber: 10, name: "Pouhon Double Apex", gear: 6, apexSpeedKmh: 290, gForce: 5.3, cognitivePhase: "High Endurance", normalizedPosition: 0.68),
            F1CornerNode(turnNumber: 19, name: "Bus Stop Chicane", gear: 2, apexSpeedKmh: 80, gForce: 4.0, cognitivePhase: "Validation & Debrief", normalizedPosition: 0.95)
        ],
        sectors: [
            F1TrackSector(id: 1, name: "Sector 1 (Eau Rouge & Raidillon)", studyPhase: "Vertical Cognitive Leap", description: "Tackling the hardest core insight first.", normalizedRange: 0.0...0.33),
            F1TrackSector(id: 2, name: "Sector 2 (Bruxelles & Pouhon)", studyPhase: "Continuous Flow", description: "Deep conceptual endurance.", normalizedRange: 0.33...0.66),
            F1TrackSector(id: 3, name: "Sector 3 (Blanchimont & Bus Stop)", studyPhase: "Final Sprint", description: "Feynman debrief and validation.", normalizedRange: 0.66...1.0)
        ]
    )

    public static let monaco = F1Circuit(
        id: "monaco",
        name: "Circuit de Monaco",
        trackNameLine1: "Circuit de",
        trackNameLine2: "Monaco",
        location: "Monte Carlo, Monaco",
        countryFlag: "🇲🇨",
        lapLengthKm: 3.337,
        cornersCount: 19,
        speedTrapPosition: 0.50,
        speedTrapLabel: "290 km/h Tunnel Exit",
        lapRecordTime: "1:12.909",
        lapRecordHolder: "Lewis Hamilton (2021)",
        grandPrixLaps: 78,
        firstGrandPrixYear: 1950,
        drsZonesCount: 1,
        elevationDeltaMeters: 42.0,
        topSpeedRecordKmh: 292,
        cornerNodes: [
            F1CornerNode(turnNumber: 1, name: "Sainte Dévote Apex", gear: 2, apexSpeedKmh: 105, gForce: 3.8, cognitivePhase: "Precision Focus", normalizedPosition: 0.15),
            F1CornerNode(turnNumber: 4, name: "Casino Square Apex", gear: 4, apexSpeedKmh: 160, gForce: 4.0, cognitivePhase: "Mental Model Mapping", normalizedPosition: 0.32),
            F1CornerNode(turnNumber: 6, name: "Grand Hotel Hairpin", gear: 1, apexSpeedKmh: 48, gForce: 2.2, cognitivePhase: "Granular Decomposition", normalizedPosition: 0.44),
            F1CornerNode(turnNumber: 10, name: "Nouvelle Chicane", gear: 2, apexSpeedKmh: 85, gForce: 4.4, cognitivePhase: "Deconstruct Problems", normalizedPosition: 0.65),
            F1CornerNode(turnNumber: 15, name: "Swimming Pool Esses", gear: 5, apexSpeedKmh: 215, gForce: 4.7, cognitivePhase: "Socratic Agility", normalizedPosition: 0.85)
        ],
        sectors: [
            F1TrackSector(id: 1, name: "Sector 1 (Sainte Dévote & Beau Rivage)", studyPhase: "Precision Focus", description: "Zero error margin initiation.", normalizedRange: 0.0...0.33),
            F1TrackSector(id: 2, name: "Sector 2 (Mirabeau & Grand Hotel)", studyPhase: "Granular Decomposition", description: "Deconstruct tight problems step-by-step.", normalizedRange: 0.33...0.66),
            F1TrackSector(id: 3, name: "Sector 3 (Swimming Pool & Rascasse)", studyPhase: "Socratic Precision", description: "High-speed mental agility.", normalizedRange: 0.66...1.0)
        ]
    )

    public static let allCircuits: [F1Circuit] = [
        .autodromoHermanosRodriguez,
        .silverstone,
        .spaFrancorchamps,
        .monaco
    ]
}

public enum TyreCompound: String, CaseIterable, Identifiable {
    case soft = "Soft (C5)"
    case medium = "Medium (C3)"
    case hard = "Hard (C1)"
    case intermediate = "Intermediate"
    case wet = "Full Wet"

    public var id: String { rawValue }
    public var name: String { rawValue }


    public var minutes: Int {
        switch self {
        case .soft: return 15
        case .medium: return 25
        case .hard: return 45
        case .intermediate: return 60
        case .wet: return 90
        }
    }

    public var shortCode: String {
        switch self {
        case .soft: return "S"
        case .medium: return "M"
        case .hard: return "H"
        case .intermediate: return "I"
        case .wet: return "W"
        }
    }

    public var compoundColor: Color {
        switch self {
        case .soft: return F1Theme.racingRed
        case .medium: return F1Theme.sectorYellow
        case .hard: return Color.white
        case .intermediate: return F1Theme.sectorGreen
        case .wet: return Color(red: 0/255, green: 144/255, blue: 255/255)
        }
    }

    public var color: Color { compoundColor }
    public var shortLetter: String { shortCode }

    public var sessionLabel: String {
        switch self {
        case .soft: return "15 MIN • SPRINT STINT"
        case .medium: return "25 MIN • CLASSIC POMODORO"
        case .hard: return "45 MIN • DEEP STUDY LAP"
        case .intermediate: return "60 MIN • ENDURANCE STINT"
        case .wet: return "90 MIN • GRAND PRIX MARATHON"
        }
    }

    public var description: String {
        switch self {
        case .soft: return "High-grip sprint for quick formula review and flashcards."
        case .medium: return "Standard Grand Prix qualifying stint for focused concept absorption."
        case .hard: return "Endurance compound for deep Feynman synthesis and translation."
        case .intermediate: return "Heavy technical problem solving under mixed conditions."
        case .wet: return "Ultimate cognitive stamina for comprehensive exam simulations."
        }
    }
}

public struct LearnerAgeProfile: Identifiable, Hashable {
    public var id: Int { age }
    public let age: Int

    public init(age: Int = 14) {
        self.age = max(5, min(99, age))
    }

    public var stageName: String {
        switch age {
        case 5...10: return "Elementary"
        case 11...14: return "Middle School"
        case 15...18: return "High School"
        case 19...24: return "University"
        default: return "Professional"
        }
    }

    public var bracketTitle: String {
        switch age {
        case 5...10: return "Elementary (Age \(age))"
        case 11...14: return "Middle School (Age \(age))"
        case 15...18: return "High School (Age \(age))"
        case 19...24: return "University / Undergrad (Age \(age))"
        default: return "Adult / Professional (Age \(age))"
        }
    }

    public var shortTitle: String {
        "Age \(age)"
    }

    public var iconName: String {
        switch age {
        case 5...10: return "figure.child"
        case 11...14: return "figure.walk"
        case 15...18: return "figure.stand"
        case 19...24: return "graduationcap.fill"
        default: return "person.badge.shield.checkmark.fill"
        }
    }

    public var expectationSummary: String {
        switch age {
        case 5...10:
            return "Requires simple picture-book analogies (toys, animals, cooking). Absolute zero jargon."
        case 11...14:
            return "Requires everyday physical models (billiard balls, water hoses). Strictly flags unexplained jargon."
        case 15...18:
            return "Requires clear mechanistic cause-and-effect reasoning. Foundational physics demystified."
        case 19...24:
            return "Requires first-principles causal logic, formal boundary conditions, and mechanistic depth."
        default:
            return "Requires concise first-principles clarity, practical applications, and zero buzzwords."
        }
    }

    public var promptInstruction: String {
        switch age {
        case 5...10:
            return "Target Learner Age: \(age) years old. Explain like talking to a primary school child. Use simple everyday visual metaphors only. Flag any formal word."
        case 11...14:
            return "Target Learner Age: \(age) years old. Strict zero-jargon rule. Require tangible physical analogies (e.g., collisions, water pipes)."
        case 15...18:
            return "Target Learner Age: \(age) years old. Focus on foundational cause-and-effect principles. Ensure all technical terms are intuitively grounded."
        case 19...24:
            return "Target Learner Age: \(age) years old. Test first-principles rigor, mathematical intuition, and causal mechanisms."
        default:
            return "Target Learner Age: \(age) years old. Emphasize first-principles logic, core mechanism clarity, and practical mastery."
        }
    }
}

public struct F1CornerNode: Identifiable, Hashable {
    public var id: Int { turnNumber }
    public let turnNumber: Int
    public let name: String
    public let gear: Int
    public let apexSpeedKmh: Int
    public let gForce: Double
    public let cognitivePhase: String
    public let normalizedPosition: Double

    public init(turnNumber: Int, name: String, gear: Int, apexSpeedKmh: Int, gForce: Double, cognitivePhase: String, normalizedPosition: Double) {
        self.turnNumber = turnNumber
        self.name = name
        self.gear = gear
        self.apexSpeedKmh = apexSpeedKmh
        self.gForce = gForce
        self.cognitivePhase = cognitivePhase
        self.normalizedPosition = normalizedPosition
    }
}

public struct F1TrackSector: Identifiable, Hashable {
    public let id: Int // 1, 2, or 3
    public var name: String
    public var studyPhase: String
    public var description: String
    public var normalizedRange: ClosedRange<Double>
    public var iconName: String
    public var colorHex: String

    public init(
        id: Int,
        name: String,
        studyPhase: String,
        description: String,
        normalizedRange: ClosedRange<Double>,
        iconName: String = "flag.checkered",
        colorHex: String = "E10600"
    ) {
        self.id = id
        self.name = name
        self.studyPhase = studyPhase
        self.description = description
        self.normalizedRange = normalizedRange
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

public let sampleReviseChapters: [ReviseChapter] = [
    ReviseChapter(
        id: "money_and_credit",
        title: "Money and Credit",
        subject: "SOCIAL SCIENCE",
        imageName: "revise_money_credit",
        cardCount: 6,
        cards: [
            FlashcardItem(
                id: "mc_1",
                title: "Double Coincidence of Wants",
                content: "In a barter economy without money, trade requires both parties to desire what the other has. Money eliminates this friction by serving as a universal medium of exchange.",
                highlightedTerms: [],
                promptQuestion: "Why is double coincidence of wants essential in barter and how does money resolve it?"
            ),
            FlashcardItem(
                id: "mc_2",
                title: "Modern Forms of Money",
                content: "Unlike ancient grain or metallic coinage, modern currency (paper notes and coins) lacks intrinsic value but is accepted because it is authorised by the government (RBI in India).",
                highlightedTerms: [],
                promptQuestion: "Why is paper currency widely accepted even without intrinsic value?"
            ),
            FlashcardItem(
                id: "mc_3",
                title: "Functions of Money",
                content: "1. Medium of exchange: Facilitates trade transactions without barter.\n2. Unit of account: Common measure for pricing goods.\n3. Store of value: Wealth can be saved for future use.\n4. Standard of deferred payment: Used for future payments and loans.",
                highlightedTerms: [],
                promptQuestion: "What are the four primary economic functions served by modern money?"
            ),
            FlashcardItem(
                id: "mc_4",
                title: "Demand Deposits in Banks",
                content: "Deposits in bank accounts that can be withdrawn on demand are called demand deposits. They share the essential features of money by allowing payments via cheques without the direct use of physical cash.",
                highlightedTerms: [],
                promptQuestion: "How do demand deposits and cheques facilitate non-cash transactions?"
            ),
            FlashcardItem(
                id: "mc_5",
                title: "Credit & Terms of Credit",
                content: "Credit refers to an agreement where the lender supplies the borrower with money, goods, or services in return for the promise of future repayment. Terms of credit include interest rate, collateral, documentation, and mode of repayment.",
                highlightedTerms: [],
                promptQuestion: "What components constitute the formal terms of credit?"
            ),
            FlashcardItem(
                id: "mc_6",
                title: "Formal vs Informal Credit Sectors",
                content: "Formal credit comes from banks and cooperatives supervised by the Reserve Bank of India with lower interest rates. Informal credit comes from moneylenders and traders with high interest and no regulatory oversight.",
                highlightedTerms: [],
                promptQuestion: "How does the formal credit sector differ from the informal sector in terms of supervision and interest rates?"
            )
        ],
        dueBadge: "DUE TODAY · 1D",
        intervalDays: 1
    ),
    ReviseChapter(
        id: "french_revolution",
        title: "French Revolution",
        subject: "SOCIAL SCIENCE",
        imageName: "revise_french_revolution",
        cardCount: 6,
        cards: [
            FlashcardItem(
                id: "fr_1",
                title: "Storming of the Bastille",
                content: "On 14 July 1789, the people of Paris stormed the Bastille fortress-prison, symbolising the overthrow of despotic royal tyranny and marking the start of the French Revolution.",
                highlightedTerms: [],
                promptQuestion: "What historic event on 14 July 1789 marked the outbreak of the French Revolution?"
            ),
            FlashcardItem(
                id: "fr_2",
                title: "Estate System in French Society",
                content: "18th-century French society was divided into three estates: Clergy (First Estate), Nobility (Second Estate), and Commoners (Third Estate). The Third Estate bore the entire burden of state taxation without political representation.",
                highlightedTerms: [],
                promptQuestion: "How was the taxation burden distributed across the Three Estates?"
            ),
            FlashcardItem(
                id: "fr_3",
                title: "Declaration of the Rights of Man",
                content: "Adopted in August 1789 by the National Assembly, it proclaimed liberty, equality, and fraternity as universal human rights, abolishing feudal privileges of the clergy and nobility.",
                highlightedTerms: [],
                promptQuestion: "Which document established liberty, equality, and fraternity in 1789?"
            ),
            FlashcardItem(
                id: "fr_4",
                title: "Reign of Terror (1793-1794)",
                content: "Led by Maximilien Robespierre and the Jacobin Club, this period saw radical policies and thousands guillotined before Robespierre's own downfall in the Thermidorian Reaction.",
                highlightedTerms: [],
                promptQuestion: "Who led the Reign of Terror and what radical policies defined it?"
            ),
            FlashcardItem(
                id: "fr_5",
                title: "Abolition of Feudalism & Monarchy",
                content: "In 1792, the newly elected National Convention voted to abolish the monarchy and declared France a Republic. King Louis XVI was sentenced to death on charges of treason.",
                highlightedTerms: [],
                promptQuestion: "When was the French monarchy formally abolished and the republic declared?"
            ),
            FlashcardItem(
                id: "fr_6",
                title: "Rise of Napoleon Bonaparte",
                content: "Political instability under the Directory paved the way for the rise of a military dictator, Napoleon Bonaparte, who seized power in 1799 and introduced civil and legal reforms codified in the Napoleonic Code.",
                highlightedTerms: [],
                promptQuestion: "What historical circumstances enabled the rise of Napoleon Bonaparte in 1799?"
            )
        ],
        dueBadge: "DUE IN 3 DAYS · 3D",
        intervalDays: 3
    ),
    ReviseChapter(
        id: "solar_system",
        title: "Solar System",
        subject: "SCIENCE",
        imageName: "revise_solar_system",
        cardCount: 6,
        cards: [
            FlashcardItem(
                id: "ss_1",
                title: "Gravitational Heliocentrism",
                content: "The Sun sits at the center of the solar system, holding 99.8% of its total mass and exerting the dominant gravitational force that dictates planetary elliptical orbits.",
                highlightedTerms: [],
                promptQuestion: "What gravitational relationship holds planets in orbit around the Sun?"
            ),
            FlashcardItem(
                id: "ss_2",
                title: "Terrestrial vs Gas Giants",
                content: "The four inner rocky planets (Mercury, Venus, Earth, Mars) possess solid silicate surfaces, whereas the outer giants (Jupiter, Saturn, Uranus, Neptune) are composed largely of hydrogen and helium fluids.",
                highlightedTerms: [],
                promptQuestion: "How do terrestrial planets differ structurally from the Jovian gas giants?"
            ),
            FlashcardItem(
                id: "ss_3",
                title: "Kepler's Laws of Planetary Motion",
                content: "1. Planets move in elliptical orbits with the Sun at one focus.\n2. A line connecting planet and Sun sweeps out equal areas in equal times.\n3. The square of orbital period is proportional to the cube of semi-major axis.",
                highlightedTerms: [],
                promptQuestion: "State Kepler's three laws governing planetary motion in our solar system."
            ),
            FlashcardItem(
                id: "ss_4",
                title: "Asteroid Belt & Kuiper Belt",
                content: "The main asteroid belt lies between the orbits of Mars and Jupiter, containing rocky remnants from solar system formation. Beyond Neptune lies the Kuiper belt, home to icy dwarf planets including Pluto.",
                highlightedTerms: [],
                promptQuestion: "Where are the Asteroid Belt and Kuiper Belt located and what are they composed of?"
            ),
            FlashcardItem(
                id: "ss_5",
                title: "Solar Wind & Helisphere",
                content: "The Sun continuously ejects a stream of charged plasma known as the solar wind. It carves out a bubble in interstellar space called the heliosphere, shielding the solar system from high-energy cosmic rays.",
                highlightedTerms: [],
                promptQuestion: "What is the solar wind and how does the heliosphere protect planetary atmospheres?"
            ),
            FlashcardItem(
                id: "ss_6",
                title: "Gravitational Tides & Resonances",
                content: "Planetary moons experience tidal forces resulting from differential gravitational attraction across their diameters. This mechanism drives volcanic activity on Jupiter's moon Io and subsurface oceans on Europa.",
                highlightedTerms: [],
                promptQuestion: "How do gravitational tidal forces produce geothermal energy inside icy moons?"
            )
        ],
        dueBadge: "DUE IN 7 DAYS · 7D",
        intervalDays: 7
    )
]

public struct AppMotionSystem {
    /// Interactive direct response spring for buttons and toggles (Apple HIG direct manipulation)
    public static let interactiveSpring: Animation = .spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.06)
    /// Fluid morphing spring for tab bars, sidebars, and structural layout transitions
    public static let tabMorphSpring: Animation = .spring(response: 0.40, dampingFraction: 0.88, blendDuration: 0.10)
    /// Smooth page transition spring for switching primary navigation destinations
    public static let fluidPageSpring: Animation = .smooth(duration: 0.36)
    /// Fluid responsive spring for input mode transitions and workstation entrance
    public static let fluidSpring: Animation = .spring(response: 0.36, dampingFraction: 0.85, blendDuration: 0.08)
    /// Rewarding bouncy spring for dopamine feedback (rings completion, XP gains, streaks)
    public static let bouncyDopamineSpring: Animation = .spring(response: 0.42, dampingFraction: 0.68, blendDuration: 0.10)
    /// Apple HIG Snappy spring for quick responsive mode changes and segmented chips
    public static let snappy: Animation = .snappy(duration: 0.28, extraBounce: 0.05)
    /// Apple HIG Smooth transition for card reflows, timestamps, and typography interpolations
    public static let smooth: Animation = .smooth(duration: 0.34)
    
    /// Motion-sensitive spring complying with Apple HIG Motion & Inclusion guidelines
    public static func spring(reduceMotion: Bool, response: Double = 0.30, damping: Double = 0.82) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.20) : .spring(response: response, dampingFraction: damping, blendDuration: 0.06)
    }
}

// MARK: - Official Apple HIG Spring Button Style (Instant Touch-Down Feedback & Sensory Response)
public struct F1SpringButtonStyle: ButtonStyle {
    public var scale: CGFloat
    public var pressedOpacity: Double
    
    public init(scale: CGFloat = 0.96, pressedOpacity: Double = 0.92) {
        self.scale = scale
        self.pressedOpacity = pressedOpacity
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        F1SpringButtonBody(configuration: configuration, scale: scale, pressedOpacity: pressedOpacity)
    }
}

private struct F1SpringButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let scale: CGFloat
    let pressedOpacity: Double
    @Environment(\.f1ReduceMotion) private var reduceMotion
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.22, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

public extension ButtonStyle where Self == F1SpringButtonStyle {
    static var f1Spring: F1SpringButtonStyle { F1SpringButtonStyle() }
    static func f1Spring(scale: CGFloat, pressedOpacity: Double = 0.92) -> F1SpringButtonStyle {
        F1SpringButtonStyle(scale: scale, pressedOpacity: pressedOpacity)
    }
    /// Subtle spring feedback for large interactive cards and tiles
    static var f1CardSpring: F1SpringButtonStyle { F1SpringButtonStyle(scale: 0.985, pressedOpacity: 0.96) }
}

struct AppleMusicDarkGradientBackground: View {
    var body: some View {
        ZStack {
            // 1. Deep Neutral Carbon Asphalt Canvas (#0A0A0C) - Zero Blue Tint
            F1Theme.carbonBlack

            // 2. Full-Bleed F1 Car Artwork - Scaled precisely to fill display
            Image("f1_car_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .opacity(0.38)
                .allowsHitTesting(false)

            // 3. Dark Neutral Carbon Vignette Overlay - Eliminates any blue tint & ensures WCAG AAA contrast
            RadialGradient(
                colors: [
                    Color.black.opacity(0.20),
                    F1Theme.carbonBlack.opacity(0.85)
                ],
                center: .center,
                startRadius: 160,
                endRadius: 1000
            )
            .allowsHitTesting(false)

            // 4. Subtle Top Matte Sheen
            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        // Drawn once into a texture: pushing and popping screens, each with this background behind it, no longer re-composites
        // the artwork and the gradients on every frame of the transition
        .drawingGroup()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
    }
}

public enum AppNavigationTab: String, CaseIterable, Identifiable {
    case pitWall = "Home"
    case carSetup = "Timer"
    case teamRadio = "Radio"
    case flashcards = "Flashcards"
    case search = "Search"
    case settings = "Settings"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .pitWall: return "Home"
        case .carSetup: return "Timer"
        case .teamRadio: return "Explain"
        case .flashcards: return "Flashcards"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    public var iconName: String {
        switch self {
        case .pitWall: return "house.fill"
        case .carSetup: return "timer"
        case .teamRadio: return "waveform.badge.mic"
        case .flashcards: return "rectangle.stack.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gear"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .pitWall: return F1Theme.racingRed
        case .carSetup: return F1Theme.sectorYellow
        case .teamRadio: return F1Theme.sectorGreen
        case .flashcards: return F1Theme.speedTrapGold
        case .search: return F1Theme.racingRed
        case .settings: return F1Theme.racingRed
        }
    }

    // Static Aliases for backward compatibility during refactoring
    public static var paddock: AppNavigationTab { .flashcards }
    public static var flightDeck: AppNavigationTab { .pitWall }
    public static var liveArena: AppNavigationTab { .teamRadio }
    public static var aiReport: AppNavigationTab { .flashcards }
    public static var metricsShield: AppNavigationTab { .carSetup }
    public static var knowledgeVault: AppNavigationTab { .flashcards }
}
