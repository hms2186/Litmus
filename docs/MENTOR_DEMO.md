# Mentor demo: a topic and an answer that passes

Real output of the app's own grading engine (`GradingCoordinator` → Apple on-device model → `RuleEngine`), run on this Mac
by `Tools/model_experiments/run.sh demo` with `DEMO_IDS=money_P1`. Nothing below is edited except layout.

**Why this one:** a short Class 10 topic, and the answer is in the student's own words (no textbook terms like
"double coincidence of wants"), so it shows the model judging ideas, not matching keywords.

```
TOPIC: Money and Credit  >  Money as a Medium of Exchange
PASSAGE (what the textbook says): A person holding money can easily exchange it for any commodity or service. Without money, a shoe manufacturer who wants wheat would have to find a farmer who both sells wheat and wants to buy shoes: both parties must agree to sell and buy each other's commodities. This is the double coincidence of wants, an essential feature of a barter system. Money provides the crucial intermediate step and eliminates the need for it: the shoe manufacturer only needs a buyer for his shoes. Since money acts as an intermediate in exchange, it is called a medium of exchange.

STUDENT ANSWER: A shoe maker who wants wheat has to find a farmer who has wheat and also wants shoes. Both must want what the other has. With money, the shoe maker sells shoes to anyone for money and then buys wheat from anyone, so he no longer needs that exact match. Money sits in the middle of every trade.

CHECKS (each key idea, judged by the on-device model):
  [YES] Explains double coincidence of wants: both parties must want to sell and buy each other's goods, which is an essential feature of barter.
        student's own words: "Both must want what the other has."
  [YES] Explains that money acts as an intermediate in the exchange process, eliminating the need for double coincidence of wants, and so is called a medium of exchange.
        student's own words: "Money sits in the middle of every trade."
  [YES] The answer attempts to explain Money as a Medium of Exchange, even if it uses everyday words instead of textbook terms.
  [YES] Connects money acting as an intermediate in exchange to eliminating the need for a double coincidence of wants.
  [NO] The answer states or implies this wrong idea: Money is useful only because it is valuable in itself.

ENGINE DECISION: mastered   (weight passed 4 of 4)
PARAKH LEVEL: advanced
RULE TRACE: score 4/4, open 0, coreAllPass true, coreFailed false | row 3: all core pass, bar met, evidence complete
```

## How to read it
- Each CHECK is one key idea from the compiled NCERT curriculum, judged by the on-device model. A YES on an idea needs a
  quote from the student's own answer that the engine verifies.
- The last check is a *misconception* check: NO is what we want.
- The engine passes when every core idea is YES, the weighted score is at least 70%, and no misconception is stated.
- PARAKH level (see `Litmus/Grading/RubricMatrix.swift`): Advanced = Mastered, Proficient = Likely mastered, Basic = partial.

## Honest limits
- Runs on the same answer vary: this answer came out *Mastered* in two runs and *Likely mastered* in one (the quote check
  timed out). Both show the pass screen. Running other apps at the same time can make the model time out and return
  "uncertain", which sent the textbook answer `money_T1` to a clarification question once.
- The 30-answer set these come from was written and labelled by us, not by students or teachers.
