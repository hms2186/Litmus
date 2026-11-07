//
//  F1ConceptDiagrams.swift
//  The NCERT textbook diagrams (images in the asset catalog) that go with the Class 10 Science
//  concepts of chapters 1 to 5. A concept's flashcard shows its first diagram; any others get a
//  card of their own, so no diagram is lost when a chapter moves to the compiled curriculum.
//

import Foundation

struct F1ConceptDiagram {
    let image: String
    let title: String
    let note: String
}

enum F1ConceptDiagrams {

    /// The diagrams for a compiled concept, in the order they appear in the chapter.
    static func diagrams(for conceptId: String) -> [F1ConceptDiagram] {
        table[conceptId] ?? []
    }

    private static func d(_ image: String, _ title: String, _ note: String) -> F1ConceptDiagram {
        F1ConceptDiagram(image: image, title: title, note: note)
    }

    private static let table: [String: [F1ConceptDiagram]] = [
        // Chapter 1: Chemical Reactions and Equations
        "sci10_ch1_t1_c1": [d("chem_rxn_hydrogen_apparatus", "Fig 1.2: Zinc and Dilute Acid", "Zinc granules in dilute sulphuric acid give off hydrogen gas, and the flask changes in temperature. A gas forming and a change in temperature show that a chemical reaction has taken place.")],
        "sci10_ch1_t3_c1": [d("chem_rxn_slaked_lime_formation", "Fig 1.3: Slaked Lime Formation", "Calcium oxide (quick lime) reacts vigorously with water to give calcium hydroxide (slaked lime), releasing a large amount of heat. Two substances combine into one product.")],
        "sci10_ch1_t5_c1": [d("chem_rxn_lead_nitrate_decomposition", "Fig 1.5: Heating Lead Nitrate", "Heating lead nitrate powder in a boiling tube gives off brown fumes of nitrogen dioxide, a thermal decomposition.")],
        "sci10_ch1_t5_c2": [
            d("chem_rxn_electrolysis_water", "Fig 1.6: Electrolysis of Water", "Passing current through acidified water gives gas at both electrodes, with twice the volume at one of them."),
            d("chem_rxn_silver_chloride_sunlight", "Fig 1.7: Silver Chloride in Sunlight", "White silver chloride turns grey in sunlight as light decomposes it into silver and chlorine.")],
        "sci10_ch1_t6_c1": [
            d("chem_rxn_iron_copper_sulphate_setup", "Fig 1.8(a): Iron Nails in Copper Sulphate", "Iron nails are dipped in blue copper sulphate solution for about 20 minutes."),
            d("chem_rxn_iron_copper_sulphate_result", "Fig 1.8(b): Nails and Solutions Compared", "The nails turn brownish and the blue colour of the solution fades: iron has displaced copper from its solution.")],
        "sci10_ch1_t7_c1": [d("chem_rxn_barium_sulphate_precipitation", "Fig 1.9: Barium Sulphate Precipitate", "Mixing sodium sulphate and barium chloride solutions gives a white precipitate of barium sulphate, a double displacement reaction.")],
        "sci10_ch1_t8_c1": [d("chem_rxn_copper_oxidation", "Fig 1.10: Oxidation of Copper", "Heated copper powder gains oxygen and gets a black coating of copper(II) oxide.")],

        // Chapter 2: Acids, Bases and Salts
        "sci10_ch2_t2_c1": [d("chem_acid_zinc_hydrogen_test", "Fig 2.1: Zinc with Dilute Sulphuric Acid", "The hydrogen gas given off is passed through soap solution, and a burning candle near a gas-filled bubble shows that it burns.")],
        "sci10_ch2_t2_c2": [d("chem_acid_carbonate_co2_test", "Fig 2.2: Carbon Dioxide Through Lime Water", "The gas from a carbonate and an acid is passed through lime water, which gives a white precipitate.")],
        "sci10_ch2_t3_c2": [d("chem_acid_circuit_conductivity", "Fig 2.3: An Acid Solution Conducts Electricity", "The bulb glows with an acid solution because ions carry the current, but not with glucose or alcohol solutions.")],
        "sci10_ch2_t3_c3": [d("chem_acid_hcl_gas_litmus_test", "Fig 2.4: Preparation of HCl Gas", "Dry HCl gas does not change dry litmus paper; the colour changes only with moisture, because hydrogen ions form only in the presence of water.")],
        "sci10_ch2_t4_c1": [d("chem_acid_corrosive_warning_sign", "Fig 2.5: Warning Sign", "The warning sign on containers of concentrated acids and bases, because dissolving them in water is highly exothermic.")],
        "sci10_ch2_t5_c1": [
            d("chem_acid_ph_scale_trends", "Fig 2.6: Variation of pH", "pH changes with the concentration of H+(aq) and OH-(aq) ions: from 0, very acidic, through 7, neutral, to 14, very alkaline."),
            d("chem_acid_ph_substances_infographic", "Fig 2.7: pH of Common Substances", "The pH of some common substances shown on pH paper; the colours are only a rough guide.")],
        "sci10_ch2_t7_c2": [d("chem_salt_chlor_alkali_process", "Fig 2.8: Products of the Chlor-alkali Process", "Electrolysis of brine gives chlorine at the anode, hydrogen at the cathode and sodium hydroxide solution near the cathode.")],
        "sci10_ch2_t8_c1": [d("chem_salt_water_crystallisation", "Fig 2.9: Removing Water of Crystallisation", "Heating blue copper sulphate crystals removes their water of crystallisation and the salt turns white.")],

        // Chapter 3: Metals and Non-metals
        "sci10_ch3_t1_c2": [
            d("chem_metal_heat_conduction", "Fig 3.1: Metals Conduct Heat", "A metal wire heated near the clamp conducts the heat along its length, which melts the wax holding the pin."),
            d("chem_metal_electrical_conductivity", "Fig 3.2: Metals Conduct Electricity", "A metal placed between the terminals completes the circuit, so the bulb glows.")],
        "sci10_ch3_t3_c1": [d("chem_metal_action_of_steam", "Fig 3.3: Action of Steam on a Metal", "Metals such as aluminium, iron and zinc react with steam to form the metal oxide and hydrogen.")],
        "sci10_ch3_t5_c1": [d("chem_metal_reactivity_displacement_test", "Fig 3.4: Reaction of Metals with Salt Solutions", "A metal that displaces another from its salt solution is the more reactive of the two.")],
        "sci10_ch3_t7_c1": [
            d("chem_metal_ionic_salt_heating_spatula", "Fig 3.7: Heating a Salt Sample", "Ionic compounds are heated directly on a spatula to see whether they melt: they have high melting points."),
            d("chem_metal_ionic_solution_conductivity", "Fig 3.8: Conductivity of a Salt Solution", "A solution of an ionic compound in water conducts electricity because it contains ions that move to the electrodes.")],
        "sci10_ch3_t9_c1": [d("chem_metal_electrolytic_refining_copper", "Fig 3.12: Electrolytic Refining of Copper", "The anode is impure copper, the cathode a strip of pure copper and the electrolyte acidified copper sulphate; pure copper deposits on the cathode.")],
        "sci10_ch3_t10_c1": [d("chem_metal_iron_rusting_conditions", "Fig 3.13: Conditions for Rusting", "Nails rust in tube A with air and water, but not in tube B (no dissolved air) or tube C (dry air).")],

        // Chapter 4: Carbon and its Compounds
        "sci10_ch4_t1_c2": [
            d("chem_carbon_h2_molecule", "Fig 4.1: A Molecule of Hydrogen", "Two hydrogen atoms share their electrons to form H2."),
            d("chem_carbon_h2_single_bond", "Fig 4.2: Single Bond Between Two Hydrogen Atoms", "The shared pair of electrons is a single covalent bond, shown as a line."),
            d("chem_carbon_o2_double_bond", "Fig 4.3: Double Bond Between Two Oxygen Atoms", "Each oxygen atom shares two electrons, giving two shared pairs and a double bond."),
            d("chem_carbon_n2_triple_bond", "Fig 4.4: Triple Bond Between Two Nitrogen Atoms", "Each nitrogen atom contributes three electrons, giving three shared pairs and a triple bond."),
            d("chem_carbon_methane_dot_structure", "Fig 4.5: Electron Dot Structure of Methane", "Carbon shares its four valence electrons with four hydrogen atoms in CH4.")],
        "sci10_ch4_t4_c1": [
            d("chem_carbon_ethane_dot_structure", "Fig 4.6(c): Electron Dot Structure of Ethane", "In ethane, C2H6, all the valencies are satisfied by single bonds, so it is saturated."),
            d("chem_carbon_ethene_lewis_structure", "Fig 4.7: Structure of Ethene", "In ethene, C2H4, a double bond between the two carbons satisfies the valencies, so it is unsaturated.")],
        "sci10_ch4_t9_c2": [d("chem_carbon_ester_formation_apparatus", "Fig 4.11: Formation of an Ester", "Ethanol and glacial acetic acid with concentrated sulphuric acid are warmed in a water bath, giving a sweet-smelling ester.")],
        "sci10_ch4_t11_c1": [d("chem_carbon_micelle_formation", "Fig 4.12: Formation of Micelles", "Soap molecules gather around an oil droplet with their carbon-chain tails inside and ionic ends facing the water.")],

        // Chapter 5: Life Processes
        "sci10_ch5_t2_c2": [
            d("bio_life_leaf_cross_section", "Fig 5.1: Cross-section of a Leaf", "Some cells contain green dots, the chloroplasts, which hold chlorophyll."),
            d("bio_life_variegated_leaf_starch_test", "Fig 5.2: Variegated Leaf Starch Test", "After the iodine test only the green areas of the leaf show starch, so chlorophyll is needed for photosynthesis.")],
        "sci10_ch5_t2_c4": [
            d("bio_life_stomata_open_closed", "Fig 5.3: Open and Closed Stomatal Pore", "Guard cells swell with water to open the pore and shrink to close it."),
            d("bio_life_bell_jar_co2_experiment", "Fig 5.4: Is Carbon Dioxide Needed?", "One plant has potassium hydroxide, which absorbs carbon dioxide, beside it; the other does not. Comparing the starch in their leaves shows the need for carbon dioxide.")],
        "sci10_ch5_t3_c2": [d("bio_life_nutrition_amoeba", "Fig 5.5: Nutrition in Amoeba", "Temporary finger-like extensions fuse over a food particle to form a food-vacuole, where digestion takes place.")],
        "sci10_ch5_t4_c1": [d("bio_life_human_alimentary_canal", "Fig 5.6: Human Alimentary Canal", "A long tube from the mouth to the anus whose regions are specialised for different functions.")],
        "sci10_ch5_t5_c1": [d("bio_life_limewater_exhaled_air_test", "Fig 5.7: Lime Water and Exhaled Air", "Air passed into lime water with a pichkari is compared with air breathed out into it, to compare how much carbon dioxide each has.")],
        "sci10_ch5_t6_c2": [d("bio_life_human_respiratory_system", "Fig 5.9: Human Respiratory System", "Air passes from the nostrils through the throat into the lungs, which end in alveoli where gases are exchanged.")],
        "sci10_ch5_t7_c2": [
            d("bio_life_human_heart_cross_section", "Fig 5.10: Sectional View of the Human Heart", "The heart has a left and a right atrium and ventricle, kept apart so that oxygen-rich and carbon dioxide-rich blood do not mix."),
            d("bio_life_double_circulation_scheme", "Fig 5.11: Transport of Oxygen and Carbon Dioxide", "Blood passes through the heart twice in each cycle: once on its way to the lungs and once on its way to the body.")],
        "sci10_ch5_t8_c2": [d("bio_life_transpiration_water_movement", "Fig 5.12: Water Movement in a Tree", "Evaporation from the leaves pulls water up the xylem from the roots, and this loss of water vapour is transpiration.")],
        "sci10_ch5_t9_c1": [d("bio_life_human_urinary_system", "Fig 5.13: Human Excretory System", "A pair of kidneys, a pair of ureters, a urinary bladder and a urethra.")],
        "sci10_ch5_t9_c2": [d("bio_life_nephron_structure", "Fig 5.14: Structure of a Nephron", "A capillary cluster with the cup-shaped Bowman's capsule of a coiled tube; useful substances are re-absorbed as the filtrate flows along the tube.")],
    ]
}
