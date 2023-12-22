// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IHandlerContract } from "./IHandlerContract.sol";

interface IPositionManager is IHandlerContract {
    function positionMargin(address _indexToken, address _collateralToken, bool _isLong)
        external
        view
        returns (uint256);

    function positionNotional(address _indexToken, address _collateralToken, bool _isLong)
        external
        view
        returns (uint256);

    function positionNotional(address _indexToken) external view returns (uint256, bool);

    function positionMargin(address _indexToken) external view returns (uint256, bool);
}

