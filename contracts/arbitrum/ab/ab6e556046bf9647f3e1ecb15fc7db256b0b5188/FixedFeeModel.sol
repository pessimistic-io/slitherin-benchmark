//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import {PositionId, IFeeModel} from "./IFeeModel.sol";
import {MathLib} from "./MathLib.sol";

contract FixedFeeModel is IFeeModel {
    using MathLib for uint256;

    uint256 private immutable fee; // fee percentage in wad, e.g. 0.0015e18 -> 0.15%

    constructor(uint256 _fee) {
        fee = _fee;
    }

    /// @inheritdoc IFeeModel
    /// @dev Calculate a fixed percentage fee
    function calculateFee(
        address,
        PositionId,
        uint256 cost
    ) external view override returns (uint256 calculatedFee) {
        calculatedFee = cost.mulWadUp(fee);
    }
}

