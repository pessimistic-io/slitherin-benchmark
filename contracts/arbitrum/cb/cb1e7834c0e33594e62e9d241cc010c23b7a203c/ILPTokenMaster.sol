// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "./extensions_IERC20Metadata.sol";
import "./IOwnable.sol";

interface ILPTokenMaster is IOwnable, IERC20Metadata {
    function initialize(
        address _underlying,
        address _lendingController
    ) external;

    function underlying() external view returns (address);

    function lendingPair() external view returns (address);
}

