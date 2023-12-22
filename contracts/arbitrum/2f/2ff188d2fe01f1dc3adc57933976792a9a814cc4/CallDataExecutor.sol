// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./UniversalERC20.sol";

contract CallDataExecutor is Ownable, ReentrancyGuard {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;

    function execute(
        IERC20 token,
        address callTo,
        address approveAddress,
        address contractOutputsToken,
        address recipient,
        uint256 amount,
        uint256 gasLimit,
        bytes memory payload
    )
        external
        payable
        nonReentrant
    {
        uint256 ethAmount = 0;
        if (token.isETH()) {
            require(address(this).balance >= amount, "ETH balance is insufficient");
            ethAmount = amount;
        } else {
            token.universalApprove(approveAddress, amount);
        }

        bool success;
        if (gasLimit > 0) {
            (success, ) = callTo.call{ value: ethAmount, gas: gasLimit }(payload);
        } else {
            (success, ) = callTo.call{ value: ethAmount }(payload);
        }

        require(success, " execution failed");
        if (contractOutputsToken != address(0)) {
            uint256 outputTokenAmount =  IERC20(contractOutputsToken).balanceOf(address(this));
            if (outputTokenAmount > 0) {
                IERC20(contractOutputsToken).universalTransfer(recipient, outputTokenAmount);
            }
        }
    }
}

