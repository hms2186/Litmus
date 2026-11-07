//
//  ParakhRubricMatrix.swift
//  Feynman Tutor Engine - PARAKH Competency Rubric & Feynman Gap Matrix
//
//  Deterministic baseline engine conforming to PARAKH Competency v1.2 (NCERT/CBSE).
//

import Foundation

public struct ParakhRubricMatrix: Sendable {
    
    public struct SocraticPromptBank: Sendable {
        public let keywordStuffingQuestion: String
        public let roteMemoryQuestion: String
        public let partialMechanismQuestion: String
        public let masteryProgressionQuestion: String
    }
    
    private static let promptBank: [String: SocraticPromptBank] = [
        "newton's third law of motion": SocraticPromptBank(
            keywordStuffingQuestion: "You know the exact phrase by heart! But let's take it out of the textbook. If you jump forward off a small rowing boat into the water, what happens to the boat itself behind you, and why?",
            roteMemoryQuestion: "You know the 'equal and opposite' slogan, but what is physically pushing what? Imagine standing on a frictionless skateboard and throwing a heavy bowling ball forward. What happens to your body?",
            partialMechanismQuestion: "You described both forces, but why don't they cancel each other out to zero? Think about which specific object each force acts on.",
            masteryProgressionQuestion: "Spot on! If the Earth pulls down on a falling apple, does the apple pull up on the Earth with the exact same magnitude?"
        ),
        "double coincidence of wants": SocraticPromptBank(
            keywordStuffingQuestion: "You know the economics terms! But imagine you have 10 sacks of wheat and need shoes. What deadlock happens if the only shoemaker already has enough wheat for the year?",
            roteMemoryQuestion: "Think about why direct barter is exhausting. How does having cash in your pocket break that deadlock instantly?",
            partialMechanismQuestion: "Good start on barter! Now explain the second part: what role does money play as an intermediate medium of exchange?",
            masteryProgressionQuestion: "Terrific! How does modern digital currency or UPI make this even faster than coins and paper?"
        ),
        "modern forms of money": SocraticPromptBank(
            keywordStuffingQuestion: "A paper note is just paper, not gold or silver! Why does the grocer still hand you bread in exchange for it?",
            roteMemoryQuestion: "Who legally guarantees that a 100 rupee note must be accepted anywhere in the country?",
            partialMechanismQuestion: "You noted it's paper, but who authorizes it so nobody can refuse it?",
            masteryProgressionQuestion: "If anyone can print paper, why is unauthorized printing considered a crime against legal tender?"
        ),
        "collateral in loans": SocraticPromptBank(
            keywordStuffingQuestion: "Why won't a bank just trust you with a loan? If you pledge your tractor and can't repay, what does the bank do?",
            roteMemoryQuestion: "What is the legal purpose of collateral from the bank's perspective if a borrower defaults?",
            partialMechanismQuestion: "You explained what collateral is. What specifically happens if the borrower cannot pay back?",
            masteryProgressionQuestion: "Why do banks refuse assets whose value changes wildly or cannot be easily sold?"
        ),
        "power sharing in democracy": SocraticPromptBank(
            keywordStuffingQuestion: "If the majority group takes all the power and decisions, why does the whole country eventually destabilize?",
            roteMemoryQuestion: "Why does giving minority communities an official voice prevent violence in a diverse nation?",
            partialMechanismQuestion: "Good on power sharing! What is the negative consequence if the majority forces its will?",
            masteryProgressionQuestion: "How do modern constitutions use federal checks and balances to preserve this harmony?"
        ),
        "refraction of light": SocraticPromptBank(
            keywordStuffingQuestion: "You know the textbook definition of refraction! But if you drop a straight pencil into a glass of water, why does it look severed right at the water line?",
            roteMemoryQuestion: "What actually happens to the speed of the light wave when it moves from air into dense glass?",
            partialMechanismQuestion: "You noted light bends, but what happens if the ray enters perpendicular at 90 degrees?",
            masteryProgressionQuestion: "How does this refraction explain why swimming pools appear shallower than they actually are?"
        ),
        "why the sky appears blue": SocraticPromptBank(
            keywordStuffingQuestion: "You know the scattering keywords! But why do we see blue during the day while sunsets turn deep red and orange?",
            roteMemoryQuestion: "Which particles in the atmosphere do the scattering, and why do short blue wavelengths scatter more than red?",
            partialMechanismQuestion: "If you went to the Moon with no atmosphere, what color would the sky be at noon?",
            masteryProgressionQuestion: "How does Rayleigh scattering explain danger signals being red rather than blue?"
        ),
        "role of villi in digestion": SocraticPromptBank(
            keywordStuffingQuestion: "You said villi! But imagine drying your hands with a flat bedsheet versus a fluffy towel with millions of loops. Why does the towel work so much faster?",
            roteMemoryQuestion: "Why is surface area so vital for absorption across the intestinal wall into the bloodstream?",
            partialMechanismQuestion: "What happens to the absorbed nutrients once they cross the thin epithelial wall of the villus?",
            masteryProgressionQuestion: "If a disease flattens the villi, why would a patient lose weight despite eating enough food?"
        ),
        "muscle cramps": SocraticPromptBank(
            keywordStuffingQuestion: "You memorized lactic acid! But when you sprint 100 meters full speed, why does your leg muscle start burning and locking up?",
            roteMemoryQuestion: "Why does the muscle cell switch to anaerobic breakdown of pyruvate when oxygen runs out?",
            partialMechanismQuestion: "What specifically converts into lactic acid during heavy athletic exercise?",
            masteryProgressionQuestion: "Why does taking a hot water bath or gentle massage relieve muscle cramps after a race?"
        ),
        "redox reactions": SocraticPromptBank(
            keywordStuffingQuestion: "You know oxidation and reduction! But if hydrogen gas passes over hot black copper oxide, why does it turn reddish-brown?",
            roteMemoryQuestion: "Why can oxidation never occur by itself without reduction happening to another substance?",
            partialMechanismQuestion: "Which substance is oxidized and which is reduced in the reaction?",
            masteryProgressionQuestion: "How does corrosion or rancidity represent an unwanted redox reaction in daily life?"
        ),
        "non-cooperation movement": SocraticPromptBank(
            keywordStuffingQuestion: "You know Gandhi's terms! But if the British had thousands of troops and Indians had none, how could simply staying home bring down an empire?",
            roteMemoryQuestion: "What was the economic consequence of boycotting foreign cloth and picketing liquor shops?",
            partialMechanismQuestion: "Why did the movement stall when violence broke out at Chauri Chaura?",
            masteryProgressionQuestion: "How did Non-Cooperation transform the independence movement from elite debates to a mass struggle?"
        )
    ]
    
