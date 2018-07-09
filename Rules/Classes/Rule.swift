//
//  Rule.swift
//  Rules
//  License: MIT, included below
//

/// A `Rule` describes a logical implication, which is commonly denoted as
/// `p -> q` in mathematics, where `->` means "implies".
///
/// In this system, it is described as `LHS => RHS`, where `=>` is read as
/// "then". The whole rule is read colloquially as:
///
/// _"If the LHS is true, then the RHS declares this fact."_
///
/// The RHS (or right hand side) of a `Rule` declares a fact. The fact is an
/// `answer` for a `question`. An `Brain` is used to get the `answer` of a
/// `question`.
///
/// The LHS (or left hand side) of a `Rule` is comprised of two parts:
/// - its `priority` ranks the importance of the `Rule` relative to others.
/// - its `predicate` can be evaluated to a `Bool`, given a `Facts`.
///
/// The RHS (or right hand side) of a `Rule` is comprised of three parts:
/// - a `question`, which is the identifier for a fact.
///
/// Given a set of `Rule`s with the same RHS `question`, the `Rule` that "wins"
/// or "takes effect" or "applies" is the one with the highest `priority`
/// amongst the subset of `Rules` whose `predicate` evaluates to `true` in a
/// given `Facts`.
///
/// When a rule takes effect, the inferred fact it declared is remembered in the
/// `Facts`. The `Facts` knows which other questions were needed to determine
/// the answer to the inferred fact and uses that information to forget inferred
/// answers when they're no longer valid because the answers to those other
/// questions changed.
///
/// - note: a `Rule` is invalid if its `predicate` contains its `question`.
public struct Rule {

    /// If an `Assignment` cannot provide a `Facts.AnswerWithDependencies`, it
    /// returns one of these cases.
    public enum FiringError: Swift.Error, Equatable {
        /// An unexpected error occurred.
        /// - parameter debugDescription: use for debug logging.
        case failed(debugDescription: String)
        /// The format of the RHS value was somehow incompatable with the `assignment`.
        /// - parameter debugDescription: use for debug logging.
        /// - parameter value: The RHS `value` of the `Rule` the `assignment` could not process.
        case invalidRHSValue(debugDescription: String, value: Predicate.Value)
    }

    public typealias FiringResult = Rules.Result<FiringError, Facts.AnswerWithDependencies>

    /// TODO: this is going to change to a `String` which the `Brain` uses to look up
    /// an `Assignment` function by name. This will make it easy to make the
    /// `Rule` type `Codable` for conversion to/from JSON.
    public typealias Assignment = (Rule, Facts, Facts.Dependencies) -> FiringResult

    /// Higher priority `Rule`s have their `predicate` checked before `Rules`
    /// with lower `priority`.
    /// The RHS of a higher `priority` `Rule` that matches the current state of
    /// the `Facts` overrides lower-`priority` rules.
    public let priority: Int

    /// The LHS condition of the `Rule`. A `Rule`'s RHS only applies if its
    /// `predicate` matches the current state of the `Facts`.
    ///
    /// - note: The predicate can include comparison against other questions
    ///         whose values are not known in the `Facts`. The answer to
    ///         those questions will be determined recursively.
    public let predicate: Predicate

    /// The RHS `question` is the identifier which the `RHS` `answer` is
    /// associated with.
    public let question: Facts.Question

    /// The `Facts` provides this RHS `answer` as the result of a question for
    /// this `Rule`'s RHS `question` iff this `Rule` has the highest `priority`
    /// amongst all `Rule`s for that question currently matching the state of
    /// the `Facts`.
    public let answer: Facts.Answer

    /// the standard/default assignment will just return the `value` as is.
    public let assignment: Assignment // will change to `String`

    /// This method is going to move into `Facts` when `assignment`
    /// is changed from a function to a `String`
    func fire(given facts: Facts, dependencies: Facts.Dependencies) -> FiringResult {
        return assignment(self, facts, dependencies)
    }
}

public enum RuleParsingError: Error, Equatable {
    case prioritySeparatorNotFound
    case invalidPriority
    case implicationOperatorNotFound
    case invalidPredicate(ConversionError)
    case equalOperatorNotFound
}

typealias RuleParsingResult = Rules.Result<RuleParsingError, Rule>

// MARK: - Parsing textual `Rule`s

// The code from here down will not be needed on other platforms like Android
// unless you cannot use this code to convert your textual rule files to JSON.

/// This parser is not completely finished, it's not quite robust enough
func parse(humanRule: String) -> RuleParsingResult {
    // right now this parses:
    //   priority: predicate => question = answer
    // eventually it will support:
    //   priority: predicate => question = answer [assignment]
    // and value will not be assumed to be a `String`, it will be support
    // all the types in `Rule.Value`, which are `String`, `Int`, `Double`, and
    // `Bool`.
    let trim = Rules.flip(String.trimmingCharacters)(.whitespacesAndNewlines)
    let parts1 = humanRule.split(separator: ":", maxSplits: 1).map(String.init).map(trim)
    guard parts1.count == 2 else {
        return .failed(.prioritySeparatorNotFound)
    }
    guard let priority = Int(trim(parts1[0])) else {
        return .failed(.invalidPriority)
    }
    let afterPriority = parts1[1]
    guard let implicationOperatorRange = afterPriority.range(of: "=>") else {
        return .failed(.implicationOperatorNotFound)
    }
    let predicateFormat = afterPriority[afterPriority.startIndex..<implicationOperatorRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)

    let afterImplicationOperator = afterPriority[implicationOperatorRange.upperBound..<afterPriority.endIndex].trimmingCharacters(in: .whitespacesAndNewlines)

    let rhsParts = afterImplicationOperator.split(separator: "=", maxSplits: 1).map(String.init).map(trim)
    guard rhsParts.count == 2 else {
        return .failed(.equalOperatorNotFound)
    }
    let question = rhsParts[0]

    // for now, leave the assignment out of the textual rule format
    let answerAndAssignment = rhsParts[1]
    let answer = answerAndAssignment
    let predicateResult = convert(ns: parse(format: predicateFormat))
    switch predicateResult {
    case .failed(let error):
        return .failed(.invalidPredicate(error))
    case .success(let predicate):
        return .success(
            Rule(
                priority: priority,
                predicate: predicate,
                question: .init(identifier: question),
                answer: .string(answer), // TODO: support other types
                assignment: { rule, _, dependencies in .success(rule.answer.asAnswerWithDependencies(dependencies)) }
            )
        )
    }
}

//  Created by Jim Roepcke on 2018-06-24.
//  Copyright © 2018- Jim Roepcke.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//
