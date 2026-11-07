//
//  ConceptEvaluator.swift
//  Litmus - Feynman Cognitive Engine Bridge
//
//  Unifies the 5-layer pipeline:
//    Layer 1: Speech Translation (LiveSpeechRecorder)
//    Layer 2: NaturalLanguage Guardrails (ParakhGuardrailLayer - NLTagger & NLEmbedding)
//    Layer 3: Deterministic Storage Bridge (session_input.json & evaluation_output.json)
//    Layer 4: Cognitive Reasoning Engine (FeynmanCognitiveEngine / ParakhRubricMatrix)
//    Layer 5: Presentation Layer (3-Tier Feedback UI in ContentView)
//

import Foundation
import NaturalLanguage

// MARK: - Public Types

public enum GradingTier: String, Equatable, Sendable {
    case right
    case vague
    case missing
}

public struct DynamicFlashcard: Hashable, Sendable {
    public let title: String
    public let content: String
    public let imageName: String?
    
    public init(title: String, content: String, imageName: String? = nil) {
        self.title = title
        self.content = content
        self.imageName = imageName
    }
}

public struct DualPillarFlashcards: Sendable {
    public let theoryCard: DynamicFlashcard
    public let analogyCard: DynamicFlashcard
    public let additionalCards: [DynamicFlashcard]
    
    public init(theoryCard: DynamicFlashcard, analogyCard: DynamicFlashcard, additionalCards: [DynamicFlashcard] = []) {
        self.theoryCard = theoryCard
        self.analogyCard = analogyCard
        self.additionalCards = additionalCards
    }
    
    public var allCards: [DynamicFlashcard] {
        var result: [DynamicFlashcard] = []
        if analogyCard.imageName != nil {
            result.append(analogyCard)
            result.append(theoryCard)
        } else {
            result.append(theoryCard)
            result.append(analogyCard)
        }
        result.append(contentsOf: additionalCards)
        return result
    }
}

public enum AnswerFlag: String, Sendable {
    case tooBrief
    case keywordList
    case promptEcho
    case roteLearning
}

public struct SemanticEvaluationResult: Sendable {
    public let tier: GradingTier
    public let detectedTopic: String
    public let rightText: String?
    public let vagueText: String?
    public let missingText: String?
    public let generatedFlashcards: [DynamicFlashcard]
    public let telemetry: LinguisticTelemetry?
    public let parakhAssessment: ParakhAssessment?
    public let feynmanAnalysis: FeynmanAnalysis?
    public var flags: [AnswerFlag] = []
    
    public init(
        tier: GradingTier,
        detectedTopic: String,
        rightText: String?,
        vagueText: String?,
        missingText: String?,
        generatedFlashcards: [DynamicFlashcard],
        telemetry: LinguisticTelemetry? = nil,
        parakhAssessment: ParakhAssessment? = nil,
        feynmanAnalysis: FeynmanAnalysis? = nil,
        flags: [AnswerFlag] = []
    ) {
        self.tier = tier
        self.detectedTopic = detectedTopic
        self.rightText = rightText
        self.vagueText = vagueText
        self.missingText = missingText
        self.generatedFlashcards = generatedFlashcards
        self.telemetry = telemetry
        self.parakhAssessment = parakhAssessment
        self.feynmanAnalysis = feynmanAnalysis
        self.flags = flags
    }

    /// The three feedback strings for the UI. Empty means the row is hidden.
    public var feedback: FeedbackReport {
        FeedbackReport(missing: missingText ?? "", vague: vagueText ?? "", right: rightText ?? "")
    }
}

// MARK: - Concept Evaluator

public enum ConceptEvaluator {
    
    public static func prepare() async {
        // Pre-warm Apple NaturalLanguage embeddings
        _ = NLEmbedding.sentenceEmbedding(for: .english)
    }
    
    // MARK: - Evaluation Entry Point
    /// Schema 4 concepts: on-device boolean checklist -> deterministic FeedbackReport.
    /// Other chapters: the PARAKH rubric matrix.
    static func evaluate(text: String, topic: String, topicObject: NCERTTopic? = nil) async -> SemanticEvaluationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = FeynmanConceptRegistry.entry(forTopicTitle: topic),
              trimmed.split(separator: " ").count >= 5 else {
            return evaluateWithRubricMatrix(text: trimmed, topic: topic, topicObject: topicObject)
        }

        let telemetry = ParakhGuardrailLayer.shared.calculateTelemetry(transcript: trimmed, conceptTopic: topic)
        let checklist = await FeynmanCognitiveEngine.shared.evaluateChecklist(
            transcript: trimmed,
            concept: entry.concept,
            articulationChecks: entry.articulationChecks,
            chapterVocabulary: entry.chapterVocabulary,
            telemetry: telemetry
        )
        let report = feedbackReport(checklist: checklist, concept: entry.concept, articulationChecks: entry.articulationChecks)

        let tier: GradingTier
        if report.missing.isEmpty && report.vague.isEmpty {
            tier = .right
        } else if !report.right.isEmpty {
            tier = .vague
        } else {
            tier = .missing
        }

        let dualPillar = dualPillarCards(for: topic, topicObject: topicObject)
        let cards = tier == .missing
            ? dualPillar.allCards
            : [dualPillar.analogyCard, dualPillar.theoryCard] + dualPillar.additionalCards

