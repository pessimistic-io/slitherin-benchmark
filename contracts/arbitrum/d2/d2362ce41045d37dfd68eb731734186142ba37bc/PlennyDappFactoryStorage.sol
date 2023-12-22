// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IPlennyDappFactory.sol";

// solhint-disable max-states-count
/// @title  PlennyDappFactoryStorage
/// @notice Storage contract for the PlennyDappFactory
abstract contract PlennyDappFactoryStorage is IPlennyDappFactory {

    /// @notice default Plenny amount the oracles needs to stake
    uint256 public override defaultLockingAmount;

    /// @notice percentage to distribute the channel reward to the user for the given reward period.
    uint256 public override userChannelReward;
    /// @notice period(in blocks) for distribute the channel reward to the user
    uint256 public override userChannelRewardPeriod;
    /// @notice fee charged whenever user collects the channel reward
    uint256 public override userChannelRewardFee;

    /// @notice Maximum channel capacity for opening channels during lightning node verification process.
    uint256 public maxCapacity;
    /// @notice Minimum channel capacity for opening channels during lightning node verification process.
    uint256 public minCapacity;

    /// @notice Fixed reward that is given to the makers in the ocean/marketplace for opening channel to the takers.
    uint256 public override makersFixedRewardAmount;
    /// @notice Fixed amount for giving reward for providing channel capacity
    uint256 public override capacityFixedRewardAmount;

    /// @notice Percentage of the treasury HODL that the maker gets when providing channel capacity via the ocean/marketplace
    uint256 public override makersRewardPercentage;
    /// @notice Percentage of the treasury HODL that the users gets when providing outbound channel capacity
    uint256 public override capacityRewardPercentage;

    /// @notice number of total delegations
    uint256 public delegatorsCount;

    /// @notice number of delegations per oracle
    mapping (address => OracleDelegation) public delegationCount;

    /// @notice arrays of all oracle validators
    ValidatorInfo[] public override validators;
    /// @dev delegator info per oracle
    mapping(address => mapping (uint256 => DelegatorInfo)) internal delegators;
    /// @notice validatorindex per address
    mapping(address => uint256)public override validatorIndexPerAddress;
    /// @notice validator address per index
    mapping(uint256 => address)public validatorAddressPerIndex;
    /// @notice delegation info for the given delegator address
    mapping(address => MyDelegationInfo)public myDelegatedOracle;

    /// @notice arrays of validator scores
    uint256[] public validatorsScore;
    /// @notice sum of all scores
    uint256 public validatorsScoreSum;

    struct ValidatorInfo {
        string name;
        uint256 nodeIndex;
        string nodeIP;
        string nodePort;
        string validatorServiceUrl;
        uint256 revenueShareGlobal;
        address owner;
        uint256 reputation;
    }

    struct OracleDelegation {
        uint256 numDelegators;
        uint256 totalDelegatedAmount;
    }

    struct DelegatorInfo {
        uint256 delegatedAmount;
        address delegator;
    }

    struct MyDelegationInfo {
        uint256 delegationIndex;
        address oracle;
    }

    /// @dev Multiplier for staked balance into the validator score.
    uint256 internal stakedMultiplier;
    /// @dev Multiplier for delegated balance into the validator score.
    uint256 internal delegatedMultiplier;
    /// @dev Multiplier for reputation into the validator score.
    uint256 internal reputationMultiplier;
}
