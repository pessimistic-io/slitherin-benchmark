// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "./LibStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {Address} from "./Address.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract RewardFacet is WithStorage, ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

    event Claimed(address userAddress, address tokenAddress, uint256 amount);

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier onlyManager() {
        require(msg.sender == rs().manager, "not allowed");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    function setManager(address manager) external onlyOwner {
        rs().manager = manager;
    }

    function referralRewardOf(address tokenAddress, address user) external view returns (uint256) {
        return rs().referralRewards[tokenAddress][user];
    }

    function l2eRewardOf(address tokenAddress, address user) external view returns (uint256) {
        return rs().l2eRewards[tokenAddress][user];
    }

    function rewardUserReferral(
        address[] calldata tokenAddress,
        address payable[] calldata users,
        uint256[] calldata amounts
    ) public onlyManager {
        require(
            tokenAddress.length == users.length && users.length == amounts.length,
            "Input arrays must have the same length"
        );

        for (uint256 i = 0; i < users.length; i++) {
            rs().referralRewards[tokenAddress[i]][users[i]] += amounts[i];
        }
    }

    function rewardUserL2E(
        address[] calldata tokenAddress,
        address payable[] calldata users,
        uint256[] calldata amounts
    ) public onlyManager {
        require(
            tokenAddress.length == users.length && users.length == amounts.length,
            "Input arrays must have the same length"
        );

        for (uint256 i = 0; i < users.length; i++) {
            rs().l2eRewards[tokenAddress[i]][users[i]] += amounts[i];
        }
    }

    function claimReferralReward(address tokenAddress) external nonReentrant notContract {
        address payable user = payable(msg.sender);
        uint256 amount = rs().referralRewards[tokenAddress][user];
        rs().referralRewards[tokenAddress][user] = 0;
        if (tokenAddress != address(0)) {
            IERC20(tokenAddress).safeTransfer(user, amount);
        } else {
            user.sendValue(amount);
        }
        emit Claimed(user, tokenAddress, amount);
    }

    function claimL2EReward(address tokenAddress) external nonReentrant notContract {
        address payable user = payable(msg.sender);
        uint256 amount = rs().l2eRewards[tokenAddress][user];
        rs().l2eRewards[tokenAddress][user] = 0;
        if (tokenAddress != address(0)) {
            IERC20(tokenAddress).safeTransfer(user, amount);
        } else {
            user.sendValue(amount);
        }
        emit Claimed(user, tokenAddress, amount);
    }

    /**
     * @notice Returns true if `account` is a contract.
     * @param account: account address
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}