        return SemanticEvaluationResult(
            tier: tier,
            detectedTopic: topic,
            rightText: report.right.isEmpty ? nil : report.right,
            vagueText: report.vague.isEmpty ? nil : report.vague,
            missingText: report.missing.isEmpty ? nil : report.missing,
            generatedFlashcards: cards,
            telemetry: telemetry,
            flags: telemetry.isKeywordStuffingSuspected ? [.keywordList] : []
        )
    }

    private static func evaluateWithRubricMatrix(text: String, topic: String, topicObject: NCERTTopic?) -> SemanticEvaluationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        
        let dualPillar = dualPillarCards(for: topic, topicObject: topicObject)
        
        // Gate 1: Word Count Guardrail (< 5 words)
        if words.count < 5 {
            return SemanticEvaluationResult(
                tier: .missing,
                detectedTopic: topic,
                rightText: nil,
                vagueText: nil,
                missingText: "Too short (\(words.count) word\(words.count == 1 ? "" : "s")). Explain the concept in full sentences with an everyday example.",
                generatedFlashcards: dualPillar.allCards,
                flags: [.tooBrief]
            )
        }
        
        // Execute the complete 5-layer pipeline synchronously for real-time responsiveness
        let (session, evaluation) = FeynmanTutorPipeline.shared.evaluateSynchronously(
            conceptTopic: topic,
            transcript: trimmed
        )
        
        let telemetry = session.linguisticTelemetry
        let parakh = evaluation.parakhAssessment
        let feynman = evaluation.feynmanAnalysis
        
        var flags: [AnswerFlag] = []
        if telemetry.isKeywordStuffingSuspected {
            flags.append(.keywordList)
        }
        if parakh.roteLearningDetected {
            flags.append(.roteLearning)
        }
        
        // Map PARAKH Conceptual Clarity Tier to 3-Tier UI Result
        switch parakh.conceptualClarity {
        case .high:
            // High clarity mastery: Serve analogy card (and diagram if present)
            var cards: [DynamicFlashcard] = [dualPillar.analogyCard]
            if dualPillar.analogyCard.imageName != nil {
                cards.append(dualPillar.theoryCard)
            }
            cards.append(contentsOf: dualPillar.additionalCards)
            return SemanticEvaluationResult(
                tier: .right,
                detectedTopic: topic,
                rightText: feynman.feynmanGapExplanation,
                vagueText: nil,
                missingText: nil,
                generatedFlashcards: cards,
                telemetry: telemetry,
                parakhAssessment: parakh,
                feynmanAnalysis: feynman,
                flags: flags
            )
            
        case .moderate:
            var cards: [DynamicFlashcard] = []
            // Targeted Dual-Pillar injection based on semantic gap
            if telemetry.semanticSimilarityToTextbook < 0.50 {
                cards.append(dualPillar.theoryCard)
            }
            if telemetry.semanticSimilarityToAnalogy < 0.38 {
                cards.append(dualPillar.analogyCard)
            }
            if cards.isEmpty {
                cards.append(dualPillar.analogyCard)
            }
            cards.append(contentsOf: dualPillar.additionalCards)
            
            return SemanticEvaluationResult(
                tier: .vague,
                detectedTopic: topic,
                rightText: telemetry.semanticSimilarityToTextbook >= 0.40 ? "You identified foundational concepts." : nil,
                vagueText: feynman.feynmanGapExplanation,
                missingText: "Guiding Thought Experiment: \(feynman.nextGuidingQuestion)",
                generatedFlashcards: cards,
                telemetry: telemetry,
                parakhAssessment: parakh,
                feynmanAnalysis: feynman,
                flags: flags
            )
            
        case .low:
            var cards: [DynamicFlashcard] = []
            if telemetry.isKeywordStuffingSuspected {
                // Keyword stuffing: student missed the cause-effect mechanism
                cards.append(dualPillar.analogyCard)
                cards.append(dualPillar.theoryCard)
            } else {
                cards.append(dualPillar.theoryCard)
                cards.append(dualPillar.analogyCard)
            }
            cards.append(contentsOf: dualPillar.additionalCards)
            
            return SemanticEvaluationResult(
                tier: .missing,
                detectedTopic: topic,
                rightText: nil,
                vagueText: nil,
                missingText: "\(feynman.feynmanGapExplanation) \(parakh.evaluationTelemetrySummary)",
                generatedFlashcards: cards,
                telemetry: telemetry,
                parakhAssessment: parakh,
                feynmanAnalysis: feynman,
                flags: flags
            )
        }
    }
    
    // MARK: - Dual-Pillar Flashcard Provider (Curriculum-Aligned)
    
    static func dualPillarCards(for topic: String, topicObject: NCERTTopic? = nil) -> DualPillarFlashcards {
        let key = topic.lowercased()
        let chap = topicObject?.chapter.lowercased() ?? ""

        // Schema 4 concepts: cards come straight from the chapter JSON.
        if let concept = FeynmanConceptRegistry.entry(forTopicTitle: topic)?.concept {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(title: concept.label, content: concept.cardText),
                analogyCard: DynamicFlashcard(
                    title: "From the chapter",
                    content: concept.acceptedExamples.prefix(2).joined(separator: ". ") + "."
                ),
                additionalCards: [DynamicFlashcard(title: "Hint", content: concept.hint)]
            )
        }
        
        // ==========================================
        // MARK: - Class 10 Biology: Life Processes (Ch 5)
        // ==========================================
        let isChapter5 = chap.contains("life process") || key.contains("life process")
            || key.contains("cellular maintenance")
            || key.contains("autotrophic") || key.contains("photosynthesis")
            || key.contains("heterotrophic nutrition")
            || key.contains("alimentary canal") || key.contains("digestive system")
            || key.contains("respiration and energy pathways")
            || key.contains("gas exchange in aquatic") || key.contains("human lungs")
            || key.contains("double circulation") || key.contains("circulatory system")
            || (key.contains("xylem") && key.contains("phloem")) || key.contains("plant transport")
            || key.contains("nephron") || (key.contains("excretory") && key.contains("human"))
            || (key.contains("excretory") && key.contains("plant"))

        if isChapter5 {
            // Topic 1: Life Processes and Cellular Maintenance (Fig 5.5: Nutrition in Amoeba)
            if key.contains("cellular maintenance") || key == "life processes and cellular maintenance" {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Life Processes & Cellular Maintenance",
                        content: "Life processes are vital maintenance activities—nutrition, respiration, transport, and excretion—essential to preserve structural order and prevent molecular breakdown in living organisms. While unicellular organisms sustain all metabolic exchanges via direct diffusion across their cell surface, multicellular organisms possess specialized organ systems because diffusion is far too slow to reach deep-seated tissues across large body volumes."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Nutrition in Amoeba & Surface Diffusion (Fig 5.5)",
                        content: "A single-celled Amoeba uses temporary finger-like extensions (pseudopodia) to engulf food particles into a food vacuole, relying on simple diffusion across its entire cell membrane—a strategy impossible for complex multicellular bodies where cells are isolated from the external environment.",
                        imageName: "bio_life_nutrition_amoeba"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Limits of Diffusion in Multicellular Organisms",
                            content: "Calculations show that if diffusion alone transported oxygen in humans, an oxygen molecule would take an estimated three years to travel from our lungs to our toes. Dedicated respiratory pigments (hemoglobin) and a muscular circulatory pump evolved to overcome these physical transport boundaries."
                        )
                    ]
                )
            }
            
            // Topic 2: Autotrophic Nutrition and Photosynthesis (Fig 5.1, 5.2, 5.3, 5.4)
            if key.contains("autotrophic") || key.contains("photosynthesis") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Autotrophic Nutrition & Photosynthetic Mechanism",
                        content: "Autotrophic organisms (green plants and cyanobacteria) synthesize high-energy carbohydrates from simple inorganic raw materials (CO₂ and H₂O) using solar photons captured by chlorophyll [6CO₂ + 12H₂O → C₆H₁₂O₆ + 6O₂ + 6H₂O]. The reaction proceeds through light absorption, photolysis of water into H⁺ and O₂, and subsequent enzymatic reduction of carbon dioxide into glucose, which is stored as starch."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Cross-Section of a Leaf (Fig 5.1)",
                        content: "Cross-section illustrating photosynthetic leaf architecture: protective upper and lower epidermis coated with waxy cuticles, middle mesophyll cells packed with green chloroplast organelles, internal air spaces for gas circulation, and vascular bundles (xylem and phloem) providing water and nutrient transport.",
                        imageName: "bio_life_leaf_cross_section"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Stomatal Guard Cell Regulation (Fig 5.3)",
                            content: "Stomatal pores regulate gas exchange and transpiration. When water rushes into guard cells, they swell and curve outward, pulling the pore open; when they lose water, they become flaccid and straighten, snapping the pore shut to prevent dehydration.",
                            imageName: "bio_life_stomata_open_closed"
                        ),
                        DynamicFlashcard(
                            title: "Variegated Leaf Starch Test (Fig 5.2)",
                            content: "Testing a variegated money plant leaf with iodine solution reveals dark blue-black staining strictly in green chlorophyll-containing patches, confirming that chlorophyll is indispensable for starch synthesis.",
                            imageName: "bio_life_variegated_leaf_starch_test"
                        ),
                        DynamicFlashcard(
                            title: "Bell-Jar Carbon Dioxide Necessity Setup (Fig 5.4)",
                            content: "Placing a potted plant alongside potassium hydroxide (KOH) inside an airtight bell jar starves the plant of CO₂ (which is absorbed by KOH). The absence of starch formation confirms carbon dioxide is an essential raw material for photosynthesis.",
                            imageName: "bio_life_bell_jar_co2_experiment"
                        )
                    ]
                )
            }
            
            // Topic 3: Heterotrophic Nutrition Strategies (Fig 5.5: Nutrition in Amoeba)
            if key.contains("heterotrophic") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Heterotrophic Nutritional Modes",
                        content: "Heterotrophs obtain organic carbon from preformed autotrophic sources via three primary strategies: Saprophytic nutrition (fungi like yeast, mushrooms, and Rhizopus secrete extracellular enzymes to decompose dead organic matter externally prior to absorption); Holozoic nutrition (organisms ingest whole food particles for internal enzymatic breakdown); and Parasitic nutrition (organisms like Cuscuta, tapeworms, and leeches derive sustained sustenance directly from host tissues without immediate killing)."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Phagocytic Nutrition in Amoeba (Fig 5.5)",
                        content: "Amoeba captures food by extending finger-like pseudopodia around a microscopic food particle, fusing them into a food vacuole. Inside, digestive enzymes break down complex nutrients into simple molecules that diffuse directly into the cytoplasm before the vacuole expels unabsorbed waste.",
                        imageName: "bio_life_nutrition_amoeba"
                    )
                )
            }
            
            // Topic 4: Human Digestive System and Enzyme Action (Fig 5.6: Human Alimentary Canal)
            if key.contains("digestive system") || key.contains("alimentary canal") || (key.contains("digest") && key.contains("enzyme")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Digestive Enzymes & Gastrointestinal Physiology",
                        content: "The human alimentary canal processes complex macromolecules through sequential mechanical grinding and enzymatic hydrolysis: Salivary amylase in the mouth hydrolyses starch into maltose; gastric pepsin in the stomach initiates protein digestion in an acidic HCl environment shielded by mucus; bile salts from the liver emulsify lipid droplets and alkalize chyme; pancreatic trypsin and lipase break down proteins and fats; and intestinal brush-border enzymes finalize hydrolysis into absorbable amino acids, glucose, and fatty acids, absorbed by vascularized villi."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Human Alimentary Canal Anatomy (Fig 5.6)",
                        content: "Comprehensive anatomy of the human digestive tract: mouth and buccal cavity, muscular oesophagus driving peristaltic waves, J-shaped stomach secreting gastric juice, liver and gall bladder releasing alkaline bile, pancreas delivering digestive enzymes, coiled small intestine lined with villi, and the large intestine terminating at the rectum and anus.",
                        imageName: "bio_life_human_alimentary_canal"
                    )
                )
            }
            
            // Topic 5: Respiration and Energy Pathways (Fig 5.7: Limewater Gas Tests)
            if key.contains("respiration and energy") || (key.contains("respiration") && (key.contains("pathway") || key.contains("energy") || key.contains("glucose"))) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Cellular Respiration & Glucose Breakdown Pathways",
                        content: "Respiration releases chemical energy through the enzymatic breakdown of glucose to generate ATP. In the cytoplasm, 6-carbon glucose is cleaved into 3-carbon pyruvate. Under aerobic conditions inside mitochondria, pyruvate oxidizes completely into CO₂, H₂O, and 38 ATP. Under anaerobic conditions in yeast, pyruvate ferments into ethanol, CO₂, and 2 ATP. When vigorous muscle exertion outstrips oxygen delivery, anaerobic glycolysis converts pyruvate into 3-carbon lactic acid, triggering painful cellular cramps."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Limewater Gas Test & Exhaled Carbon Dioxide (Fig 5.7)",
                        content: "Comparing atmospheric air pumped with a syringe/pichkari versus air exhaled through a straw into lime water [Ca(OH)₂]: while atmospheric air takes minutes to induce turbidity, exhaled breath instantly precipitates insoluble white calcium carbonate, proving that cellular respiration vigorously expels carbon dioxide.",
                        imageName: "bio_life_limewater_exhaled_air_test"
                    )
                )
            }
            
            // Topic 6: Gas Exchange in Aquatic vs Terrestrial Organisms and Human Lungs (Fig 5.9: Human Respiratory System)
            if key.contains("gas exchange") || key.contains("aquatic vs terrestrial") || key.contains("human lungs") || key.contains("respiratory system") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Alveolar Gas Exchange & Hemoglobin Dynamics",
                        content: "Terrestrial organisms utilize atmospheric air, whereas aquatic species must breathe rapidly to extract limited dissolved oxygen from water. In human lungs, inhaled air reaches millions of thin-walled, spherical alveoli providing ~80 m² of capillary exchange area. Because simple diffusion would take years to transport oxygen across large human body dimensions, iron-rich hemoglobin in red blood cells binds oxygen with high affinity in alveolar capillaries, while carbon dioxide dissolves directly into blood plasma for exhalation."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Human Respiratory System Architecture (Fig 5.9)",
                        content: "Detailed anatomical diagram of the human respiratory tract: nasal passage with warming and filtering mucosal hairs, trachea supported by structural rings of cartilage preventing collapse, branching bronchi and bronchioles, and dense clusters of alveolar sacs expanding into an 80-square-metre gas-exchange surface.",
                        imageName: "bio_life_human_respiratory_system"
                    )
                )
            }
            
            // Topic 7: Human Circulatory System and Double Circulation (Fig 5.10 & Fig 5.11)
            if key.contains("circulatory system") || key.contains("double circulation") || key.contains("human heart") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Double Circulation & Cardiac Physiology",
                        content: "The mammalian four-chambered heart operates two distinct circulatory circuits: Pulmonary circulation (right ventricle pumps deoxygenated blood via pulmonary arteries to lungs, returning oxygenated blood via pulmonary veins to left atrium) and Systemic circulation (left ventricle pumps high-pressure oxygenated blood via the aorta to body organs, returning deoxygenated blood via the vena cava). This strict physical separation by the interventricular septum prevents oxygen dilution, sustaining the elevated metabolic rates and homeothermic thermal demands of warm-blooded organisms."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Sectional View of the Human Heart (Fig 5.10)",
                        content: "Cross-section showing the four muscular chambers of the human heart: right atrium and ventricle handling deoxygenated blood from the vena cava, thick-walled left ventricle generating powerful contractile force to pump oxygenated blood through the aorta, and the central septum preventing blood mixing.",
                        imageName: "bio_life_human_heart_cross_section"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Oxygen & Carbon Dioxide Exchange Transport Scheme (Fig 5.11)",
                            content: "Flowchart schematic illustrating the systemic and pulmonary circulatory loops: deoxygenated blood from body tissues flows through the vena cava to the right side of the heart, is pumped to lung capillaries for gas exchange, and returns via pulmonary veins to the left heart to be distributed body-wide.",
                            imageName: "bio_life_double_circulation_scheme"
                        )
                    ]
                )
            }
            
            // Topic 8: Plant Transport Systems: Xylem and Phloem (Fig 5.12: Water Movement During Transpiration)
            if (key.contains("xylem") && key.contains("phloem")) || key.contains("plant transport") || key.contains("translocation") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Xylem Transpiration Pull vs. Phloem Translocation",
                        content: "Plants utilize two specialized vascular networks: Xylem conducts water and inorganic minerals unidirectionally from roots to aerial parts, driven primarily by physical negative suction (transpiration pull) created by stomatal evaporation during the day and active root pressure at night. Phloem conducts organic photosynthates (sucrose, amino acids) bidirectionally via translocation, utilizing cellular ATP energy to build osmotic pressure gradients that drive nutrients to active metabolic sinks like growing shoot tips and storage organs."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Transpiration & Water Movement in Trees (Fig 5.12)",
                        content: "Diagram illustrating continuous water transport in tall trees: roots absorb soil water and minerals, cohesive and adhesive water columns ascend through xylem vessels, and solar-driven transpiration from stomatal leaf pores creates a powerful upward suction pull.",
                        imageName: "bio_life_transpiration_water_movement"
                    )
                )
            }
            
            // Topic 9: Human Excretory System and Nephron Function (Fig 5.13 & Fig 5.14)
            if key.contains("nephron") || (key.contains("excretory") && (key.contains("human") || key.contains("kidney"))) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Nephron Filtration & Renal Physiology",
                        content: "The human excretory system eliminates nitrogenous wastes (urea and uric acid) produced during protein catabolism. Within each kidney, millions of microscopic nephrons perform ultrafiltration: systemic blood enters the glomerulus where hydrostatic pressure drives water and small solutes across Bowman's capsule to form ~180 L of initial daily filtrate. As filtrate traverses the convoluted tubule and loop of Henle, selective reabsorption recovers essential glucose, amino acids, electrolytes, and 99% of water into peritubular capillaries, concentrating final urine to 1–2 litres per day."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Human Excretory System Anatomy (Fig 5.13)",
                        content: "Macroscopic anatomy of the human urinary system: bilateral kidneys filtering metabolic nitrogenous wastes from the renal arteries, tubular ureters transporting urine downward, an elastic muscular urinary bladder storing urine under autonomic nervous control, and the terminal urethra.",
                        imageName: "bio_life_human_urinary_system"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Microscopic Structure of a Nephron (Fig 5.14)",
                            content: "Microscopic functional unit of the kidney: cup-shaped Bowman's capsule enclosing the capillary glomerulus, convoluted tubule wrapped in peritubular capillary networks for selective reabsorption, and the collecting duct draining into the renal pelvis.",
                            imageName: "bio_life_nephron_structure"
                        )
                    ]
                )
            }
            
            // Topic 10: Excretory Strategies in Plants (Fig 5.12: Transpiration Water Movement)
            if key.contains("excretory strategies in plants") || (key.contains("excret") && key.contains("plant")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Plant Excretory Mechanisms & Vacuolar Storage",
                        content: "Plants eliminate metabolic wastes without specialized excretory organs through cellular compartmentalization and passive physical disposal: Gaseous oxygen and carbon dioxide diffuse through stomatal pores; surplus water evaporates via foliar transpiration; secondary metabolic wastes are sequestered inside cellular vacuoles, deposited into dying leaves that are shed (abscission), or permanently entombed as insoluble resins and gums inside non-conducting heartwood xylem, with trace organic toxins excreted directly into rhizosphere soil."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Plant Transpiration & Waste Disposal (Fig 5.12)",
                        content: "Because plants lack an active pumping heart and kidneys, they eliminate excess water by evaporating water vapour through foliar stomatal transpiration, while compartmentalizing cellular byproducts into falling autumn leaves and old heartwood xylem as inert gums and resins.",
                        imageName: "bio_life_transpiration_water_movement"
                    )
                )
            }
        }
        
        // ==========================================
        // MARK: - Class 10 Chemistry: Carbon and its Compounds (Ch 4)
        // ==========================================
        let isChapter4 = chap.contains("carbon") || key.contains("carbon")
            || key.contains("covalent bonding")
            || key.contains("allotrope")
            || key.contains("versatile nature")
            || key.contains("catenation")
            || key.contains("tetravalen")
            || key.contains("saturated, unsaturated")
            || key.contains("isomers")
            || key.contains("homologous series")
            || key.contains("functional group")
            || (key.contains("combustion") && (key.contains("oxidation") || chap.contains("carbon")))
            || key.contains("addition & substitution")
            || key.contains("reactions of ethanol")
            || key.contains("ethanoic acid")
            || key.contains("esterification")
            || key.contains("micelle")
            || key.contains("soaps, micelles")

        if isChapter4 {
            // Topic 1: Covalent Bonding in Carbon (Fig 4.1, 4.2, 4.3, 4.4, 4.5)
            if key.contains("covalent") || key.contains("bonding in carbon") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Covalent Bonding & Electron Sharing",
                        content: "Carbon has atomic number 6 with electronic configuration (2,4). Since gaining four electrons to form C⁴⁻ requires holding 10 electrons with only 6 protons, and losing four electrons to form C⁴⁺ demands immense ionization energy, carbon overcomes this barrier by sharing its valence electrons with other atoms to achieve stable noble gas octets. Covalent compounds possess strong intramolecular bonds but weak intermolecular forces, resulting in low melting/boiling points and electrical non-conductivity due to the absence of free charged ions."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "A Molecule of Hydrogen (Fig 4.1)",
                        content: "Two hydrogen atoms, each possessing a single valence electron, share an electron pair to attain the stable electronic configuration of helium, forming an H₂ molecule held by a single covalent bond.",
                        imageName: "chem_carbon_h2_molecule"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Single Bond Between Two Hydrogen Atoms (Fig 4.2)",
                            content: "The shared pair of electrons constitutes a single covalent bond between the two hydrogen atoms, represented by a single dash line between the atomic symbols (H—H).",
                            imageName: "chem_carbon_h2_single_bond"
                        ),
                        DynamicFlashcard(
                            title: "Double Bond Between Two Oxygen Atoms (Fig 4.3)",
                            content: "Each oxygen atom (2,6) requires two electrons to complete its octet. Two oxygen atoms share two pairs of valence electrons (four electrons total), establishing a stable O=O double covalent bond in the O₂ molecule.",
                            imageName: "chem_carbon_o2_double_bond"
                        ),
                        DynamicFlashcard(
                            title: "Triple Bond Between Two Nitrogen Atoms (Fig 4.4)",
                            content: "Nitrogen (2,5) requires three electrons to achieve an octet. Two nitrogen atoms share three pairs of electrons (six electrons total), creating an exceptionally strong N≡N triple covalent bond in the N₂ molecule.",
                            imageName: "chem_carbon_n2_triple_bond"
                        ),
                        DynamicFlashcard(
                            title: "Electron Dot Structure for Methane (Fig 4.5)",
                            content: "A central tetravalent carbon atom shares each of its four valence electrons with four separate hydrogen atoms, giving carbon an octet (neon configuration) and each hydrogen a duplet (helium configuration) in tetrahedral methane (CH₄).",
                            imageName: "chem_carbon_methane_dot_structure"
                        )
                    ]
                )
            }
            
            // Topic 2: Allotropes of Carbon
            if key.contains("allotrope") || key.contains("diamond") || key.contains("graphite") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Carbon Allotropes: Diamond & Graphite",
                        content: "Allotropy is the phenomenon where an element exists in distinct structural forms with identical chemical properties but markedly different physical properties. In diamond, each carbon atom is covalently bonded to four other carbon atoms in a rigid, three-dimensional tetrahedral network, making it the hardest natural substance known with an exceptionally high melting point. In graphite, each carbon atom bonds to three others in planar hexagonal sheets separated by weak van der Waals forces, allowing layers to slide smoothly over each other."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Graphite Electrical Conductivity & Lubrication",
                        content: "Because each carbon in graphite forms only three covalent bonds, one delocalized valence electron remains free to migrate across hexagonal planes. This free electron pool makes graphite an exceptional non-metallic electrical conductor used in battery electrodes, while the easily shearable planar layers provide dry lubrication for industrial machinery."
                    )
                )
            }
            
            // Topic 3: The Versatile Nature of Carbon
            if key.contains("versatile") || key.contains("catenation") || key.contains("tetravalen") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Catenation & Tetravalency",
                        content: "Carbon forms millions of compounds due to two unique properties: Catenation—carbon's unmatched ability to form strong, stable covalent bonds with other carbon atoms to yield straight chains, branched frameworks, and closed rings; and Tetravalency—its valency of four allows bonding with atoms of oxygen, hydrogen, nitrogen, sulphur, and halogens. Carbon-carbon bonds are extraordinarily strong and stable because carbon's small atomic radius enables its nucleus to hold shared electron pairs tightly."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Silicon vs. Carbon Chain Stability",
                        content: "While silicon also forms chains with hydrogen (silanes), its larger atomic radius results in weak, highly reactive Si—Si bonds that rarely exceed seven or eight atoms and decompose readily in air. In contrast, compact carbon atoms link infinitely into robust chains, forming the backbone of all organic molecules and living tissue."
                    )
                )
            }
            
            // Topic 4: Saturated, Unsaturated & Isomers (Fig 4.6 & Fig 4.7)
            if key.contains("saturated") || key.contains("unsaturated") || key.contains("isomer") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Saturated vs. Unsaturated Hydrocarbons & Isomers",
                        content: "Hydrocarbons containing only single C—C covalent bonds are called saturated hydrocarbons (alkanes, general formula CₙH₂ₙ₊₂); they are relatively unreactive. Hydrocarbons containing carbon-carbon double bonds (alkenes, CₙH₂ₙ) or triple bonds (alkynes, CₙH₂ₙ₋₂) are unsaturated hydrocarbons and exhibit higher chemical reactivity. Structural isomers are compounds having identical molecular formulas but completely different carbon skeletal arrangements, such as normal butane and isobutane (C₄H₁₀)."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Electron Dot Structure of Ethane (Fig 4.6)",
                        content: "In ethane (C₂H₆), the two carbon atoms link via a single covalent bond by sharing one electron pair, while their remaining three valence electrons each bond with hydrogen atoms, satisfying tetravalency through single covalent links only.",
                        imageName: "chem_carbon_ethane_dot_structure"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Structure of Ethene (Fig 4.7)",
                            content: "In ethene (C₂H₄), each carbon links to only two hydrogen atoms; to satisfy tetravalency, the two carbon atoms share two electron pairs to establish a double covalent bond (C=C), characteristic of unsaturated alkenes.",
                            imageName: "chem_carbon_ethene_lewis_structure"
                        )
                    ]
                )
            }
            
            // Topic 5: Functional Groups & Homologous Series
            if key.contains("functional group") || key.contains("homologous series") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Functional Groups & Homologous Series",
                        content: "In hydrocarbon chains, heteroatoms (halogens, oxygen, nitrogen, sulphur) replace hydrogen to form specific groups known as functional groups (e.g., -OH for alcohols, -CHO for aldehydes, -CO- for ketones, -COOH for carboxylic acids), which confer characteristic chemical properties to the molecule regardless of chain length. A homologous series is a family of organic compounds sharing the same functional group and general formula, where successive members differ by a -CH₂ unit (14 unified atomic mass units) and exhibit a gradual gradation in physical properties."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Gradation in the Alcohol Homologous Series",
                        content: "Methanol (CH₃OH), ethanol (C₂H₅OH), propanol (C₃H₇OH), and butanol (C₄H₉OH) all undergo identical chemical oxidation reactions because of the common hydroxyl (-OH) functional group. However, their boiling points and melting points increase systematically as molecular mass grows by 14 u with each added -CH₂ group, increasing intermolecular van der Waals forces."
                    )
                )
            }
            
            // Topic 6: Combustion & Oxidation
            if key.contains("combustion") || (key.contains("oxidation") && chap.contains("carbon")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Combustion & Chemical Oxidation of Carbon",
                        content: "All carbon allotropes and compounds combust in oxygen to produce carbon dioxide, water vapour, heat, and light [CH₄ + 2O₂ → CO₂ + 2H₂O + Heat + Light]. Saturated hydrocarbons undergo complete combustion with a clean blue flame in sufficient air, whereas unsaturated hydrocarbons burn with a yellow, sooty flame due to unburnt carbon particles. Alcohols undergo controlled chemical oxidation using alkaline potassium permanganate (KMnO₄) or acidified potassium dichromate (K₂Cr₂O₇) to synthesize carboxylic acids."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Bunsen Burner Flame & Sooty Combustion",
                        content: "When a gas stove's air holes are open, methane burns completely with a non-luminous blue flame. If the air vents become clogged, incomplete combustion yields a yellow flame that blackens vessel bottoms with sooty carbon deposits. In the laboratory, adding pink alkaline KMnO₄ to warm ethanol causes the colour to discharge as ethanol oxidises into ethanoic acid."
                    )
                )
            }
            
            // Topic 7: Addition & Substitution Reactions
            if key.contains("addition") || key.contains("substitution") || key.contains("hydrogenation") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Addition & Substitution Reaction Mechanisms",
                        content: "Unsaturated hydrocarbons undergo addition reactions across their double or triple bonds in the presence of nickel or palladium catalysts to yield saturated hydrocarbons; industrially, this hydrogenation converts liquid unsaturated vegetable oils into solid saturated fats. Conversely, saturated hydrocarbons are typically inert but undergo substitution reactions in the presence of sunlight, where chlorine atoms progressively replace hydrogen atoms one by one [CH₄ + Cl₂ → CH₃Cl + HCl]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Industrial Hydrogenation of Vegetable Oils",
                        content: "Vegetable oils contain long, kinked unsaturated fatty acid chains with C=C double bonds that keep them healthy and liquid at room temperature. Bubbling hydrogen gas through hot oil over a nickel catalyst adds hydrogen across the double bonds, straightening the chains into dense, solid saturated fats (vanaspati ghee)."
                    )
                )
            }
            
            // Topic 8: Reactions of Ethanol
            if key.contains("ethanol") && !key.contains("ester") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Chemical Properties & Reactions of Ethanol",
                        content: "Ethanol (C₂H₅OH) is a clear, volatile liquid, neutral to litmus, and an excellent organic solvent. It reacts with active sodium metal to evolve hydrogen gas with effervescence and produce sodium ethoxide [2Na + 2CH₃CH₂OH → 2CH₃CH₂ONa + H₂↑]. Heating ethanol at 443 K with excess concentrated sulphuric acid induces dehydration, where conc. H₂SO₄ acts as a dehydrating agent to strip water from ethanol and yield unsaturated ethene [CH₃CH₂OH → CH₂=CH₂ + H₂O]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Sodium Metal Test & Acidic Dehydration",
                        content: "Dropping a small pellet of metallic sodium into dry ethanol creates immediate effervescence as flammable hydrogen gas bubbles release, confirming the presence of an active hydroxyl proton. When heated strongly with concentrated sulphuric acid, the acid acts like a chemical sponge, forcibly wrenching an H and an OH from adjacent carbons to leave behind gaseous ethene."
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Formation of Ester Reaction Apparatus (Fig 4.11)",
                            content: "Heating ethanol with ethanoic acid in the presence of an acid catalyst in a water bath produces sweet, fruity-smelling ethyl ethanoate ester.",
                            imageName: "chem_carbon_ester_formation_apparatus"
                        )
                    ]
                )
            }
            
            // Topic 9: Ethanoic Acid & Esterification (Fig 4.11: Formation of Ester)
            if key.contains("ester") || (key.contains("ethanoic acid") && !key.contains("carbonate")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Ethanoic Acid & The Esterification Reaction",
                        content: "Ethanoic acid (CH₃COOH), commonly known as acetic acid, belongs to the carboxylic acid group. A 5-8% solution of acetic acid in water is commercial vinegar, used widely as a preservative. Pure ethanoic acid has a melting point of 290 K (17°C) and readily freezes into icelike crystals during winter, earning it the name glacial acetic acid. When ethanoic acid is heated with absolute ethanol in the presence of a few drops of concentrated sulphuric acid catalyst, they react in an esterification reaction to form ethyl ethanoate—a sweet, fruity-smelling ester [CH₃COOH + C₂H₅OH → CH₃COOC₂H₅ + H₂O]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Formation of Ester (Fig 4.11)",
                        content: "A reaction mixture of 1 mL glacial acetic acid, 1 mL absolute ethanol, and conc. H₂SO₄ is gently warmed inside a test tube immersed in a water bath beaker on a tripod stand. Pouring the warmed mixture into a beaker of water releases a sweet, fruity fragrance, confirming ester formation.",
                        imageName: "chem_carbon_ester_formation_apparatus"
                    )
                )
            }
            
            // Topic 10: Ethanoic Acid with Carbonates
            if key.contains("carbonate") && (key.contains("ethanoic") || chap.contains("carbon")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Ethanoic Acid Reactions with Carbonates",
                        content: "Unlike mineral acids, ethanoic acid is a weak acid that only partially ionizes in aqueous solution. However, it reacts vigorously with sodium carbonate and sodium hydrogencarbonate (baking soda) to produce sodium ethanoate (sodium acetate), water, and carbon dioxide gas with brisk effervescence [2CH₃COOH + Na₂CO₃ → 2CH₃COONa + H₂O + CO₂↑; CH₃COOH + NaHCO₃ → CH₃COONa + H₂O + CO₂↑]. The evolved CO₂ turns lime water milky."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Brisk Effervescence & Lime Water Confirmation",
                        content: "Adding a spoonful of baking soda into ethanoic acid causes rapid foaming and fizzing as bubbles of carbon dioxide gas surge out. Channelling this gas through a delivery tube into clear lime water precipitates insoluble calcium carbonate, turning the lime water milky white just like hydrochloric acid does."
                    )
                )
            }
            
            // Topic 11: Soaps, Micelles & Detergents (Fig 4.12: Formation of Micelles)
            if key.contains("soap") || key.contains("micelle") || key.contains("detergent") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Structure of Soaps, Micelles & Cleansing Action",
                        content: "Soaps are sodium or potassium salts of long-chain carboxylic acids (e.g., sodium stearate, C₁₇H₃₅COO⁻Na⁺). A soap molecule is amphiphilic: it possesses a long, non-polar hydrophobic hydrocarbon 'tail' that repels water but dissolves in oily dirt, and a short, polar hydrophilic ionic 'head' (-COO⁻Na⁺) that dissolves in water. In aqueous solution, soap molecules self-assemble into spherical aggregates called micelles, where the hydrophobic tails point inward to entrap oily grease droplets in the center, while ionic heads remain exposed to water, forming a stable emulsion that rinses away."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Formation of Micelles (Fig 4.12)",
                        content: "Diagram showing soap molecules arrayed radially around a central oily dirt droplet. The hydrophobic hydrocarbon tails anchor into the oil droplet while the negatively charged ionic heads (Na⁺ counter-ions) project outward into the surrounding water, electrostatically repelling adjacent micelles to prevent coagulation.",
                        imageName: "chem_carbon_micelle_formation"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Hard Water Scum & Synthetic Detergents",
                            content: "Hard water contains dissolved Ca²⁺ and Mg²⁺ ions which react with soap to form an insoluble curdy precipitate called scum, wasting soap and sticking to fabric. Synthetic detergents—sodium salts of sulphonic acids or ammonium salts with chlorides/bromides—do not form insoluble precipitates with calcium or magnesium, lathering effortlessly even in hard water."
                        )
                    ]
                )
            }
        }
        
        // ==========================================
        // MARK: - Class 10 Chemistry: Metals and Non-metals (Ch 3)
        // ==========================================
        let isChapter3 = chap.contains("metal") || key.contains("metals and non-metals")
            || key.contains("physical properties of metals")
            || key.contains("amphoteric")
            || (key.contains("metal") && key.contains("steam"))
            || key.contains("aqua regia")
            || key.contains("reactivity series")
            || (key.contains("ionic compounds") && (key.contains("formation") || key.contains("physical properties") || key.contains("nature")))
            || key.contains("metallurgy") || key.contains("roasting") || key.contains("calcination") || key.contains("extraction of metals")
            || key.contains("electrolytic refining")
            || key.contains("galvanis") || key.contains("galvaniz") || key.contains("alloying") || (key.contains("corrosion") && key.contains("prevention"))

        if isChapter3 {
            // Topic 1: Physical Properties of Metals, Non-metals, and Their Exceptions (Fig 3.1 & Fig 3.2)
            if ((key.contains("physical properties") || key.contains("properties of metals")) && !key.contains("ionic")) || key.contains("exceptions") || key.contains("malleability") || key.contains("ductility") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Metallic Physical Properties & Exceptions",
                        content: "Metals exhibit malleability, ductility, sonority, and high thermal and electrical conductivity. However, physical properties have key exceptions: mercury is liquid at room temperature, gallium and caesium melt in the palm of a hand, iodine is a lustrous non-metal, diamond is an extremely hard non-metal, graphite conducts electricity, and alkali metals (Li, Na, K) can be sliced with a knife."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Thermal Conduction & Wax Pin Experiment",
                        content: "Heating one end of a clamped metal wire conducts thermal energy along its length to melt wax at the free end, causing an attached pin to drop while the metal remains solid, proving metals conduct heat with high melting points.",
                        imageName: "chem_metal_heat_conduction"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Electrical Conductivity Circuit Test",
                            content: "Inserting metal specimens between terminal clips A and B in an electric circuit with a 6V battery completes the conduction path, instantly illuminating the indicator bulb due to free mobile valence electrons.",
                            imageName: "chem_metal_electrical_conductivity"
                        )
                    ]
                )
            }
            
            // Topic 2: Chemical Reactivity of Metals with Oxygen and Amphoteric Oxides
            if key.contains("amphoteric") || (key.contains("oxygen") && key.contains("metal")) || key.contains("reactivity of metals with oxygen") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Metal Oxidation & Amphoteric Oxides",
                        content: "Metals combine with oxygen to form basic metal oxides. Amphoteric oxides—such as aluminium oxide (Al₂O₃) and zinc oxide (ZnO)—react with both acids and bases to yield salt and water [Al₂O₃ + 2NaOH → 2NaAlO₂ + H₂O]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Differential Metal Oxidation & Passivation",
                        content: "Sodium and potassium ignite spontaneously in air and must be stored under kerosene oil. In contrast, aluminium cookware forms a self-passivating, impermeable oxide film (Al₂O₃) that shields underlying metal from further atmospheric corrosion."
                    )
                )
            }
            
            // Topic 3: Chemical Reactions of Metals with Water and Steam (Fig 3.3: Action of Steam on Metal)
            if key.contains("steam") || (key.contains("water") && key.contains("metal")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Metal Reactions with Water & Steam",
                        content: "Metals react with water to generate metal hydroxides or oxides plus hydrogen gas. Highly reactive alkali metals (Na, K) react violently with cold water; magnesium requires hot water; while metals like iron and aluminium react only with steam to produce metal oxides [3Fe + 4H₂O(g) → Fe₃O₄ + 4H₂]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Action of Steam on Metal Apparatus",
                        content: "Heating water-soaked glass wool in a boiling tube generates steam over a heated metal sample; evolved hydrogen gas travels through the delivery tube and is collected by downward displacement of water in an inverted gas jar.",
                        imageName: "chem_metal_action_of_steam"
                    )
                )
            }
            
            // Topic 4: Reaction of Metals with Acids and Aqua Regia
            if key.contains("aqua regia") || (key.contains("acid") && key.contains("metal")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Acid Reactions with Metals & Aqua Regia",
                        content: "Active metals react with dilute acids to evolve hydrogen gas, but nitric acid (HNO₃) suppresses H₂ evolution by oxidising it into water while reducing to nitrogen oxides (NO₂/NO). Aqua Regia—a fresh 3:1 mixture of concentrated HCl and HNO₃—is a fuming reagent powerful enough to dissolve inert noble metals like gold and platinum."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Aqua Regia & Dilute Acid Reactivity",
                        content: "While copper fails to displace hydrogen from dilute HCl and gold resists pure concentrated acids, jewellers use freshly mixed Aqua Regia (royal water) to dissolve and refine pure gold ornaments through nascent chlorine coordination."
                    )
                )
            }
            
            // Topic 5: The Reactivity Series and Displacement Reactions (Fig 3.4: Electrochemistry Test Tube Experiment)
            if key.contains("reactivity series") || (key.contains("reactivity") && key.contains("displacement")) || key.contains("displacement") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "The Reactivity Series & Displacement",
                        content: "The reactivity series arranges metals in descending order of chemical activity (K > Na > Ca > Mg > Al > Zn > Fe > Pb > [H] > Cu > Hg > Ag > Au). A metal higher in the series displaces any less reactive metal from its aqueous salt solution [Fe + CuSO₄ → FeSO₄ + Cu]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Iron Nail in Copper Sulphate vs. Reverse Setup",
                        content: "Suspending an iron nail in blue copper sulphate solution causes reddish-brown copper to plate onto the nail while the solution fades to pale green iron sulphate. Conversely, a copper wire immersed in iron sulphate undergoes zero reaction.",
                        imageName: "chem_metal_reactivity_displacement_test"
                    )
                )
            }
            
            // Topic 6: Formation and Chemical Nature of Ionic Compounds
            if (key.contains("formation") || key.contains("chemical nature")) && key.contains("ionic") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Formation of Ionic Electrovalent Bonds",
                        content: "Ionic compounds form when electropositive metal atoms transfer valence electrons to electronegative non-metal atoms to achieve stable octet noble gas configurations. The resulting cations and anions bind via omnidirectional electrostatic forces into rigid 3D crystalline lattices [Na⁺ + Cl⁻ → NaCl]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Electron Transfer in NaCl & MgCl₂ Formation",
                        content: "A neutral sodium atom (2,8,1) donates its lone valence electron to chlorine (2,8,7), transforming both into stable isoelectronic ions (Na⁺ and Cl⁻) that snap together electrostatically like microscopic magnets to build salt crystals."
                    )
                )
            }
            
            // Topic 7: Physical Properties of Ionic Compounds (Fig 3.7 & Fig 3.8)
            if key.contains("ionic") && (key.contains("physical") || key.contains("properties")) {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Physical Properties of Ionic Compounds",
                        content: "Ionic compounds are hard, brittle crystalline solids with high melting and boiling points due to powerful electrostatic lattice forces. They dissolve readily in polar water but resist non-polar organic solvents, and conduct electricity exclusively when molten or dissolved in water where mobile ions can move."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Heating Salt on Spatula (Flame & Melting Test)",
                        content: "Placing sodium chloride or calcium chloride crystals on a metal spatula directly over a roaring burner flame demonstrates extreme thermal stability: the crystals resist melting even at hundreds of degrees Celsius while imparting characteristic flame colouration.",
                        imageName: "chem_metal_ionic_salt_heating_spatula"
                    ),
                    additionalCards: [
                        DynamicFlashcard(
                            title: "Salt Solution Electrical Conductivity Circuit",
                            content: "While dry solid salt crystals are complete electrical insulators, dissolving them in water releases free-floating Na⁺ and Cl⁻ ions that migrate across graphite electrodes to complete the circuit and illuminate the testing bulb.",
                            imageName: "chem_metal_ionic_solution_conductivity"
                        )
                    ]
                )
            }
            
            // Topic 8: Extraction of Metals (Metallurgy): Roasting, Calcination, and Reduction
            if key.contains("metallurgy") || key.contains("roasting") || key.contains("calcination") || key.contains("extraction") || key.contains("reduction") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Metallurgy: Roasting, Calcination & Reduction",
                        content: "Extracting metals from ores involves converting ores to oxides via Roasting (heating sulphide ores in excess air) or Calcination (heating carbonate ores in limited air), followed by carbon reduction or exothermic Thermit displacement [Fe₂O₃ + 2Al → 2Fe(l) + Al₂O₃ + Heat]."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Thermit Railway Welding & Pyrometallurgy",
                        content: "Igniting aluminium powder with iron(III) oxide unleashes an intense thermit reaction reaching over 2500°C, producing a stream of incandescent molten iron that flows directly into gaps between cracked railway tracks to weld them seamlessly."
                    )
                )
            }
            
            // Topic 9: Electrolytic Refining of Metals (Fig 3.11: Electrolytic Refining of Copper)
            if key.contains("electrolytic refining") || key.contains("refining") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Electrolytic Refining of Metals",
                        content: "Electrolytic refining purifies crude metals using an electrolytic cell: an impure metal block acts as the anode, a thin strip of pure metal serves as the cathode, and an acidified metal salt solution acts as electrolyte. Current dissolves pure metal from the anode and plates it onto the cathode, leaving insoluble impurities as anode mud."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Electrolytic Copper Refining Cell Setup",
                        content: "In a copper refining tank, electric current transfers Cu²⁺ ions from an impure copper anode across acidified copper sulphate to plate 99.99% pure copper onto the cathode, while precious insoluble gold and silver particles drop to the tank floor as anode mud.",
                        imageName: "chem_metal_electrolytic_refining_copper"
                    )
                )
            }
            
            // Topic 10: Corrosion and Prevention through Galvanisation and Alloying (Fig 3.13: Conditions for Rusting)
            if key.contains("corrosion") || key.contains("galvanis") || key.contains("galvaniz") || key.contains("alloying") || key.contains("rust") {
                return DualPillarFlashcards(
                    theoryCard: DynamicFlashcard(
                        title: "Corrosion Mechanisms & Alloy Protection",
                        content: "Corrosion deteriorates metals via ambient oxidation; iron rusts into hydrated ferric oxide [Fe₂O₃·xH₂O] only when simultaneously exposed to oxygen and water. Protection methods include sacrificial zinc galvanisation and alloying—blending metals to modify properties, such as forging iron with chromium and nickel into corrosion-proof stainless steel."
                    ),
                    analogyCard: DynamicFlashcard(
                        title: "Investigating Conditions for Iron Rusting (Tubes A, B, C)",
                        content: "Iron nails rust heavily in Test Tube A (exposed to both air and water), but stay completely pristine in Test Tube B (boiled water with an air-excluding oil barrier) and Test Tube C (sealed in bone-dry air with anhydrous calcium chloride).",
                        imageName: "chem_metal_iron_rusting_conditions"
                    )
                )
            }
        }
        
        // ==========================================
        // MARK: - Class 10 Chemistry: Chemical Reactions and Equations (Ch 1)
        // ==========================================
        
        // Topic 1: Chemical Reactions and Everyday Observations (Fig 1.2: Hydrogen Gas Formation Apparatus)
        if key.contains("everyday observation") || (key.contains("chemical reaction") && key.contains("observation")) || key == "chemical reactions and everyday observations" {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Indicators of Chemical Reactions",
                    content: "A chemical reaction transforms reactants into new substances with distinct identities, confirmed by macroscopic indicators: evolution of gas, temperature shift, colour change, or state transition."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Acid-Zinc Reaction & Gas Evolution",
                    content: "When dilute sulphuric acid reacts with zinc granules in a conical flask, hydrogen gas vigorously bubbles out through the glass delivery tube while the flask turns noticeably warm.",
                    imageName: "chem_rxn_hydrogen_apparatus"
                )
            )
        }
        
        // Topic 2: Chemical Equations and Conservation of Mass
        if key.contains("chemical equation") || key.contains("conservation of mass") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Law of Conservation of Mass",
                    content: "Matter can neither be created nor destroyed in a chemical reaction. The total number of atoms of each element must remain strictly identical on both reactant and product sides of a balanced equation."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Atomic Bookkeeping in Equations",
                    content: "Writing a balanced equation like 3Fe + 4H₂O → Fe₃O₄ + 4H₂ ensures every iron, oxygen, and hydrogen atom in the reactants is accounted for in the products without losing mass."
                )
            )
        }
        
        // Topic 3: Combination Reactions (Fig 1.3: Slaked Lime Formation in Beaker)
        if key.contains("combination") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Combination Reaction Principle",
                    content: "A combination reaction is a chemical process where two or more distinct reactants (elements or compounds) unite to synthesize a single compound product (A + B → AB)."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Quicklime Reaction & Slaked Lime Formation",
                    content: "Calcium oxide (quicklime) reacts vigorously with water to synthesize a single compound, slaked lime [Ca(OH)₂], releasing copious heat that makes the reaction beaker feel scorching hot.",
                    imageName: "chem_rxn_slaked_lime_formation"
                )
            )
        }
        
        // Topic 4: Exothermic and Endothermic Reactions (Fig 1.3: Slaked Lime Heat Evolution)
        if key.contains("exothermic") || key.contains("endothermic") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Exothermic vs. Endothermic Exchange",
                    content: "Exothermic reactions release thermal energy into their surroundings, raising the temperature. Endothermic reactions absorb heat, light, or electrical energy to break chemical bonds in reactants."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Exothermic Slaking of Quicklime",
                    content: "When water is slowly poured onto quicklime, an energetic exothermic reaction unleashes intense heat into the beaker, demonstrating how chemical bond restructuring releases thermal energy.",
                    imageName: "chem_rxn_slaked_lime_formation"
                )
            )
        }
        
        // Topic 5: Decomposition Reactions (Fig 1.5, Fig 1.7, Fig 1.6)
        if key.contains("decompos") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Decomposition Reaction Mechanism",
                    content: "A decomposition reaction occurs when a single reactant breaks down into two or more simpler substances upon absorbing energy in the form of heat, light, or electricity (AB → A + B)."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Thermal Decomposition of Lead Nitrate",
                    content: "Heating dry lead nitrate powder in a boiling tube decomposes it into yellow lead monoxide, oxygen, and dense, pungent brown fumes of nitrogen dioxide gas [2Pb(NO₃)₂ → 2PbO + 4NO₂ + O₂].",
                    imageName: "chem_rxn_lead_nitrate_decomposition"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Photolytic Decomposition in Sunlight",
                        content: "White silver chloride placed in a China dish near a sunny window absorbs solar photons and decomposes into grey elemental silver metal and chlorine gas [2AgCl → 2Ag + Cl₂].",
                        imageName: "chem_rxn_silver_chloride_sunlight"
                    ),
                    DynamicFlashcard(
                        title: "Electrolytic Decomposition of Water",
                        content: "Electric current driven through acidified water splits H₂O into hydrogen gas at the cathode and oxygen gas at the anode in an exact 2:1 volume ratio [2H₂O → 2H₂ + O₂].",
                        imageName: "chem_rxn_electrolysis_water"
                    )
                ]
            )
        }
        
        // Topic 6: Displacement Reactions (Fig 1.8: Iron Nails in Copper Sulphate)
        if key.contains("displacement") && !key.contains("double") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Displacement & Chemical Reactivity",
                    content: "A displacement reaction is a chemical process where a more reactive metal takes the place of a less reactive metal in its aqueous salt compound, dictated by the reactivity series."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Iron Nails in Copper Sulphate Solution",
                    content: "Clean iron nails dipped in bright blue copper sulphate become coated with reddish-brown copper, while the solution fades to pale green ferrous sulphate (Fe + CuSO₄ → FeSO₄ + Cu).",
                    imageName: "chem_rxn_iron_copper_sulphate_result"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Displacement Reaction Apparatus",
                        content: "Laboratory setup showing two clean iron nails tied with thread and suspended inside a test tube containing aqueous copper sulphate solution for 20 minutes.",
                        imageName: "chem_rxn_iron_copper_sulphate_setup"
                    )
                ]
            )
        }
        
        // Topic 7: Double Displacement and Precipitation Reactions (Fig 1.9: Barium Sulphate Precipitation)
        if key.contains("double displacement") || key.contains("precipitation") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Double Displacement & Ion Exchange",
                    content: "A double displacement reaction involves a mutual exchange of ions between two reacting aqueous solutions. The formation of an insoluble solid product defines a precipitation reaction."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Barium Sulphate Precipitation",
                    content: "Pouring clear sodium sulphate solution into clear barium chloride solution triggers an instantaneous ion exchange, forming a thick white precipitate of insoluble barium sulphate (Na₂SO₄ + BaCl₂ → BaSO₄↓ + 2NaCl).",
                    imageName: "chem_rxn_barium_sulphate_precipitation"
                )
            )
        }
        
        // Topic 9: Everyday Effects of Oxidation: Corrosion and Rancidity (Must check before general oxidation)
        if key.contains("corrosion") || key.contains("rancidity") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Corrosion & Rancidity Mechanisms",
                    content: "Corrosion is the slow degradation of metals caused by aerial oxygen and moisture. Rancidity is the aerial oxidation of unsaturated fats and oils in foods, creating unpleasant smells and tastes."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Oxidation of Iron & Copper in Air",
                    content: "Exposing iron to moist air oxidizes it into flaky reddish-brown rust [Fe₂O₃·xH₂O], while copper develops a green patina. Flushing snack bags with inert nitrogen gas prevents food oil oxidation.",
                    imageName: "chem_rxn_copper_oxidation"
                )
            )
        }
        
        // Topic 8: Oxidation, Reduction, and Redox Reactions (Fig 1.10: Copper Oxidation & Fig 1.6: Electrolysis Redox)
        if key.contains("redox") || (key.contains("oxidation") && key.contains("reduction")) || key.contains("oxidation") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Simultaneous Oxidation & Reduction",
                    content: "Oxidation is the gain of oxygen or loss of electrons, while reduction is the loss of oxygen or gain of electrons. Because electron transfer is reciprocal, both must occur simultaneously."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Surface Oxidation of Copper Powder",
                    content: "Heating reddish-brown copper powder in a China dish over a burner causes surface copper atoms to bond with oxygen, forming a jet-black layer of copper(II) oxide [2Cu + O₂ → 2CuO].",
                    imageName: "chem_rxn_copper_oxidation"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Electrolysis & Redox Mechanism",
                        content: "Water decomposes via simultaneous redox: Oxygen gas forms at the positive anode via oxidation, while hydrogen gas is released at the negative cathode via reduction.",
                        imageName: "chem_rxn_electrolysis_water"
                    )
                ]
            )
        }
        
        // ==========================================
        // MARK: - Class 10 Chemistry: Acids, Bases and Salts (Ch 2)
        // ==========================================
        
        // Topic 1: Acid-Base Indicators and Sensory Properties
        if key.contains("indicator") || (key.contains("sensory") && key.contains("properties")) {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Acid-Base Indicators Principle",
                    content: "Acids taste sour and turn blue litmus red, whereas bases taste bitter, feel soapy, and turn red litmus blue. Natural, synthetic, and olfactory indicators detect acids or bases through distinct colour or scent changes."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Curry Stains & Olfactory Detection",
                    content: "A yellow turmeric curry stain on a cloth turns reddish-brown when scrubbed with basic soap, reverting to yellow on rinsing. Similarly, onion and clove oil lose their characteristic scents in basic solutions."
                )
            )
        }
        
        // Topic 2: Chemical Reactions of Acids and Bases with Metals, Carbonates, and Oxides (Fig 2.1 & Fig 2.2)
        if (key.contains("metal") && key.contains("carbonate")) || key.contains("chemical reactions of acids") || (key.contains("acid") && key.contains("metal")) {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Acid Reactions with Metals & Carbonates",
                    content: "Acids react with active metals to produce a salt and hydrogen gas (Zn + H₂SO₄ → ZnSO₄ + H₂), and with metal carbonates to yield a salt, water, and carbon dioxide (Na₂CO₃ + 2HCl → 2NaCl + H₂O + CO₂)."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Zinc & Acid Hydrogen Evolution",
                    content: "Granulated zinc reacting with dilute sulphuric acid vigorously evolves hydrogen gas; when piped through soap solution, the hydrogen-filled bubbles rise and detonate with a distinct pop sound.",
                    imageName: "chem_acid_zinc_hydrogen_test"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Carbon Dioxide Lime Water Test",
                        content: "Passing carbon dioxide gas generated from metal carbonates through clear lime water turns it milky due to insoluble calcium carbonate precipitation [Ca(OH)₂ + CO₂ → CaCO₃↓ + H₂O].",
                        imageName: "chem_acid_carbonate_co2_test"
                    )
                ]
            )
        }
        
        // Topic 3: Neutralisation and the Ionic Nature of Acids and Bases (Fig 2.3 & Fig 2.4)
        if key.contains("neutralis") || key.contains("neutraliz") || key.contains("ionic nature") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Ionic Dissociation & Neutralisation",
                    content: "Acids produce hydronium ions [H₃O⁺] in water, whereas bases release hydroxide ions [OH⁻]. Neutralisation is their fundamental ionic union to synthesize neutral water and a salt [H⁺ + OH⁻ → H₂O]."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Aqueous Acid Electrical Conductivity",
                    content: "Aqueous hydrochloric acid conducts electric current through free mobile hydrogen ions [H⁺(aq)], completing the electric circuit and causing the testing bulb to glow brightly.",
                    imageName: "chem_acid_circuit_conductivity"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Dry vs. Moist Litmus HCl Test",
                        content: "Completely dry HCl gas fails to turn dry blue litmus red, but instantly turns moist blue litmus red because acids require aqueous moisture to dissociate and release acidic H⁺ ions.",
                        imageName: "chem_acid_hcl_gas_litmus_test"
                    )
                ]
            )
        }
        
        // Topic 4: Concentration, Dilution, and Exothermic Mixing (Fig 2.5: Corrosive Warning Sign)
        if key.contains("dilution") || key.contains("exothermic mixing") || key.contains("concentration, dilution") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Acid Dilution & Hydronium Concentration",
                    content: "Dilution decreases the concentration of hydronium [H₃O⁺] or hydroxide [OH⁻] ions per unit volume. The process is intensely exothermic, risking explosive acid splashing if water is poured into acid."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Corrosive Acid Hazard & Dilution Warning",
                    content: "Container warning labels caution that dissolving concentrated acids or bases in water unleashes violent heat. Concentrated acid must always be added slowly to water with constant stirring, never water to acid.",
                    imageName: "chem_acid_corrosive_warning_sign"
                )
            )
        }
        
        // Topic 6: Importance of pH in Everyday Life (Fig 2.7: Textbook pH Scale Benchmark) - Checked before general pH
        if key.contains("everyday life") && key.contains("ph") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Biological & Environmental pH Homeostasis",
                    content: "Biological organisms and ecosystems require optimal pH windows to function. Shifts below pH 5.6 cause toxic acid rain, while localized neutralisation reactions protect human tissue and maintain crop soil health."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Physiological & Everyday pH Regulation",
                    content: "Living systems survive within narrow pH bounds: stomach acid (~1.2) is neutralised by basic antacids, tooth decay begins when mouth pH falls below 5.5, and bee stings are soothed with mild baking soda.",
                    imageName: "chem_acid_ph_substances_infographic"
                )
            )
        }
        
        // Topic 5: The pH Scale and Acid-Base Strength (Fig 2.6 & Fig 2.7)
        if key.contains("ph scale") || (key.contains("ph") && key.contains("strength")) {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "The pH Metric & Acid Strength",
                    content: "pH quantitatively measures hydronium ion concentration on a logarithmic scale. Strong acids dissociate completely in water to yield high H⁺ concentrations, whereas weak acids dissociate only partially."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Continuous pH Spectrum & Ion Trends",
                    content: "The pH scale from 0 to 14 maps hydronium concentration: pH values below 7 reflect increasing acidic H⁺ ion concentration, while values above 7 indicate increasing basic OH⁻ ion concentration.",
                    imageName: "chem_acid_ph_scale_trends"
                ),
                additionalCards: [
                    DynamicFlashcard(
                        title: "Textbook pH Scale Benchmark",
                        content: "Universal indicator benchmark scale showing gastric juice (~1.2), lemon juice (~2.2), pure water and blood (7.4), milk of magnesia (10), and concentrated sodium hydroxide solution (14).",
                        imageName: "chem_acid_ph_substances_infographic"
                    )
                ]
            )
        }
        
        // Topic 7: Chemicals Derived from Common Salt (Fig 2.8: Chlor-Alkali Process)
        if key.contains("common salt") || key.contains("chlor-alkali") || key.contains("derived from salt") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Common Salt as Chemical Feedstock",
                    content: "Sodium chloride serves as the primary raw material for industrial synthesis: chlor-alkali electrolysis yields sodium hydroxide, chlorine, and hydrogen, which in turn form bleaching powder, baking soda, and washing soda."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Chlor-Alkali Industrial Membrane Cell",
                    content: "Electrolysing aqueous brine (sodium chloride) drives chlorine gas evolution at the anode, hydrogen gas at the cathode, and sodium hydroxide solution near the cathode [2NaCl + 2H₂O → 2NaOH + Cl₂ + H₂].",
                    imageName: "chem_salt_chlor_alkali_process"
                )
            )
        }
        
        // Topic 8: Water of Crystallisation and Plaster of Paris (Fig 2.9: Removing Water of Crystallisation)
        if key.contains("crystallis") || key.contains("crystalliz") || key.contains("plaster of paris") || key.contains("gypsum") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Hydrated Crystals & Plaster of Paris",
                    content: "Water of crystallisation is the fixed number of water molecules bound in one formula unit of a salt. Heating gypsum at 373 K removes water to form Plaster of Paris [CaSO₄·½H₂O], which sets hard upon rehydration."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Removing Water of Crystallisation",
                    content: "Heating blue hydrated copper sulphate in a dry boiling tube expels chemically bound water droplets onto the tube walls, transforming the vibrant blue crystals into white anhydrous copper sulphate.",
                    imageName: "chem_salt_water_crystallisation"
                )
            )
        }
        
        // 2. Refraction of Light (Class 10 Physics)
        if key.contains("refract") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Snell's Law & Optical Refraction",
                    content: "Refraction is the directional bending of light when obliquely transitioning between media of differing optical densities. This deflection occurs because light changes its velocity upon entering a new medium."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Bent Pencil in Water & Optical Density",
                    content: "A pencil submerged in water appears broken at the surface because light waves slow down and bend away from the normal as they exit denser water into air."
                )
            )
        }
        
        // 3. Why the Sky Appears Blue (Class 10 Physics)
        if key.contains("sky") || key.contains("blue") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Rayleigh Atmospheric Scattering",
                    content: "Atmospheric gas molecules scatter electromagnetic radiation with an intensity inversely proportional to the fourth power of its wavelength. Consequently, shorter blue visible wavelengths scatter far more efficiently than longer red wavelengths."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Prismatic Blue Scattering vs. Space Darkness",
                    content: "Tiny air molecules scatter short blue sunlight toward our eyes from every direction, while astronauts in airless space see a pitch-black sky because no particles exist to scatter light."
                )
            )
        }
        
        // 4. Role of Villi in Digestion (Class 10 Biology)
        if key.contains("villi") || (key.contains("digest") && key.contains("enzyme")) {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Intestinal Villi & Absorption Surface",
                    content: "Villi are millions of vascularized, microscopic finger-like projections lining the inner small intestine. They multiply the total absorptive surface area to accelerate the uptake of digested nutrients."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Microvascular Nutrient Transfer Mechanism",
                    content: "Like the dense fibers of a plush sponge soaking water, villi maximize contact with digested chyme, funneling glucose and amino acids directly into dense capillary networks for body-wide cellular delivery."
                )
            )
        }
        
        // 5. Muscle Cramps (Respiration) (Class 10 Biology)
        if key.contains("cramp") || key.contains("respirat") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Anaerobic Lactic Acid Fermentation",
                    content: "When cellular respiration demand exceeds available oxygen, pyruvate breaks down anaerobically in muscle tissue. This pathway enzymatically converts pyruvate into three-carbon lactic acid, yielding emergency ATP without oxygen."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Sprinting Oxygen Debt & Cramp Mechanism",
                    content: "During an all-out sprint, muscles consume oxygen faster than lungs can supply it. This forces muscle fibers into anaerobic glycolysis, building up acidic lactic acid that triggers painful cramping spasms."
                )
            )
        }
        
        // 6. Double Coincidence of Wants (Class 10 Economics)
        if key.contains("coincidence") || key.contains("medium of exchange") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Double Coincidence of Wants",
                    content: "In a direct barter economy, trade requires a double coincidence of wants: each transacting party must simultaneously desire the specific surplus commodity that the other is willing to exchange."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Barter Gridlock & The Money Solution",
                    content: "If a shoemaker needs wheat but the farmer wants pots, direct barter deadlocks completely. Money resolves this impasse by acting as a universal medium of exchange accepted by all producers."
                )
            )
        }
        
        // 7. Modern Forms of Money (Class 10 Economics)
        if key.contains("modern forms") || key.contains("currency") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Fiat Currency & Legal Tender",
                    content: "Modern currency comprises paper notes and coins possessing no intrinsic commodity value. It functions effectively as money solely because a sovereign government officially legalizes and mandates it as tender."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Sovereign Guarantee & Digital Ledger Trust",
                    content: "A printed bill is worthless paper until stamped with the central bank’s legal promise to pay the bearer. This sovereign guarantee allows paper currency and UPI digital balances to settle transactions instantly."
                )
            )
        }
        
        // 8. Collateral in Loans (Class 10 Economics)
        if key.contains("collateral") || key.contains("terms of credit") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Credit Collateral & Lender Security",
                    content: "Collateral is an asset owned by a borrower—such as land, livestock, or property—pledged to a lender as security. It guarantees debt repayment and permits asset liquidation upon borrower default."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Mortgage Foreclosure & Credit Access",
                    content: "When a borrower deposits land deeds with a bank, the bank secures a legal lien. If loan installments fail, the bank recovers its principal by auctioning the pledged land."
                )
            )
        }
        
        // 9. Power Sharing in Democracy (Class 10 Civics)
        if key.contains("power sharing") || key.contains("power-sharing") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Democratic Power Sharing",
                    content: "Power sharing is the institutional distribution of state authority across diverse government organs, levels, and socio-linguistic groups. It neutralizes factional conflict and guarantees minority political participation."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Belgian Accommodation vs. Majoritarian Crisis",
                    content: "Belgium maintained social peace by dividing cabinet seats equally between Dutch and French leaders. Conversely, Sri Lanka’s majoritarian dominance triggered civil war, demonstrating that power sharing preserves national unity."
                )
            )
        }
        
        // 10. Non-Cooperation Movement (Class 10 History)
        if key.contains("non-cooperation") || key.contains("khilafat") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Satyagraha Non-Cooperation Principle",
                    content: "The Non-Cooperation doctrine asserts that colonial dominance survives exclusively through the voluntary compliance of the subjugated population. Orderly withdrawal of that cooperation systematically dismantles the regime’s administrative capacity."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Boycott of Foreign Cloth & Civil Disobedience",
                    content: "When millions of Indians boycotted government courts, surrendered imperial titles, and burned imported British textiles to wear homespun Khadi, the economic and governing machinery of the colonial state rapidly collapsed."
                )
            )
        }
        
        // 11. Newton's Third Law (Class 9 Physics Core Benchmark)
        if key.contains("newton") {
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: "Newton's Third Law of Motion",
                    content: "To every action force, there is always an equal and opposite reaction force. Forces occur exclusively in matched, simultaneous pairs acting on two mutually interacting physical bodies."
                ),
                analogyCard: DynamicFlashcard(
                    title: "Skateboard Recoil & Ground Propulsion",
                    content: "When leaping forward off a skateboard, your feet exert a forceful backward action on the deck. The board rolls backward, while the equal reaction force propels your body forward into the air."
                )
            )
        }
        
        // Dynamic Fallback: Generated from Chapter JSON Data
        let matchedTopic = topicObject ?? CurriculumCatalog.shared.topic(withTitle: topic)
        if let item = matchedTopic {
            let theoryText = formatSentenceLimit(item.coreIdeaIB, maxWords: 35)
            let analogyRaw: String
            if !item.causeEffectParakh.isEmpty {
                analogyRaw = item.causeEffectParakh
            } else if !item.sampleParakhOnlyAnswer.isEmpty {
                analogyRaw = "For example: \(item.sampleParakhOnlyAnswer)."
            } else {
                analogyRaw = "Demonstrate the cause-and-effect relationship in \(item.title) through a concrete real-world observation or practical experiment."
            }
            let analogyText = formatSentenceLimit(analogyRaw, maxWords: 40)
            
            return DualPillarFlashcards(
                theoryCard: DynamicFlashcard(
                    title: item.title,
                    content: theoryText.isEmpty ? "Articulate the foundational academic rule governing \(item.title) clearly and directly." : theoryText
                ),
                analogyCard: DynamicFlashcard(
                    title: "\(item.title) Mechanism & Application",
                    content: analogyText
                )
            )
        }
        
        // Generic Fallback
        return DualPillarFlashcards(
            theoryCard: DynamicFlashcard(
                title: "\(topic) Principle",
                content: "Articulate the foundational academic rule governing \(topic) using precise terminology and active verbs."
            ),
            analogyCard: DynamicFlashcard(
                title: "\(topic) Mechanism & Application",
                content: "Demonstrate the cause-and-effect relationship in \(topic) through a concrete real-world observation or practical experiment."
            )
        )
    }
    
    /// Ensures flashcard body conforms strictly to 1-2 sentences and max word count
    private static func formatSentenceLimit(_ text: String, maxWords: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }
        
        // Split by sentence terminators
        var sentences: [String] = []
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for part in parts {
            let s = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                sentences.append(s + ".")
            }
        }
        
        if sentences.isEmpty {
            sentences = [cleaned + "."]
        }
        
        // Take at most 2 sentences
        let candidate = Array(sentences.prefix(2)).joined(separator: " ")
        let words = candidate.split(separator: " ")
        if words.count <= maxWords {
            return candidate
        } else {
            let truncated = words.prefix(maxWords).joined(separator: " ")
            if !truncated.hasSuffix(".") && !truncated.hasSuffix("!") && !truncated.hasSuffix("?") {
                return truncated + "."
            }
            return truncated
        }
    }
}

