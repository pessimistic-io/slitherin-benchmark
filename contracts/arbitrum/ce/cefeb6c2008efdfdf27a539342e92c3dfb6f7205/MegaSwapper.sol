// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./SafeMath.sol";
import "./RevertReasonParser.sol";
import "./SafeERC20.sol";

contract MegaSwapper {
    using SafeMath for uint256;

    using SafeERC20 for IERC20;

    address public constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ZERO_ADDRESS =
        0x0000000000000000000000000000000000000000;

    event Swap(
        address indexed inToken,
        address indexed outToken,
        uint256 inAmount,
        uint256 outAmount,
        address recipient
    );

    function isETH(address token) internal pure returns (bool) {
        return (token == ZERO_ADDRESS || token == ETH_ADDRESS);
    }

    function swap(
        address inToken,
        address outToken,
        uint256 inAmount,
        address caller,
        bytes calldata data
    ) external payable returns (uint256) {
        address recipient = msg.sender;
        if (isETH(inToken)) {
            (bool success, bytes memory result) = address(caller).call{
                value: msg.value
            }(data);
            if (!success) {
                revert(RevertReasonParser.parse(result, "callBytes failed: "));
            }
        } else {
            IERC20(inToken).approve(caller, type(uint256).max);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = address(caller).call(data);
            if (!success) {
                revert(RevertReasonParser.parse(result, "callBytes failed: "));
            }
            IERC20(inToken).approve(caller, 0);
        }

        bool outETH = isETH(outToken);
        uint256 outAmount;
        if (!outETH) {
            outAmount = IERC20(outToken).balanceOf(address(this));
            if (outAmount > 0) {
                IERC20(outToken).safeTransfer(recipient, outAmount);
            }
        } else {
            outAmount = address(this).balance;
            if (outAmount > 0) {
                _transferOutETH(recipient, outAmount);
            }
        }
        emit Swap(inToken, outToken, inAmount, outAmount, recipient);
        return outAmount;
    }

    receive() external payable {
        // solhint-disable-next-line avoid-tx-origin
        require(msg.sender != tx.origin, "ETH deposit rejected");
    }

    function _transferOutETH(address receiver, uint256 amountOut) internal {
        (bool success, ) = payable(receiver).call{value: amountOut}("");
        require(success, "vault: send ETH fail");
    }
}

