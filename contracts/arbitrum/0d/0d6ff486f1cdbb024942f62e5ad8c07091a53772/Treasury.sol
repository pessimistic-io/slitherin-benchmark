// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Treasury.sol ============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./Owned.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./TransferHelper.sol";

contract Treasury is Owned {
    // Events
    event Execute(address indexed to, bytes data);
    event RecoverEth(uint256 amount);

    constructor(address _sweep) Owned(_sweep) {}

    /* ========== Actions ========== */

    /**
     * @notice Receive Eth
     */
    receive() external payable {}

    /**
     * @notice Execute encoded data
     * @param _to address
     * @param _data Encoded data
     */
    function execute(address _to, bytes memory _data) external onlyAdmin {
        bytes memory returndata = Address.functionCall(_to, _data);
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "Execute failed");
        }

        emit Execute(_to, _data);
    }

    /**
     * @notice Recover Eth
     * @param _amount Eth amount
     */
    function recoverEth(uint256 _amount) external onlyAdmin {
        uint256 eth_balance = address(this).balance;
        if (_amount > eth_balance) _amount = eth_balance;

        TransferHelper.safeTransferETH(msg.sender, _amount);

        emit RecoverEth(_amount);
    }
}

