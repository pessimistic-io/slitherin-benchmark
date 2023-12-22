// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Permit2.sol";
import "./IWETH9.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract Proxy is Ownable {
    using SafeERC20 for IERC20;

    error FailedToSendEther();

    IWETH9 public immutable WETH;
    Permit2 public immutable permit2;

    constructor(Permit2 _permit2, IWETH9 _weth) {
        WETH = _weth;
        permit2 = _permit2;
    }

    /// @notice Withdraws fees and transfers them to owner
    function withdrawAdmin() public onlyOwner {
        require(address(this).balance > 0);

        payable(owner()).transfer(address(this).balance);
    }

    /// @notice Sweeps contract tokens to msg.sender
    function sweepToken(IERC20 _token) internal {
        uint256 balanceOf = _token.balanceOf(address(this));

        _token.safeTransfer(msg.sender, balanceOf);
    }

    /// @notice Approves an ERC20 token to lendingPool and wethGateway
    /// @param _token ERC20 token address
    function approveToken(IERC20 _token, address[] calldata _spenders) external onlyOwner {
        for (uint8 i = 0; i < _spenders.length;) {
            _token.safeApprove(_spenders[i], type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    function unwrapWETH9(address recipient) internal {
        uint256 balanceWETH = WETH.balanceOf(address(this));

        if (balanceWETH > 0) {
            WETH.withdraw(balanceWETH);

            (bool success,) = recipient.call{value: balanceWETH}("");
            if (!success) revert FailedToSendEther();
        }
    }

    receive() external payable {}
}

