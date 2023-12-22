// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library Maths{

    uint256 constant REWARD_DENOMINATION = 18;
    uint256 constant LOG2_E = 14426950;
    uint256 constant ONE_EXP = 7;
    uint256 constant ONE = 10 ** ONE_EXP;

    function computeReputation(
        uint256 wageDeadline,
        uint256 creationDate,
        uint256 predictionTimestamp,
        uint256 numberOfOutcomes
    ) external pure returns(uint256){
        //time before wage deadline
        uint256 timeBeforeDeadline = (
            wageDeadline - predictionTimestamp
        );
        //length of the market
        uint256 marketLength = (
            wageDeadline - creationDate
        );
        //log of market length
        uint256 logMarketLength = (
            ln(marketLength * ONE)
        );
        //log of number of outcomes
        uint256 logNumberOfOutcomes = (
            ln(numberOfOutcomes * ONE)
        );

        uint256 exp = REWARD_DENOMINATION - ONE_EXP - ONE_EXP;
        //result
        return (
            (10 ** exp) *
            (logMarketLength * logNumberOfOutcomes * timeBeforeDeadline) /
            marketLength
        );
    }

    function ln(
        uint256 x
    ) validLogInput(x) internal pure returns (uint256) {
        uint256 ilog2 = floorLog2(x / ONE);
        uint256 z = (x >> ilog2);
        uint256 term = (z - ONE) * ONE / (z + ONE);
        uint256 halflnz = term;
        uint256 termpow = term * term / ONE * term / ONE;
        halflnz += termpow / 3;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 5;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 7;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 9;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 11;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 13;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 15;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 17;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 19;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 21;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 23;
        termpow = termpow * term / ONE * term / ONE;
        halflnz += termpow / 25;
        return (ilog2 * ONE) * ONE / LOG2_E + 2 * halflnz;
    }

    function floorLog2(uint256 x) internal pure returns (uint256) {
        uint256 n;
        if (x >= 2**128) { x >>= 128; n += 128;}
        if (x >= 2**64) { x >>= 64; n += 64;}
        if (x >= 2**32) { x >>= 32; n += 32;}
        if (x >= 2**16) { x >>= 16; n += 16;}
        if (x >= 2**8) { x >>= 8; n += 8;}
        if (x >= 2**4) { x >>= 4; n += 4;}
        if (x >= 2**2) { x >>= 2; n += 2;}
        if (x >= 2**1) { x >>= 1; n += 1;}
        return n;
    }

    modifier validLogInput(uint256 x){
        if(x > 0){
            _;
        }
    }
}
