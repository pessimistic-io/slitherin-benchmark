// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {PolyMaster} from "./PolyMaster.sol";

contract PolyStrategyNative is Ownable {
    using SafeERC20 for IERC20;

    // master contract
    PolyMaster public immutable polyMaster;
    // deposit want token
    IERC20 public immutable depositToken;
    // performance fee
    uint256 public performanceFeeBips;
    // max uint256
    uint256 internal constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    // scaled up by ACC_EARNING_PRECISION
    uint256 internal constant ACC_EARNING_PRECISION = 1e18;
    // max performance fee
    uint256 internal constant MAX_BIPS = 10000;

    constructor(PolyMaster _polyMaster, IERC20 _depositToken) {
        polyMaster = _polyMaster;
        depositToken = _depositToken;
        transferOwnership(address(_polyMaster));
    }

    //PUBLIC FUNCTIONS
    /**
     * @notice Reward token balance that can be claimed
     * @dev Staking rewards accrue to contract on each deposit/withdrawal
     * @return Unclaimed rewards
     */
    function checkReward() public view returns (uint256) {
        return 0;
    }

    function checkReward(uint256 _pidMonopoly) public view returns (uint256) {
        return 0;
    }

    function pendingRewards(address user) public view returns (uint256) {
        return 0;
    }

    function pendingRewards(
        uint256 _pidMonopoly
    ) public view returns (uint256) {
        return 0;
    }

    function rewardTokens() external view virtual returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        return (_rewardTokens);
    }

    function pendingTokens(
        uint256,
        address user,
        uint256
    ) external view returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = pendingRewards(user);
        return (_rewardTokens, _pendingAmounts);
    }

    //EXTERNAL FUNCTIONS
    function harvest(uint256 _pidMonopoly) external {}

    //OWNER-ONlY FUNCTIONS
    function deposit(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 _pidMonopoly
    ) external onlyOwner {}

    function withdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP,
        uint256 _pidMonopoly
    ) external onlyOwner {
        if (tokenAmount > 0) {
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(
                    polyMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function setAllowances(uint256 _pidMonopoly) external onlyOwner {}

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards(uint256 _pidMonopoly) internal {}

    function _harvest(address caller, address to) internal {}

    //internal wrapper function to avoid reverts due to rounding
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {}

    function emergencyWithdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP,
        uint256 pidMonopoly
    ) external onlyOwner {
        if (tokenAmount > 0) {
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(
                    polyMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function inCaseTokensGetStuck(
        IERC20 token,
        address to,
        uint256 amount,
        uint256 _pidMonopoly
    ) external virtual onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");
        require(
            address(token) != address(depositToken),
            "cannot recover deposit token"
        );
        token.safeTransfer(to, amount);
    }
}

