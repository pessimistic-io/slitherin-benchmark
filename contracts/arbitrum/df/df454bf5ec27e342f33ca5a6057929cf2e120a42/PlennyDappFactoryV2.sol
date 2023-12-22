// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IPlennyERC20.sol";
import "./PlennyCoordinator.sol";
import "./PlennyCoordinatorStorage.sol";
import "./PlennyDao.sol";
import "./PlennyTreasury.sol";
import "./PlennyLiqMining.sol";
import "./PlennyOracleValidator.sol";
import "./BytesLib.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyDappFactoryStorage.sol";
import "./PlennyValidatorElection.sol";

/// @title  PlennyDappFactory
/// @notice Contract for storing information about the Lightning Oracles and Delegators.
contract PlennyDappFactoryV2 is PlennyBasePausableV2, PlennyDappFactoryStorage {

    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address payable;
    using BytesLib for bytes;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
    /// An event emitted when a validator is added.
    event ValidatorAdded(address account, bool created);

    /// @dev    Logs the method calls.
    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /// @notice Registers a Lightning Oracle. The oracle needs to stake Plenny as a prerequisite for the registration.
    ///         The oracle needs to have a verified Lightning node registered in the PlennyCoordinator.
    /// @param  _name Name of the oracle
    /// @param  nodeIndex index/id of the Lightning as registered in the PlennyCoordinator.
    /// @param  nodeIP ip address of the verified Lightning node.
    /// @param  nodePort port of the verified Lightning node.
    /// @param  serviceUrl url(host:port) used for running the Plenny Oracle Service.
    function addValidator(string memory _name, uint256 nodeIndex, string memory nodeIP, string memory nodePort,
        string memory serviceUrl) external whenNotPaused _logs_ {

        require(myDelegatedOracle[msg.sender].delegationIndex == 0, "ERR_DELEGATOR");
        require(contractRegistry.stakingContract().plennyBalance(msg.sender) >= defaultLockingAmount, "ERR_NO_FUNDS");

        (,,,, uint256 status,, address to) = contractRegistry.coordinatorContract().nodes(nodeIndex);
        require(to == msg.sender, "ERR_NOT_OWNER");
        require(status == 1, "ERR_NOT_VERIFIED");

        uint256 index = validatorIndexPerAddress[msg.sender];

        if (index >= validators.length || validatorAddressPerIndex[index] != msg.sender) {
            validators.push(ValidatorInfo(_name, nodeIndex, nodeIP, nodePort, serviceUrl, 0, msg.sender, 0));
            validatorIndexPerAddress[msg.sender] = validators.length.sub(1);
            validatorAddressPerIndex[validators.length.sub(1)] = msg.sender;
            validatorsScore.push(0);
            _setValidatorScore(validatorsScore.length.sub(1));
        } else {
            ValidatorInfo storage validatorInfo = validators[index];
            validatorInfo.name = _name;
            validatorInfo.nodeIndex = nodeIndex;
            validatorInfo.nodeIP = nodeIP;
            validatorInfo.nodePort = nodePort;
            validatorInfo.validatorServiceUrl = serviceUrl;
            validatorInfo.revenueShareGlobal = 0;
        }
        emit ValidatorAdded(msg.sender, index == 0);
    }

    /// @notice Used for registering the initial(ZERO) oracle. Managed by the contract owner.
    /// @param  publicKey The public key of the Lightning node.
    /// @param  name Name of the oracle
    /// @param  nodeIP ip address of the initial Lightning node.
    /// @param  nodePort port of the initial Lightning node.
    /// @param  serviceUrl url(host:port) used for running the Plenny Oracle Service.
    /// @param  account address of the initial lightning oracle.
    function createDefaultValidator(string calldata publicKey, string calldata name, string calldata nodeIP,
        string calldata nodePort, string calldata serviceUrl, address payable account) external onlyOwner _logs_ {

        uint256 nodeIndex = contractRegistry.coordinatorContract().verifyDefaultNode(publicKey, account);

        validators.push(ValidatorInfo(name, nodeIndex, nodeIP, nodePort, serviceUrl, 0, account, 0));
        validatorIndexPerAddress[account] = validators.length.sub(1);
        validatorAddressPerIndex[validators.length.sub(1)] = account;
        validatorsScore.push(0);
        _setValidatorScore(validatorsScore.length.sub(1));
    }

    /// @notice Unregisters a Lightning Oracle. In case the oracle is an active validator in the current validation cycle,
    ///         it will fail in removing it.
    function removeValidator() external whenNotPaused _logs_ {
        uint256 index = validatorIndexPerAddress[msg.sender];
        require(validatorAddressPerIndex[index] == msg.sender, "ERR_NOT_ORACLE");
        require(!contractRegistry.validatorElectionContract().validators(
            contractRegistry.validatorElectionContract().latestElectionBlock(), msg.sender),
            "ERR_ACTIVE_VALIDATOR");

        if (validatorsScoreSum >= validatorsScore[index]) {
            validatorsScoreSum = validatorsScoreSum.sub(validatorsScore[index]);
        } else {
            validatorsScoreSum = 0;
        }

        uint256 lastIndex = validators.length.sub(1);
        address lastAddress = validatorAddressPerIndex[lastIndex];

        if (lastIndex == index && lastAddress == msg.sender) {
            delete validatorAddressPerIndex[index];
            delete validatorIndexPerAddress[lastAddress];
        } else {
            validatorAddressPerIndex[index] = lastAddress;
            validatorsScore[index] = validatorsScore[lastIndex];
            validators[index] = validators[lastIndex];

            validatorIndexPerAddress[lastAddress] = index;
            validatorIndexPerAddress[msg.sender] = 0;
        }

        validators.pop();
        validatorsScore.pop();
    }

    /// @notice Gets info for the given oracle.
    /// @param  validator oracle address
    /// @return name name
    /// @return nodeIndex index/id of the Lightning as registered in the PlennyCoordinator.
    /// @return nodeIP ip address of the verified Lightning node.
    /// @return nodePort port of the verified Lightning node.
    /// @return validatorServiceUrl url(host:port) used for running the Plenny Oracle Service.
    /// @return owner address of the validator
    /// @return reputation score/reputation
    function getValidatorInfo(address validator) external view returns (string memory name, uint256 nodeIndex,
        string memory nodeIP, string memory nodePort, string memory validatorServiceUrl, address owner, uint256 reputation){

        uint256 index = validatorIndexPerAddress[validator];
        if (index >= validators.length || validatorAddressPerIndex[index] != validator) {
            return ("ERR", 0, "ERR", "ERR", "ERR", address(0), 0);
        } else {
            ValidatorInfo memory info = validators[index];
            return (info.name, info.nodeIndex, info.nodeIP, info.nodePort, info.validatorServiceUrl, info.owner, info.reputation);
        }
    }

    /// @notice Called whenever an oracle has participated in a validation cycle just before a new validator election
    ///         is triggered. It will update the oracle reputation of that validation cycle.
    /// @dev    Only called by the PlennyValidatorElection contract.
    /// @param  validator oracle address
    /// @param  reward the validator reward to update reputation for
    function updateReputation(address validator, uint256 reward) external override {
        require(msg.sender == contractRegistry.requireAndGetAddress("PlennyOracleValidator"), "ERR_NOT_AUTH");

        uint256 index = validatorIndexPerAddress[validator];
        require(validatorAddressPerIndex[index] == validator, "ERR_VALIDATOR_NOT_FOUND");

        validators[index].reputation = validators[index].reputation.add(reward);

        _setValidatorScore(index);
    }

    /// @notice Called whenever a delegator user stakes more Plenny.
    /// @dev    Called by the PlennyStaking contract.
    /// @param  user address
    function increaseDelegatedBalance(address user, uint256) external override {
        require(msg.sender == contractRegistry.requireAndGetAddress("PlennyStaking"), "ERR_NOT_AUTH");

        if (isOracleValidator(user)) {
            _setValidatorScore(validatorIndexPerAddress[user]);
        }
    }

    /// @notice Called whenever a delegator user unstakes Plenny.
    /// @dev    Only called by the PlennyStaking contract.
    /// @param  user address
    function decreaseDelegatedBalance(address user, uint256) external override {
        require(msg.sender == contractRegistry.requireAndGetAddress("PlennyStaking"), "ERR_NOT_AUTH");

        if (isOracleValidator(user)) {
            _setValidatorScore(validatorIndexPerAddress[user]);
        }
    }

    /// @notice Changes the default Locking Amount. Managed by the contract owner.
    /// @param  amount Plenny amount
    function setDefaultLockingAmount(uint256 amount) external onlyOwner {
        defaultLockingAmount = amount;
    }

    /// @notice Changes the user Channel Reward. Managed by the contract owner.
    /// @param  amount percentage multiplied by 100
    function setUserChannelReward(uint256 amount) external onlyOwner {
        userChannelReward = amount;
    }

    /// @notice Changes the user Channel Reward Period. Managed by the contract owner.
    /// @param  amount period, in blocks
    function setUserChannelRewardPeriod(uint256 amount) external onlyOwner {
        userChannelRewardPeriod = amount;
    }

    /// @notice Changes the user Channel Reward Fee. Managed by the contract owner.
    /// @param  amount percentage multiplied by 100
    function setUserChannelRewardFee(uint256 amount) external onlyOwner {
        userChannelRewardFee = amount;
    }

    /// @notice Changes the staked Multiplier. Managed by the contract owner.
    /// @param  amount multiplied by 100
    function setStakedMultiplier(uint256 amount) external onlyOwner {
        stakedMultiplier = amount;
    }

    /// @notice Changes the delegated Multiplier. Managed by the contract owner.
    /// @param  amount multiplied by 100
    function setDelegatedMultiplier(uint256 amount) external onlyOwner {
        delegatedMultiplier = amount;
    }

    /// @notice Changes the reputation Multiplier. Managed by the contract owner.
    /// @param  amount multiplied by 100
    function setReputationMultiplier(uint256 amount) external onlyOwner {
        reputationMultiplier = amount;
    }

    /// @notice Changes the  minimum channel capacity amount. Managed by the contract owner.
    /// @param  value channel capacity, in satoshi
    function setMinCapacity(uint256 value) external onlyOwner {
        require(value < maxCapacity, "ERR_VALUE_TOO_HIGH");
        minCapacity = value;
    }

    /// @notice Changes the maximum channel capacity amount. Managed by the contract owner.
    /// @param  value channel capacity, in satoshi
    function setMaxCapacity(uint256 value) external onlyOwner {
        require(value > minCapacity, "ERR_VALUE_TOO_LOW");
        maxCapacity = value;
    }

    /// @notice Changes the makers Fixed Reward Amount. Managed by the contract owner.
    /// @param  value plenny reward amount, in wei
    function setMakersFixedRewardAmount(uint256 value) external onlyOwner {
        makersFixedRewardAmount = value;
    }

    /// @notice Changes the capacity Fixed Reward Amount. Managed by the contract owner.
    /// @param  value plenny reward, in wei
    function setCapacityFixedRewardAmount(uint256 value) external onlyOwner {
        capacityFixedRewardAmount = value;
    }

    /// @notice Changes the makers Reward Percentage. Managed by the contract owner.
    /// @param  value multiplied by 100
    function setMakersRewardPercentage(uint256 value) external onlyOwner {
        makersRewardPercentage = value;
    }

    /// @notice Changes the capacity Reward Percentage. Managed by the contract owner.
    /// @param  value multiplied by 100
    function setCapacityRewardPercentage(uint256 value) external onlyOwner {
        capacityRewardPercentage = value;
    }

    /// @notice Number of oracles.
    /// @return uint256 counter
    function validatorsCount() external view returns (uint256) {
        return validators.length;
    }

    /// @notice Calculates random numbers for a channel capacity used for verifying nodes in the PlennyCoordinator.
    /// @return uint256 random number
    function random() external view override returns (uint256) {
        uint256 ceiling = maxCapacity.sub(minCapacity);
        uint256 randomNumber = uint256(uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % ceiling);
        randomNumber = randomNumber.add(minCapacity);
        return randomNumber;
    }

    /// @notice Calculates random numbers based on the block info.
    /// @return uint256 random number
    function pureRandom() external view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty)));
    }

    /// @notice Gets all the validator scores and the sum of all scores.
    /// @return scores arrays of validator scores
    /// @return sum score sum
    function getValidatorsScore() external view override returns (uint256[] memory scores, uint256 sum) {
        return (validatorsScore, validatorsScoreSum);
    }

    /// @notice Gets all delegators for the given oracle.
    /// @return address[] array of delegator addresses
    function getDelegators(address) public view override returns (address[] memory){
        revert("ERR_DISABLED");
    }

    /// @notice Gets the Plenny balance from all the delegators of the given address.
    /// @param  user address to check
    /// @return uint256 delegated balance
    function getDelegatedBalance(address user) public view override returns (uint256) {
        return delegationCount[user].totalDelegatedAmount;
    }

    /// @notice Checks if the address is an oracle.
    /// @param  oracle address to check
    /// @return bool true/false
    function isOracleValidator(address oracle) public view override returns (bool) {
        return validatorAddressPerIndex[validatorIndexPerAddress[oracle]] == oracle;
    }

    /// @notice Calculates the validator score for the given validator
    /// @param  index id of the validator
    function _setValidatorScore(uint256 index) internal {

        uint256 oldValue = validatorsScore[index];

        address oracle = validators[index].owner;
        uint256 stakedBalance = contractRegistry.stakingContract().plennyBalance(oracle);
        uint256 staked = stakedBalance.mul(stakedMultiplier).div(100);

        uint256 _reputation = validators[index].reputation;
        uint256 reputation = _reputation.mul(reputationMultiplier).div(100);

        uint256 newValue = staked.add(reputation);
        validatorsScore[index] = newValue;

        if (newValue >= oldValue) {
            validatorsScoreSum = validatorsScoreSum.add(newValue.sub(oldValue));
        } else {
            validatorsScoreSum = validatorsScoreSum.sub(oldValue.sub(newValue));
        }
    }
}
