// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Strategy Vault.
 * @author  Pulsar Finance
 * @dev     VERSION: 1.0
 *          DATE:    2023.08.29
 */
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {ITreasuryVault} from "./ITreasuryVault.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract TreasuryVault is ITreasuryVault, Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {
        emit Events.TreasuryCreated(msg.sender, address(this));
    }

    receive() external payable {
        emit Events.EtherReceived(msg.sender, msg.value);
    }

    function withdrawNative(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) {
            revert Errors.NotEnoughEther("Insufficient balance");
        }
        (bool success, ) = owner().call{value: amount}("");
        if (!success) {
            revert Errors.EtherTransferFailed("Ether transfer failed");
        }
        emit Events.NativeWithdrawal(owner(), amount);
    }

    function depositERC20(uint256 amount, address asset) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit Events.ERC20Received(msg.sender, amount, asset);
    }

    function withdrawERC20(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        if (amount > token.balanceOf(address(this))) {
            revert Errors.InvalidTokenBalance("Insufficient balance");
        }
        (bool success, ) = tokenAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                owner(),
                amount
            )
        );
        if (!success) {
            revert Errors.TokenTransferFailed("Token transfer failed");
        }
        emit Events.ERC20Withdrawal(owner(), tokenAddress, amount);
    }
}

