//
//  ParakhGuardrailLayer.swift
//  Feynman Tutor Engine - Layer 2 (NaturalLanguage Framework)
//
//  Calculates structural parameters via Apple's native NaturalLanguage framework
//  (NLTagger & NLEmbedding) before passing data to the on-device Cognitive Engine.
//

import Foundation
import NaturalLanguage

public final class ParakhGuardrailLayer: @unchecked Sendable {
    
    public static let shared = ParakhGuardrailLayer()
    
    // Contraction & NCERT Microphone Homophone Dictionary
    private static let speechHomophones: [String: String] = [
        "can't": "cannot", "cant": "cannot", "won't": "will not", "doesn't": "does not",
        "don't": "do not", "isn't": "is not", "aren't": "are not", "didn't": "did not",
        "wouldn't": "would not", "couldn't": "could not", "shouldn't": "should not",
        // Microphone homophones for CBSE/NCERT terms
        "villy": "villi", "vili": "villi", "will i": "villi", "villai": "villi",
        "r.b.i.": "rbi", "r b i": "rbi", "are be eye": "rbi",
        "swarajya": "swaraj", "sooraj": "swaraj", "swarajh": "swaraj",
        "gandhi ji": "gandhiji", "barter system": "barter", "bater": "barter",
        "piruvate": "pyruvate", "pie ruvate": "pyruvate", "lactic-acid": "lactic acid",
        "red ox": "redox", "read ox": "redox", "co-operate": "cooperate"
    ]
    
    // Topic Anchors for Analogy & Textbook embeddings across NCERT curriculum
    public struct TopicAnchors: Sendable {
        public let topic: String
        public let analogyAnchors: [String]
        public let textbookAnchors: [String]
        public let pillar1CoreTerms: [String]
        public let pillar2CauseTerms: [String]
        
        public init(
            topic: String,
            analogyAnchors: [String],
            textbookAnchors: [String],
            pillar1CoreTerms: [String] = [],
            pillar2CauseTerms: [String] = []
        ) {
            self.topic = topic
            self.analogyAnchors = analogyAnchors
            self.textbookAnchors = textbookAnchors
            self.pillar1CoreTerms = pillar1CoreTerms
            self.pillar2CauseTerms = pillar2CauseTerms
        }
    }
    
