// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {Address} from "./Address.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {CommonError} from "./CommonError.sol";
import {IVault} from "./IVault.sol";

contract Vault is IVault, SafeOwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    address public erc20Token;

    function initialize(
        address owner_,
        address erc20Token_
    ) public payable initializer {
        __Ownable_init(owner_);
        erc20Token = erc20Token_;
    }

    /**
     * @notice Send reward to user
     * @param to The address of awards
     * @param amount number of awards
     */
    function rewardERC20(
        address to,
        uint256 amount
    ) external virtual onlyOwner {
        IERC20(erc20Token).safeTransfer(to, amount);
    }

    /**
     * @notice Send reward to user
     * @param to The address of awards
     * @param amount number of awards
     */
    function rewardNative(
        address to,
        uint256 amount
    ) external virtual nonReentrant onlyOwner {
        payable(to).sendValue(amount);
    }

    /**
     * @notice withdraw token Emergency
     */
    function withdrawEmergency(address to) external virtual onlyOwner {
        if (to == address(0)) revert CommonError.ZeroAddressSet();
        uint256 nativeBalance;
        uint256 erc20Balance;
        if (address(erc20Token) == address(0)) {
            nativeBalance = address(this).balance;
            payable(to).sendValue(nativeBalance);
        } else {
            erc20Balance = IERC20(erc20Token).balanceOf(address(this));
            IERC20(erc20Token).safeTransfer(to, erc20Balance);
        }

        emit WithdrawEmergency(to, erc20Token, erc20Balance, nativeBalance);
    }

    /**
     * @dev receive native token
     */
    receive() external payable {}
}