// MARK: - Deterministic Feedback Generator

extension ConceptEvaluator {

    /// Maps the on-device model's true/false checklist onto the three feedback strings.
    /// No arithmetic: right = checks marked true; missing = required checks not marked true
    /// (or a keyPoint whose passRule failed when it has no required checks); vague = cause
    /// links or articulation checks marked false.
    static func feedbackReport(
        checklist: [String: Bool],
        concept: FeynmanConcept,
        articulationChecks: [ArticulationCheck]
    ) -> FeedbackReport {
        let passed: (String) -> Bool = { checklist[$0] == true }
        // Heaviest keyPoints first, so the most important gaps lead the sentence.
        let keyPoints = concept.keyPoints.enumerated()
            .sorted { ($0.element.weight, -$0.offset) > ($1.element.weight, -$1.offset) }
            .map(\.element)

        // What was right
        let rightItems = keyPoints
            .flatMap { $0.assessment.checks }
            .filter { passed($0.id) }
            .map { clause(from: $0.criterion) }

        // What was missing
        var missingItems: [String] = []
        for keyPoint in keyPoints {
            let checks = keyPoint.assessment.checks
            let required = checks.filter(\.isRequired)
            if required.isEmpty {
                if !passRuleMet(keyPoint.assessment, passed: passed),
                   let firstUnmet = checks.first(where: { !passed($0.id) }) {
                    missingItems.append(clause(from: firstUnmet.criterion))
                }
            } else {
                missingItems += required.filter { !passed($0.id) }.map { clause(from: $0.criterion) }
            }
        }

        // What was vague: facts stated but not connected, or not expressed clearly.
        var vagueParts: [String] = []
        if let link = concept.causeLinks.first(where: { link in
            link.isRequired && !passed(link.id) && link.linksChecks.contains(where: passed)
        }) {
            vagueParts.append("You stated the facts but didn't link the cause to the effect. \(imperative(from: link.criterion))")
        }
        vagueParts += articulationChecks.filter { !passed($0.id) }.map { imperative(from: $0.criterion) }

        return FeedbackReport(
            missing: missingItems.isEmpty ? "" : "You still need to explain: \(list(missingItems)).",
            vague: vagueParts.joined(separator: " "),
            right: rightItems.isEmpty ? "" : "You accurately explained: \(list(rightItems))."
        )
    }

