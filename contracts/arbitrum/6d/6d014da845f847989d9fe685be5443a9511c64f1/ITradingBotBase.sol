// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IPAllAction.sol";
import "./BotSimulationLib.sol";

interface ITradingBotBase {
    struct MultiApproval {
        address[] tokens;
        address spender;
    }

    event DepositSy(uint256 netSyIn);

    event DepositToken(address indexed token, uint256 netTokenIn);

    event WithdrawFunds(address indexed token, uint256 amount);

    event ClaimAndCompound(
        uint256 netSyOut,
        uint256 netPendleOut
    );

    function depositSy(uint256 netSyIn) external;

    function depositToken(
        address router,
        TokenInput calldata inp,
        uint256 minSyOut
    ) external payable;

    function withdrawFunds(address token, uint256 amount) external;

    function claimAndCompound(
        address router,
        TokenInput[] calldata inps,
        uint256 minSyOut
    ) external returns (uint256 netSyOut, uint256 netPendleOut);

    function readMarketExtState(address router) external returns (MarketExtState memory marketExt);

    function readBotState() external view returns (BotState memory botState);
}

