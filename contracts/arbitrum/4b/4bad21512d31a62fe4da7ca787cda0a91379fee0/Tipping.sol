// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IStakingPool.sol";
import "./ITipping.sol";

/// Allows users to transfer tokens and have the transferred amount split
/// among several destinations
contract Tipping is Ownable, ITipping {
    using SafeERC20 for IERC20;

    /// @notice The address of the {StakingPool} contract
    address public _STAKING_VAULT;
    /// @notice The address of the {Odeum} contract
    address public _ODEUM;
    /// @notice The address of the team wallet
    address public _FUND_VAULT;
    /// @notice The address to send burnt tokens to
    address public _VAULT_TO_BURN;

    /// @notice The percentage of tokens to be burnt (in basis points)
    uint256 public _burnRate;
    /// @notice The percentage of tokens to be sent to the team wallet (in basis points)
    uint256 public _fundRate;
    /// @notice The percentage of tokens to be sent to the {StakingPool} and distributed as rewards
    uint256 public _rewardRate;

    /// @notice The amount of tips received by each user
    mapping(address => uint256) public userTips;

    /// @notice The maximum possible percentage
    uint256 public constant MAX_RATE_BP = 1000;

    constructor(
        address STAKING_VAULT,
        address ODEUM,
        address FUND_VAULT,
        address VAULT_TO_BURN,
        uint256 burnRate,
        uint256 fundRate,
        uint256 rewardRate
    ) {
        _VAULT_TO_BURN = VAULT_TO_BURN;
        _STAKING_VAULT = STAKING_VAULT;
        _ODEUM = ODEUM;
        _FUND_VAULT = FUND_VAULT;
        _burnRate = burnRate;
        _fundRate = fundRate;
        _rewardRate = rewardRate;
    }

    /// @dev Forbids to set too high percentage
    modifier validRate(uint256 rate) {
        require(rate > 0 && rate <= MAX_RATE_BP, "Tipping: Rate too high!");
        _;
    }

    /// @notice See {ITipping-setStakingVaultAddress}
    /// @dev Emits the {StakingAddressChanged} event
    function setStakingVaultAddress(address STAKING_VAULT) external onlyOwner {
        require(
            STAKING_VAULT != address(0),
            "Tipping: Invalid staking address!"
        );
        _STAKING_VAULT = STAKING_VAULT;
        emit StakingAddressChanged(STAKING_VAULT);
    }

    /// @notice See {ITipping-setOdeumAddress}
    /// @dev Emits the {OdeumAddressChanged} event
    function setOdeumAddress(address ODEUM) external onlyOwner {
        require(ODEUM != address(0), "Tipping: Invalid odeum address!");
        _ODEUM = ODEUM;
        emit OdeumAddressChanged(ODEUM);
    }

    /// @notice See {ITipping-setVaultToBurnAddress}
    /// @dev Emits the {BurnAddressChanged} event
    function setVaultToBurnAddress(address VAULT_TO_BURN) external onlyOwner {
        // Zero address allowed here
        _VAULT_TO_BURN = VAULT_TO_BURN;
        emit BurnAddressChanged(VAULT_TO_BURN);
    }

    /// @notice See {ITipping-setFundVaultAddress}
    /// @dev Emits the {FundAddressChanged} event
    function setFundVaultAddress(address FUND_VAULT) external onlyOwner {
        require(
            FUND_VAULT != address(0),
            "Tipping: Invalid fund vault address!"
        );
        _FUND_VAULT = FUND_VAULT;
        emit FundAddressChanged(FUND_VAULT);
    }

    /// @notice See {ITipping-setBurnRate}
    /// @dev Emits the {FundAddressChanged} event
    function setBurnRate(
        uint256 burnRate
    ) external validRate(burnRate) onlyOwner {
        // Any burn rate allowed here
        _burnRate = burnRate;
        emit BurnRateChanged(burnRate);
    }

    /// @notice See {ITipping-setFundRate}
    function setFundRate(
        uint256 fundRate
    ) external validRate(fundRate) onlyOwner {
        // Any fund rate allowed here
        _fundRate = fundRate;
        emit FundRateChanged(fundRate);
    }

    /// @notice See {ITipping-setRewardRate}
    function setRewardRate(
        uint256 rewardRate
    ) external validRate(rewardRate) onlyOwner {
        // Any reward rate allowed here
        _rewardRate = rewardRate;
        emit RewardRateChanged(rewardRate);
    }

    /// @notice See {ITipping-transfer}
    function tip(address to, uint256 amount) external {
        IERC20 _odeum = IERC20(_ODEUM);
        _odeum.safeTransferFrom(msg.sender, address(this), amount);
        (
            uint256 transAmount,
            uint256 burnAmount,
            uint256 fundAmount,
            uint256 rewardAmount
        ) = _getValues(amount);
        _odeum.safeTransfer(to, transAmount);
        userTips[to] += transAmount;
        _odeum.safeTransfer(_VAULT_TO_BURN, burnAmount);
        _odeum.safeTransfer(_FUND_VAULT, fundAmount);
        _odeum.safeTransfer(_STAKING_VAULT, rewardAmount);
        IStakingPool(_STAKING_VAULT).supplyReward(rewardAmount);
        emit SplitTransfer(to, amount);
    }

    /// @dev Calculates portions of the transferred amount to be
    ///      split among several destinations
    /// @param amount The amount of transferred tokens
    function _getValues(
        uint256 amount
    ) private view returns (uint256, uint256, uint256, uint256) {
        uint256 burnAmount = (amount * _burnRate) / MAX_RATE_BP;
        uint256 fundAmount = (amount * _fundRate) / MAX_RATE_BP;
        uint256 rewardAmount = (amount * _rewardRate) / MAX_RATE_BP;
        uint256 transAmount = amount - rewardAmount - fundAmount - burnAmount;
        return (transAmount, burnAmount, fundAmount, rewardAmount);
    }
}

