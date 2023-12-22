// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

type Probability is uint16;

uint constant PROBABILITY_MASK = type(uint16).max;
uint constant PROBABILITY_SHIFT = 16;
uint constant PROBABILITY_DIVIDER = 10000;
Probability constant PROBABILITY_ZERO = Probability.wrap(0);
Probability constant PROBABILITY_MAX = Probability.wrap(uint16(PROBABILITY_DIVIDER));

library ProbabilityLib {
    error ProbabilityTooBig(uint probability, uint maxProbability);

    function toProbability(uint16 value) internal pure returns (Probability) {
        if (value > PROBABILITY_DIVIDER) {
            revert ProbabilityTooBig(value, PROBABILITY_DIVIDER);
        }
        return Probability.wrap(value);
    }

    function toUint16(Probability probability) internal pure returns (uint16) {
        return Probability.unwrap(probability);
    }

    function mul(Probability probability, uint value) internal pure returns (uint) {
        uint prob = Probability.unwrap(probability);
        return value * prob / PROBABILITY_DIVIDER;
    }

    function mul(uint value, Probability probability) internal pure returns (uint) {
        uint prob = Probability.unwrap(probability);
        return value * prob / PROBABILITY_DIVIDER;
    }

    function isPlayedOut(Probability probability, uint value, uint boost) internal pure returns (bool) {
        return value % PROBABILITY_DIVIDER < Probability.unwrap(probability) * boost;
    }

    function add(Probability a, Probability b) internal pure returns (Probability) {
        return toProbability(Probability.unwrap(a) + Probability.unwrap(b));
    }

    function unwrap(Probability probability) internal pure returns (uint16) {
        return Probability.unwrap(probability);
    }
}

function gtProbability(Probability a, Probability b) pure returns (bool) {
    return Probability.unwrap(a) > Probability.unwrap(b);
}

function ltProbability(Probability a, Probability b) pure returns (bool) {
    return Probability.unwrap(a) < Probability.unwrap(b);
}

function gteProbability(Probability a, Probability b) pure returns (bool) {
    return Probability.unwrap(a) >= Probability.unwrap(b);
}

function lteProbability(Probability a, Probability b) pure returns (bool) {
    return Probability.unwrap(a) <= Probability.unwrap(b);
}

function eProbability(Probability a, Probability b) pure returns (bool) {
    return Probability.unwrap(a) == Probability.unwrap(b);
}

function neProbability(Probability a, Probability b) pure returns (bool) {
    return !eProbability(a, b);
}

using {
      gtProbability as >
    , ltProbability as <
    , gteProbability as >=
    , lteProbability as <=
    , eProbability as ==
    , neProbability as !=
} for Probability global;
