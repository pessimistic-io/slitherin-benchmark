// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// ====================================================================
// ========================== Treasury.sol ============================
// ====================================================================

/**
 * @title Treasury
 * @dev Manages the fees paid to the protocol
 */

import "./Owned.sol";

import "./Address.sol";
import "./TransferHelper.sol";

contract Treasury is Owned {
    // Events
    event SendEther(address to, uint256 amount);
    event SendToken(address token, address to, uint256 amount);

    constructor(address _sweep) Owned(_sweep) {}

    /* ========== Actions ========== */

    /**
     * @notice Receive Eth
     */
    receive() external payable {}

    /**
     * @notice Send Eth
     * @param _receiver address
     * @param _amount Eth amount
     */
    function sendEther(address _receiver, uint256 _amount) external onlyGov {
        uint256 eth_balance = address(this).balance;
        if (_amount > eth_balance) _amount = eth_balance;

        TransferHelper.safeTransferETH(_receiver, _amount);

        emit SendEther(_receiver, _amount);
    }

    /**
     * @notice Recover ERC20 Token
     * @param _token address
     * @param _receiver address
     * @param _amount SWEEP amount
     */
    function sendToken(address _token, address _receiver, uint256 _amount) external onlyGov {
        uint256 token_balance = IERC20(_token).balanceOf(address(this));
        if (_amount > token_balance) _amount = token_balance;

        TransferHelper.safeTransfer(_token, _receiver, _amount);

        emit SendToken(_token, _receiver, _amount);
    }
}

