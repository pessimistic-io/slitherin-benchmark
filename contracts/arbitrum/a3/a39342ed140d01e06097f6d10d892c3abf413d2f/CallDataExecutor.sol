pragma solidity >=0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./UniversalERC20.sol";

contract CallDataExecutor is Ownable, ReentrancyGuard {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;

    function sendNativeAndExecute(
        IERC20 token,
        address callTo,
        address approveAddress,
        uint256 amount,
        uint256 gasLimit,
        bytes memory payload
    )
        external
        payable
        nonReentrant
    {
        require(msg.value == amount, "Amount mismatch");
        _execute(token, callTo, approveAddress, amount, gasLimit, payload);
    }

    function sendAndExecute(
        IERC20 token,
        address callTo,
        address approveAddress,
        uint256 amount,
        uint256 gasLimit,
        bytes memory payload
    )
        external
        payable
        nonReentrant
    {
        token.safeTransferFrom(msg.sender, address(this), amount);
        _execute(token, callTo, approveAddress, amount, gasLimit, payload);
    }

    function execute(
        IERC20 token,
        address callTo,
        address approveAddress,
        uint256 amount,
        uint256 gasLimit,
        bytes memory payload
    )
        external
        payable
        nonReentrant
    {
        _execute(token, callTo, approveAddress, amount, gasLimit, payload);
    }

    function _execute(
        IERC20 token,
        address callTo,
        address approveAddress,
        uint256 amount,
        uint256 gasLimit,
        bytes memory payload
    )
        internal
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
    }
}

