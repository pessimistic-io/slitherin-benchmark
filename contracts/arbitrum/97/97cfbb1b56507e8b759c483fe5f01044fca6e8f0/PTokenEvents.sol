// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IIRM.sol";

abstract contract PTokenEvents {

    /*** User Events ***/

    event DepositSent(
        address indexed user,
        address indexed pToken,
        uint256 amount
    );

    event WithdrawApproved(
        address indexed user,
        address indexed pToken,
        uint256 withdrawAmount,
        bool isWithdrawAllowed
    );

    /*** Admin Events ***/

    event SetMiddleLayer(
        address oldMiddleLayer,
        address newMiddleLayer
    );

    event MarketDeprecationChanged(
        bool previousStatus,
        bool newStatus
    );

    event MarketFreezeChanged(
        bool previousStatus,
        bool newStatus
    );

    event RequestControllerChanged(
        address oldRequestController,
        address newRequestController
    );
}
