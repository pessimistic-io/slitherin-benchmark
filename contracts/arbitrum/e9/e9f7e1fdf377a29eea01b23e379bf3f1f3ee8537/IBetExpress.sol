// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;

import "./IBet.sol";
import "./IOwnable.sol";

interface IBetExpress is IBet, IOwnable {
    struct Bet {
        address affiliate;
        uint64 odds;
        uint128 amount;
        uint48 leaf;
        bool isClaimed;
        SubBet[] subBets;
        uint64[] conditionOdds;
    }

    struct SubBet {
        uint256 conditionId; // the match or condition ID
        uint64 outcomeId; // predicted outcome
    }

    event MaxOddsChanged(uint256 newMaxOdds);
    event NewBet(address indexed bettor, uint256 indexed betId, Bet bet);
    event ReinforcementChanged(uint128 newReinforcement);

    error AlreadyPaid();
    error ConditionNotFinished(uint256 conditionId);
    error ConditionNotRunning(uint256 conditionId);
    error IncorrectMaxOdds();
    error LargeOdds();
    error OnlyLp();
    error SameGameIdsNotAllowed();
    error TooFewSubbets();
    error TooLargeReinforcement(uint256 conditionId);
    error WrongToken();

    function initialize(address lp, address core) external;
}

