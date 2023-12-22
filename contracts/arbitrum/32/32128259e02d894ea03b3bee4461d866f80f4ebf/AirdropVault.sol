// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Address} from "./Address.sol";
import {IAirdropVault} from "./IAirdropVault.sol";

contract AirdropVault is IAirdropVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable rebornToken;

    /**
     * @dev receive native token
     */
    receive() external payable {}

    constructor(address owner_, address rebornToken_) {
        if (rebornToken_ == address(0)) revert ZeroAddressSet();
        _transferOwnership(owner_);
        rebornToken = rebornToken_;
    }

    /**
     * @notice Send reward to user
     * @param to The address of awards
     * @param amount number of awards
     */
    function rewardDegen(
        address to,
        uint256 amount
    ) external virtual override onlyOwner {
        IERC20(rebornToken).safeTransfer(to, amount);
    }

    /**
     * @notice Send reward to user
     * @param to The address of awards
     * @param amount number of awards
     */
    function rewardNative(
        address to,
        uint256 amount
    ) external virtual override nonReentrant onlyOwner {
        payable(to).sendValue(amount);
    }

    /**
     * @notice withdraw token Emergency
     */
    function withdrawEmergency(address to) external virtual override onlyOwner {
        if (to == address(0)) revert ZeroAddressSet();
        uint256 degenBalance = IERC20(rebornToken).balanceOf(address(this));
        uint256 nativeBalance = address(this).balance;
        IERC20(rebornToken).safeTransfer(to, degenBalance);

        payable(to).sendValue(nativeBalance);

        emit WithdrawEmergency(to, rebornToken, degenBalance, nativeBalance);
    }
}