    private static func passRuleMet(_ assessment: FeynmanAssessment, passed: (String) -> Bool) -> Bool {
        let checks = assessment.checks
        let rule = assessment.passRule
        if rule == "anyOf" {
            return checks.contains { passed($0.id) }
        }
        if rule.hasPrefix("minCount:"), let n = Int(rule.dropFirst("minCount:".count)) {
            return checks.filter { passed($0.id) }.count >= n
        }
        // "allRequired" (or an unknown rule): every required check must pass.
        let required = checks.filter(\.isRequired)
        return required.isEmpty ? checks.contains { passed($0.id) } : required.allSatisfy { passed($0.id) }
    }

    /// Leading criterion verbs and their imperative forms.
    private static let criterionVerbs: [String: String] = [
        "States": "State", "Mentions": "Mention", "Names": "Name", "Explains": "Explain",
        "Notes": "Note", "Defines": "Define", "Describes": "Describe", "Distinguishes": "Distinguish",
        "Gives": "Give", "Connects": "Connect", "Contrasts": "Contrast", "Uses": "Use",
        "Lists": "List", "Identifies": "Identify", "Links": "Link", "Compares": "Compare"
    ]

    /// "States that Sinhala was made the only official language." -> "Sinhala was made the only official language"
    private static func clause(from criterion: String) -> String {
        var words = criterion.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if let first = words.first, criterionVerbs[first] != nil {
            words.removeFirst()
            if words.first == "that" { words.removeFirst() }
        }
        return words.isEmpty ? criterion : words.joined(separator: " ")
    }

    /// "Connects A to B." -> "Connect A to B."; "The answer is ..." -> "Make sure the answer is ..."
    private static func imperative(from criterion: String) -> String {
        var text = criterion.trimmingCharacters(in: .whitespaces)
        if !text.hasSuffix(".") { text += "." }
        let first = String(text.prefix(while: { $0 != " " }))
        if let verb = criterionVerbs[first] {
            return verb + text.dropFirst(first.count)
        }
        return "Make sure " + text.prefix(1).lowercased() + text.dropFirst()
    }

    /// Up to three items joined with "; ", then a count of the rest.
    private static func list(_ items: [String]) -> String {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0).inserted }
        let shown = unique.prefix(3).joined(separator: "; ")
        let rest = unique.count - 3
        return rest > 0 ? "\(shown); and \(rest) more point\(rest == 1 ? "" : "s")" : shown
    }
}