    private var anchorsRegistry: [String: TopicAnchors] = [
        "newton's third law of motion": TopicAnchors(
            topic: "Newton's Third Law of Motion",
            analogyAnchors: [
                "jumping off a small boat into the water pushes the boat backward",
                "stepping off a skateboard pushes the skateboard backwards while rolling you forward",
                "air escaping backwards out of a balloon pushes the balloon forward across the room",
                "pushing against a swimming pool wall launches you forward in the water",
                "recoil of a cannon or rifle kicking back into your shoulder when firing"
            ],
            textbookAnchors: [
                "to every action there is always an equal and opposite reaction",
                "for every action force there is an equal and opposite reaction force",
                "forces always occur in matched pairs acting on two different bodies simultaneously",
                "action reaction forces equal in magnitude opposite in direction"
            ],
            pillar1CoreTerms: ["action", "reaction", "forces", "equal", "opposite", "pair"],
            pillar2CauseTerms: ["push", "pushes", "backward", "forward", "accelerate", "move", "simultaneously", "different objects"]
        ),
        "double coincidence of wants": TopicAnchors(
            topic: "Double Coincidence of Wants",
            analogyAnchors: [
                "a farmer wanting shoes must find a shoemaker who specifically wants wheat",
                "trading a pencil for an eraser only works if both students need what the other has",
                "money solves the problem because everyone accepts cash as a medium instead of direct barter"
            ],
            textbookAnchors: [
                "double coincidence of wants is an essential feature of a barter economy",
                "money eliminates the need for double coincidence of wants by acting as a medium of exchange",
                "both parties must agree to buy and sell each other commodities"
            ],
            pillar1CoreTerms: ["want", "need", "desire", "both", "barter", "trade", "match", "simultaneously"],
            pillar2CauseTerms: ["money", "cash", "medium of exchange", "sell", "buy", "anyone", "eliminates"]
        ),
        "modern forms of money": TopicAnchors(
            topic: "Modern Forms of Money",
            analogyAnchors: [
                "a paper note is just paper, but the shopkeeper accepts it because the government promises its worth",
                "like a token at an arcade backed by the counter"
            ],
            textbookAnchors: [
                "currency notes have no intrinsic value of their own unlike gold coins",
                "authorized by the central government and Reserve Bank of India as legal tender"
            ],
            pillar1CoreTerms: ["paper", "currency", "note", "intrinsic", "no value", "precious metal"],
            pillar2CauseTerms: ["rbi", "reserve bank", "government", "authorized", "guarantee", "law", "legal tender"]
        ),
        "collateral in loans": TopicAnchors(
            topic: "Collateral in Loans",
            analogyAnchors: [
                "leaving your bicycle with your friend until you pay back the five dollars you borrowed",
                "if you do not pay, the bank sells your house or land to get their cash back"
            ],
            textbookAnchors: [
                "collateral is an asset owned by borrower pledged as a guarantee to the lender",
                "lender has right to sell or seize collateral upon loan default"
            ],
            pillar1CoreTerms: ["asset", "property", "gold", "land", "house", "security", "guarantee", "pledge"],
            pillar2CauseTerms: ["default", "fail", "repay", "sell", "seize", "recover", "auction"]
        ),
        "power sharing in democracy": TopicAnchors(
            topic: "Power Sharing in Democracy",
            analogyAnchors: [
                "letting everyone at the table choose one song on the car radio so nobody fights",
                "if the big group bullies the small group, the family falls apart"
            ],
            textbookAnchors: [
                "power sharing reduces the possibility of conflict between social groups",
                "tyranny of the majority undermines unity and political stability"
            ],
            pillar1CoreTerms: ["share", "sharing", "group", "community", "diverse", "representation", "reduce conflict"],
            pillar2CauseTerms: ["majority", "minority", "tyranny", "dominance", "undermines", "unity", "stability"]
        ),
        "refraction of light": TopicAnchors(
            topic: "Refraction of Light",
            analogyAnchors: [
                "a pencil looks bent or broken when dipped in a glass of water",
                "a coin at the bottom of a bucket looks raised and closer to the surface"
            ],
            textbookAnchors: [
                "bending of light rays as they pass obliquely from one transparent medium to another of different optical density",
                "change in the speed of light when traveling between two media causes deviation at the boundary"
            ],
            pillar1CoreTerms: ["refraction", "bending", "light", "medium", "optical density", "speed"],
            pillar2CauseTerms: ["bent", "pencil", "water", "glass", "air", "angle", "boundary", "deviation"]
        ),
        "why the sky appears blue": TopicAnchors(
            topic: "Why the Sky Appears Blue",
            analogyAnchors: [
                "milk droplets in water scatter blue light more than red light",
                "fine dust in a dark room catches the short blue waves first"
            ],
            textbookAnchors: [
                "fine particles in the atmosphere scatter shorter wavelengths blue light more strongly than longer red wavelengths according to Rayleigh scattering",
                "scattering of light by air molecules makes the daytime sky appear blue"
            ],
            pillar1CoreTerms: ["scatter", "scattering", "wavelength", "blue", "particles", "atmosphere", "rayleigh"],
            pillar2CauseTerms: ["sky", "sunlight", "red", "shorter", "molecules", "air", "color"]
        ),
        "redox reactions": TopicAnchors(
            topic: "Redox Reactions",
            analogyAnchors: [
                "iron rusting in air takes oxygen while heated copper oxide loses black coating to hydrogen",
                "like trading hot potatoes where one loses and the other gains at the same time"
            ],
            textbookAnchors: [
                "oxidation is gain of oxygen or loss of electrons while reduction is loss of oxygen or gain of electrons",
                "oxidation and reduction always occur simultaneously in a chemical reaction"
            ],
            pillar1CoreTerms: ["oxidation", "reduction", "redox", "oxygen", "electrons", "simultaneously"],
            pillar2CauseTerms: ["copper", "hydrogen", "gain", "loss", "oxide", "react", "heat"]
        ),
        "role of villi in digestion": TopicAnchors(
            topic: "Role of Villi in Digestion",
            analogyAnchors: [
                "a fluffy terrycloth towel absorbs water faster than a flat cotton sheet because of thousands of tiny loops",
                "millions of tiny finger folds soak up digested nutrients quickly"
            ],
            textbookAnchors: [
                "finger-like projections in the small intestine called villi increase surface area for rapid absorption of digested food",
                "villi are richly supplied with blood vessels that transport absorbed nutrients"
            ],
            pillar1CoreTerms: ["villi", "intestine", "absorption", "surface area", "nutrients", "finger-like"],
            pillar2CauseTerms: ["absorb", "towel", "blood", "vessels", "food", "increase", "rapid"]
        ),
        "muscle cramps": TopicAnchors(
            topic: "Muscle Cramps (Respiration)",
            analogyAnchors: [
                "sprinting 100 meters full speed causes sudden sharp burning and locking in leg muscles",
                "heavy exercise leaves muscles gasping for air"
            ],
            textbookAnchors: [
                "anaerobic breakdown of pyruvate into lactic acid in muscle cells during lack of oxygen causes muscle cramps",
                "accumulation of lactic acid leads to painful contraction in muscle tissue"
            ],
            pillar1CoreTerms: ["cramp", "lactic acid", "pyruvate", "anaerobic", "respiration", "oxygen", "muscle"],
            pillar2CauseTerms: ["exercise", "sprint", "run", "pain", "lack of oxygen", "burn", "fatigue"]
        ),
        "non-cooperation movement": TopicAnchors(
            topic: "Non-Cooperation Movement",
            analogyAnchors: [
                "if all students refuse to go to school the whole institution stops working",
                "boycotting foreign cloth and government jobs to withdraw everyday support"
            ],
            textbookAnchors: [
                "British rule survived in India only with Indian cooperation and would collapse if cooperation was refused",
                "boycott of foreign goods legislative councils and government institutions to achieve swaraj"
            ],
            pillar1CoreTerms: ["non-cooperation", "gandhi", "boycott", "swaraj", "british", "movement"],
            pillar2CauseTerms: ["refuse", "foreign cloth", "protest", "peaceful", "withdraw", "institutions"]
        )
    ]
    
