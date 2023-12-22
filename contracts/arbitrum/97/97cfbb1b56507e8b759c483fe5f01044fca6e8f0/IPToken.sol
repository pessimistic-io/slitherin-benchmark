// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./ILendable.sol";

abstract contract IPToken is ILendable {

    /*** User Functions ***/

    function deposit(address route, uint256 amount) external virtual payable;

    function depositBehalf(address route, address user, uint256 amount) external virtual payable;

    /*** Admin Functions ***/

    function setMidLayer(address newMiddleLayer) external virtual;

    function deprecateMarket(
        bool deprecatedStatus
    ) external virtual;

    function freezeMarket(
        bool freezeStatus
    ) external virtual;
}
