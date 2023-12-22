// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

import "./IOreoVault.sol";

contract OreoVault is IOreoVault, Ownable {
    using SafeERC20 for IERC20;
    IERC20 public OREO;

    constructor(address _oreo) {
        OREO = IERC20(_oreo);
    }

    /// @notice Safe transfer OREO function, just in case if rounding error causes pool to not have enough OREOs.
    /// @param _to The address to transfer OREO to
    /// @param _amount The amount to transfer to
    function safeTransferOreo(address _to, uint256 _amount) external override onlyOwner {
        uint256 oreoBal = OREO.balanceOf(address(this));
        if (_amount >= oreoBal) {
            OREO.safeTransfer(_to, oreoBal);
        } else {
            OREO.safeTransfer(_to, _amount);
        }
    }
}

