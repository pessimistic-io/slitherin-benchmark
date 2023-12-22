// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";

interface IDepositController is IController {
    error NotExpired();

    function deposit(
        address token,
        uint256 amount,
        uint16 lockEpochs,
        uint256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable;

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams
    ) external;

    function collect(uint256 positionId, PermitSignature calldata positionPermitParams) external;
}

