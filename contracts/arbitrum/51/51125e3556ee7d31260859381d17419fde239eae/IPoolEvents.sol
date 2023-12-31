// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {SD59x18} from "./SD59x18.sol";
import {UD60x18} from "./UD60x18.sol";

import {Position} from "./Position.sol";

interface IPoolEvents {
    event UpdateTick(
        UD60x18 indexed tick,
        UD60x18 indexed prev,
        UD60x18 indexed next,
        SD59x18 delta,
        UD60x18 externalFeeRate,
        SD59x18 longDelta,
        SD59x18 shortDelta,
        uint256 counter
    );

    event Deposit(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 longs,
        UD60x18 shorts,
        SD59x18 lastFeeRate,
        UD60x18 claimableFees,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick
    );

    event Withdrawal(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 longs,
        UD60x18 shorts,
        SD59x18 lastFeeRate,
        UD60x18 claimableFees,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick
    );

    event ClaimFees(address indexed owner, uint256 indexed tokenId, UD60x18 feesClaimed, SD59x18 lastFeeRate);

    event ClaimProtocolFees(address indexed feeReceiver, UD60x18 feesClaimed);

    event FillQuoteOB(
        bytes32 indexed quoteOBHash,
        address indexed user,
        address indexed provider,
        UD60x18 contractSize,
        Position.Delta deltaMaker,
        Position.Delta deltaTaker,
        UD60x18 premium,
        UD60x18 protocolFee,
        UD60x18 totalReferralRebate,
        bool isBuy
    );

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        address indexed taker,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 protocolFee
    );

    event Trade(
        address indexed user,
        UD60x18 contractSize,
        Position.Delta delta,
        UD60x18 premium,
        UD60x18 takerFee,
        UD60x18 protocolFee,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick,
        UD60x18 totalReferralRebate,
        bool isBuy
    );

    event Exercise(
        address indexed operator,
        address indexed holder,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 settlementPrice,
        UD60x18 fee,
        UD60x18 operatorCost
    );

    event Settle(
        address indexed operator,
        address indexed holder,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 settlementPrice,
        UD60x18 fee,
        UD60x18 operatorCost
    );

    event Annihilate(address indexed owner, UD60x18 contractSize, uint256 fee);

    event SettlePosition(
        address indexed operator,
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 exerciseValue,
        UD60x18 feesClaimed,
        UD60x18 settlementPrice,
        UD60x18 fee,
        UD60x18 operatorCost
    );

    event TransferPosition(
        address indexed owner,
        address indexed receiver,
        uint256 srcTokenId,
        uint256 destTokenId,
        UD60x18 contractSize
    );

    event CancelQuoteOB(address indexed provider, bytes32 quoteOBHash);

    event FlashLoan(address indexed initiator, address indexed receiver, UD60x18 amount, UD60x18 fee);

    event SettlementPriceCached(UD60x18 settlementPrice);
}