    // Apple NLEmbedding sentence embedding for English
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    
    public init() {}
    
    // MARK: - Speech Normalization
    public static func normalizeTranscript(_ input: String) -> String {
        var s = input.lowercased().replacingOccurrences(of: "’", with: "'")
        for (homophone, replacement) in speechHomophones {
            s = s.replacingOccurrences(of: homophone, with: replacement)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    
    // MARK: - Causal Clause Breaker
    public static func splitIntoCausalClauses(_ text: String) -> [String] {
        var t = text
        let breakers = [
            " because ", " so that ", " so ", " therefore ", " whereas ", " but ",
            " which means ", " as a result ", " then ", " since ", " in order to "
        ]
        for b in breakers {
            t = t.replacingOccurrences(of: b, with: ".")
        }
        return t.components(separatedBy: CharacterSet(charactersIn: ".;!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.split(separator: " ").count >= 3 }
    }
    
    // MARK: - Core Guardrail Analysis
    public func calculateTelemetry(
        transcript: String,
        conceptTopic: String
    ) -> LinguisticTelemetry {
        let normalized = Self.normalizeTranscript(transcript)
        guard !normalized.isEmpty else {
            return LinguisticTelemetry(
                nounToVerbRatio: 0.0,
                semanticSimilarityToAnalogy: 0.0,
                semanticSimilarityToTextbook: 0.0,
                isKeywordStuffingSuspected: false
            )
        }
        
        // 1. NL TAGGER: Count Nouns and Verbs via .lexicalClass
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = normalized
        
        var nouns = 0
        var verbs = 0
        var wordCount = 0
        var lemmas = Set<String>()
        
        let range = normalized.startIndex..<normalized.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
            wordCount += 1
            let word = String(normalized[tokenRange]).lowercased()
            lemmas.insert(word)
            
            if let tag = tag {
                switch tag {
                case .noun:
                    nouns += 1
                case .verb:
                    verbs += 1
                default:
                    break
                }
            }
            return true
        }
        
        // Add root lemmas
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            if let root = tag?.rawValue {
                lemmas.insert(root.lowercased())
            }
            return true
        }
        
        // Compute Noun-to-Verb Ratio
        let ratio: Double
        if verbs == 0 {
            ratio = nouns > 0 ? Double(nouns) : 0.0
        } else {
            ratio = Double(nouns) / Double(verbs)
        }
        let roundedRatio = (ratio * 100).rounded() / 100.0
        
        // 2. Keyword Stuffing Detection Guardrail
        let glueWords: Set<String> = [
            "the", "a", "an", "to", "in", "of", "for", "with", "on", "at", "from", "by",
            "if", "when", "because", "so", "that", "is", "are", "has", "have", "can",
            "it", "they", "we", "i", "you", "while", "into", "onto", "happens", "pushes"
        ]
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let glueHits = tokens.filter { glueWords.contains($0) }.count
        
        let isKeywordStuffing: Bool
        if wordCount >= 5 && (ratio >= 3.5 || (verbs <= 1 && nouns >= 4) || glueHits < 2) {
            isKeywordStuffing = true
        } else {
            isKeywordStuffing = false
        }
        
        // 3. NL EMBEDDING: Semantic Vector Distance to Analogy and Textbook Anchors
        let anchors = lookupAnchors(for: conceptTopic)
        let clauses = Self.splitIntoCausalClauses(normalized)
        var activeClauses = clauses.isEmpty ? [normalized] : clauses
        if !activeClauses.contains(normalized) {
            activeClauses.append(normalized)
        }
        
        let analogySim = bestSimilarity(clauses: activeClauses, anchors: anchors.analogyAnchors)
        let textbookSim = bestSimilarity(clauses: activeClauses, anchors: anchors.textbookAnchors)
        
        return LinguisticTelemetry(
            nounToVerbRatio: roundedRatio,
            semanticSimilarityToAnalogy: (analogySim * 100).rounded() / 100.0,
            semanticSimilarityToTextbook: (textbookSim * 100).rounded() / 100.0,
            isKeywordStuffingSuspected: isKeywordStuffing
        )
    }
    
    public func lookupAnchors(for topic: String) -> TopicAnchors {
        let lower = topic.lowercased().trimmingCharacters(in: .whitespaces)
        for (key, val) in anchorsRegistry {
            if lower.contains(key) || key.contains(lower) {
                return val
            }
        }
        return TopicAnchors(
            topic: topic,
            analogyAnchors: [
                "in everyday life when one thing pushes another it pushes right back",
                "like stepping off a skateboard onto the ground",
                "an everyday object or practical scenario showing this in action"
            ],
            textbookAnchors: [
                "scientific law governing action and reaction forces in matched pairs",
                "formal textbook definition of the underlying physical principle",
                "core theoretical definition and mechanism"
            ]
        )
    }
    
    private func bestSimilarity(clauses: [String], anchors: [String]) -> Double {
        guard let embedding = embedding, !clauses.isEmpty, !anchors.isEmpty else { return 0.38 }
        var maxSim = 0.0
        for clause in clauses {
            for anchor in anchors {
                let distance = embedding.distance(between: clause, and: anchor)
                if distance.isFinite && distance <= 2.0 {
                    let sim = max(0.0, min(1.0, 1.0 - (distance / 1.5)))
                    if sim > maxSim {
                        maxSim = sim
                    }
                }
            }
        }
        return maxSim
    }
}
