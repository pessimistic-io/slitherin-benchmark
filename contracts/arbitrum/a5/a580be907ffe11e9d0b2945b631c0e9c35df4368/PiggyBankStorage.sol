// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IPiggyBankDefinition} from "./IPiggyBank.sol";

contract PiggyBankStorage is IPiggyBankDefinition {
    uint256 public constant PERCENTAGE_BASE = 10000;
    address public portal;

    // nextRoundTarget = preRoundTarget * multiple / 100
    uint8 public multiple;

    // min time long from season start to end
    uint64 private _placeholder;

    // Mapping from season to seasonInfo
    mapping(uint256 => SeasonInfo) internal seasons;

    // Mapping from round index to RoundInfo
    mapping(uint256 => RoundInfo) internal rounds;

    // mapping(account => mapping(season=> mapping(roundIndex => userInfo)))
    mapping(address => mapping(uint256 => mapping(uint256 => UserInfo)))
        internal users;

    uint32 private _placeholder2;

    // 800 = 8%
    uint16 public newRoundRewardPercentage;

    bool public isClaimOpened;

    uint200 internal _placeholder3;

    uint256 public countDownBlockLong;

    uint256[41] internal _gap;
}