    public static func evaluate(session: SessionInput) -> EvaluationOutput {
        let telemetry = session.linguisticTelemetry
        let context = session.systemContext
        let topicKey = context.conceptTopic.lowercased()
        
        let questions = promptBank.first(where: { topicKey.contains($0.key) || $0.key.contains(topicKey) })?.value ?? SocraticPromptBank(
            keywordStuffingQuestion: "You know the keywords! But explain it simply: what real-world example shows this happening right now?",
            roteMemoryQuestion: "How would you explain the cause and effect to an 8-year-old using something around the house?",
            partialMechanismQuestion: "What happens next in this chain reaction?",
            masteryProgressionQuestion: "How does this principle apply to a more complex scenario?"
        )
        
        // TELEMETRY ENFORCEMENT PRIORITY:
        let isStuffing = telemetry.isKeywordStuffingSuspected || telemetry.nounToVerbRatio >= 3.8
        let isRote = telemetry.semanticSimilarityToTextbook >= 0.70 && telemetry.semanticSimilarityToAnalogy < 0.35
        
        let clarity: ConceptualClarityTier
        let roteDetected: Bool
        let score: Int
        let summary: String
        let gapExplanation: String
        let guidingQuestion: String
        
        if isStuffing {
            clarity = .low
            roteDetected = true
            score = 12
            summary = "Student relies heavily on isolated keywords without grammatical syntax (noun-to-verb ratio \(telemetry.nounToVerbRatio)). Fails to demonstrate functional mental models."
            gapExplanation = "You mentioned core vocabulary terms, but strung them together without explaining how or why the interaction occurs."
            guidingQuestion = questions.keywordStuffingQuestion
            
        } else if isRote {
            clarity = .moderate
            roteDetected = true
            score = 56
            summary = "Textbook phrasing detected (similarity \(Int(telemetry.semanticSimilarityToTextbook * 100))%) with low analogy grounding (\(Int(telemetry.semanticSimilarityToAnalogy * 100))%). Shows rote memory rather than organic understanding."
            gapExplanation = "You recited the formal definition accurately, but have not yet grounded the idea in an intuitive real-world analogy."
            guidingQuestion = questions.roteMemoryQuestion
            
        } else if telemetry.semanticSimilarityToAnalogy >= 0.38 && telemetry.nounToVerbRatio < 3.2 {
            clarity = .high
            roteDetected = false
            score = 94
            summary = "Strong conceptual mastery! Active phrasing (noun-to-verb ratio \(telemetry.nounToVerbRatio)) with high analogy resonance (\(Int(telemetry.semanticSimilarityToAnalogy * 100))%) meets PARAKH competency standards."
            gapExplanation = "You successfully explained both the core mechanism of \(context.conceptTopic) and grounded it with a clear, active interaction."
            guidingQuestion = questions.masteryProgressionQuestion
            
        } else {
            clarity = .moderate
            roteDetected = false
            score = 65
            summary = "Balanced sentence syntax (\(telemetry.nounToVerbRatio)), but lacks a complete causal link or tangible real-world analogy."
            gapExplanation = "You identified foundational concepts but missed the interactive link connecting the underlying cause to its effect."
            guidingQuestion = questions.partialMechanismQuestion
        }
        
        return EvaluationOutput(
            parakhAssessment: ParakhAssessment(
                conceptualClarity: clarity,
                roteLearningDetected: roteDetected,
                evaluationTelemetrySummary: summary,
                clarityScore: score
            ),
            feynmanAnalysis: FeynmanAnalysis(
                feynmanGapExplanation: gapExplanation,
                nextGuidingQuestion: guidingQuestion
            )
        )
    }
}
