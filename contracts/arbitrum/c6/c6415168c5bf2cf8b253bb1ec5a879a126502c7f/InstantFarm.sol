// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ERC20.sol";

import "./FullMath.sol";

import "./DefaultAccessControl.sol";

contract InstantFarm is DefaultAccessControl, ERC20 {
    using SafeERC20 for IERC20;

    struct Epoch {
        uint256[] amounts;
        uint256 totalSupply;
    }

    Epoch[] private _epochs;
    address public immutable lpToken;

    address[] public rewardTokens;
    uint256[] public totalCollectedAmounts;
    uint256[] public totalClaimedAmounts;

    mapping(address => uint256) public epochIterator;
    mapping(address => mapping(uint256 => int256)) public balanceDelta;
    mapping(address => bool) public hasDeposits;

    constructor(
        address lpToken_,
        address admin_,
        address[] memory rewardTokens_
    )
        DefaultAccessControl(admin_)
        ERC20(
            string(abi.encodePacked(ERC20(lpToken_).name(), " instant farm")),
            string(abi.encodePacked(ERC20(lpToken_).symbol(), "IF"))
        )
    {
        require(rewardTokens_.length > 0, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            require(rewardTokens_[i] != address(0) && rewardTokens_[i] != lpToken_, ExceptionsLibrary.INVALID_VALUE);
        }
        lpToken = lpToken_;
        rewardTokens = rewardTokens_;

        totalCollectedAmounts = new uint256[](rewardTokens_.length);
        totalClaimedAmounts = new uint256[](rewardTokens_.length);
    }

    function epochCount() external view returns (uint256) {
        return _epochs.length;
    }

    function epochAt(uint256 index) external view returns (Epoch memory) {
        return _epochs[index];
    }

    function updateRewardAmounts() external returns (uint256[] memory amounts) {
        _requireAtLeastOperator();
        require(totalSupply() > 0, ExceptionsLibrary.VALUE_ZERO);
        address[] memory tokens = rewardTokens;
        amounts = new uint256[](tokens.length);
        address this_ = address(this);

        uint256[] memory totalCollectedAmounts_ = totalCollectedAmounts;
        uint256[] memory totalClaimedAmounts_ = totalClaimedAmounts;
        bool hasPositiveAmounts = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 farmBalanceBefore = totalCollectedAmounts_[i] - totalClaimedAmounts_[i];
            amounts[i] = IERC20(tokens[i]).balanceOf(this_) - farmBalanceBefore;
            if (amounts[i] > 0) {
                hasPositiveAmounts = true;
                totalCollectedAmounts[i] += amounts[i];
            }
        }

        if (hasPositiveAmounts) {
            uint256 totalSupply_ = IERC20(lpToken).balanceOf(this_);
            _epochs.push(Epoch({amounts: amounts, totalSupply: totalSupply_}));
            emit RewardAmountsUpdated(_epochs.length - 1, amounts, totalSupply_);
        }
    }

    function deposit(uint256 lpAmount, address to) external {
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);
        _mint(to, lpAmount);
        if (!hasDeposits[to]) {
            hasDeposits[to] = true;
            epochIterator[to] = _epochs.length;
        }
    }

    function withdraw(uint256 lpAmount, address to) external {
        _burn(msg.sender, lpAmount);
        IERC20(lpToken).safeTransfer(to, lpAmount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        uint256 epochCount_ = _epochs.length;
        if (from != address(0)) {
            balanceDelta[from][epochCount_] -= int256(amount);
        }
        if (to != address(0)) {
            balanceDelta[to][epochCount_] += int256(amount);
        }
    }

    function claim(address to) external returns (uint256[] memory amounts) {
        address user = msg.sender;
        uint256 iterator = epochIterator[user];
        uint256 epochCount_ = _epochs.length;
        address[] memory tokens = rewardTokens;
        amounts = new uint256[](tokens.length);
        if (iterator == epochCount_) return amounts;
        mapping(uint256 => int256) storage balanceDelta_ = balanceDelta[user];

        uint256 lpAmount = balanceOf(user);
        uint256 epochIndex = epochCount_;
        while (epochIndex >= iterator) {
            if (epochIndex < epochCount_) {
                Epoch memory epoch_ = _epochs[epochIndex];
                for (uint256 i = 0; i < tokens.length; i++) {
                    amounts[i] += FullMath.mulDiv(lpAmount, epoch_.amounts[i], epoch_.totalSupply);
                }
            }

            int256 delta = balanceDelta_[epochIndex];
            if (delta > 0) {
                lpAmount -= uint256(delta);
            } else if (delta < 0) {
                lpAmount += uint256(-delta);
            }
            if (epochIndex == 0) break;
            epochIndex--;
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransfer(to, amounts[i]);
                totalClaimedAmounts[i] += amounts[i];
            }
        }
        epochIterator[user] = epochCount_;
    }

    event RewardAmountsUpdated(uint256 indexed lastEpochId, uint256[] rewardAmounts, uint256 totalSupply);
}

