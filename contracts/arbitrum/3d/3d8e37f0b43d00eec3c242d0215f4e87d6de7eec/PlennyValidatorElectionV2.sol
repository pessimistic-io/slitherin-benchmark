// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IPlennyERC20.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyValidatorElectionStorage.sol";


/// @title  PlennyValidatorElection
/// @notice Contains the logic for the election cycle and the process of electing validators based on validators scores.
contract PlennyValidatorElectionV2 is PlennyBasePausableV2, PlennyValidatorElectionStorage {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
    /// An event emitted when the rewards are distributed.
    event OracleReward(address indexed to, uint256 amount);
    /// An event emitted when new validators are elected.
    event NewValidators(address[] newValidators);
    /// An event emitted when user reward is distributed.
    event UserReward(uint256 userReward);

    /// @notice Triggers a new election. Fails if not enough time has passed from the previous election.
    function newElection() external whenNotPaused nonReentrant {
        _logs_();

        if (latestElectionBlock > 0) {
            require(currentElection[latestElectionBlock][0].created.add(newElectionPeriod) <= _blockNumber(), "ERR_LOCKED");
        }

        // send reward to the user
        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        require(contractRegistry.treasuryContract().approve(address(this), electionTriggerUserReward), "failed");
        token.safeTransferFrom(contractRegistry.requireAndGetAddress("PlennyTreasury"), address(this), electionTriggerUserReward);
        token.safeTransfer(msg.sender, electionTriggerUserReward);
        emit UserReward(electionTriggerUserReward);

        // scores holds a list of score for every validator
        IPlennyDappFactory factory = contractRegistry.factoryContract();
        (uint256[] memory scores, uint256 scoreSum) = factory.getValidatorsScore();
        ValidatorIndex [] memory oracles = new ValidatorIndex[](scores.length);

        // New election
        require(scores.length > 0 && scoreSum > 0, "ERR_NO_VALIDATORS");
        address[] memory newValidators = new address[](scores.length > maxValidators ? maxValidators : scores.length);

        uint256 randomNumber = factory.pureRandom();
        uint256 oraclesToBeElectedLength = scores.length;

        latestElectionBlock = _blockNumber();
        for (uint i = 0; i < newValidators.length; i++) {
            randomNumber = uint256(keccak256(abi.encode(randomNumber)));
            uint256 randomIndex = _getRandomIndex(scores, scoreSum, randomNumber);
            uint256 validatorIndex = _getValidatorIndex(oracles, randomIndex);

            (,,,,,,address owner,) = factory.validators(validatorIndex);

            newValidators[i] = owner;
            validators[latestElectionBlock][owner] = true;

            scoreSum = scoreSum.sub(scores[randomIndex]);
            oraclesToBeElectedLength = oraclesToBeElectedLength.sub(1);
            scores[randomIndex] = scores[oraclesToBeElectedLength];
            if (oracles[oraclesToBeElectedLength].exists) {
                oracles[randomIndex] = oracles[oraclesToBeElectedLength];
            } else {
                oracles[randomIndex] = ValidatorIndex(oraclesToBeElectedLength, true);
            }

            // Creating snapshot
            uint256 stakedBalance = contractRegistry.stakingContract().plennyBalance(newValidators[i]);
            electionsArr[latestElectionBlock][newValidators[i]] = ElectionInfo(latestElectionBlock, stakedBalance, scores[randomIndex]);
            currentElection[latestElectionBlock].push(ElectionInfo(latestElectionBlock, stakedBalance, scores[randomIndex]));
        }

        electedValidators[latestElectionBlock] = newValidators;
        emit NewValidators(newValidators);
    }

    /// @notice Reserves a reward for a given validator as a result of a oracle validation done on-chain.
    function reserveReward(address, uint256) external override whenNotPaused nonReentrant {
        revert("ERR_DISABLED");
    }

    /// @notice Changes the new election period (measured in blocks). Called by the owner.
    /// @param  amount election period, in blocks
    function setNewElectionPeriod(uint256 amount) external onlyOwner {
        newElectionPeriod = amount;
    }

    /// @notice Changes the maximum number of validators. Called by the owner.
    /// @param  amount validators
    function setMaxValidators(uint256 amount) external onlyOwner {
        maxValidators = amount;
    }

    /// @notice Changes the user reward in percentage. Called by the owner.
    /// @param  amount amount percentage for the user
    function setUserRewardPercent(uint256 amount) external onlyOwner {
        userRewardPercent = amount;
    }

    /// @notice Changes the user reward. Called by the owner.
    /// @param  amount amount reward for the user
    function setElectionTriggerUserReward(uint256 amount) external onlyOwner {
        electionTriggerUserReward = amount;
    }

    /// @notice Sets the latest election block number. Only to be used in rare circumstances, like resetting the number.
    /// @param  value block number value
    function setLatestElectionBlock(uint256 value) external onlyOwner {
        latestElectionBlock = value;
    }

    /// @notice Gets elected validator count per election.
    /// @param  electionBlock block of the election
    /// @return uint256 count
    function getElectedValidatorsCount(uint256 electionBlock) external view override returns (uint256) {
        return electedValidators[electionBlock].length;
    }

    /// @notice Get a random index for the election based on the validators scores and a randomness.
    /// @param _scores validators scores
    /// @param _scoreSum score sum
    /// @param _randomNumber randomness
    /// @return uint256 index
    function _getRandomIndex(uint256[] memory _scores, uint256 _scoreSum, uint256 _randomNumber) internal pure returns (uint256) {
        uint256 random = _randomNumber % _scoreSum;
        uint256 sum = 0;
        uint256 index = 0;
        while (sum <= random) {
            sum = sum.add(_scores[index]);
            index = index.add(1);
        }
        return index.sub(1);
    }

    /// @notice Get validator index.
    /// @param  _oracles validators
    /// @param  _randomIndex the index
    /// @return uint256 the actual index
    function _getValidatorIndex(ValidatorIndex [] memory _oracles, uint256 _randomIndex) internal pure returns (uint256) {
        if (_oracles[_randomIndex].exists) {
            return _oracles[_randomIndex].index;
        } else {
            return _randomIndex;
        }
    }

    /// @dev    logs the function calls.
    function _logs_() internal {
        emit LogCall(msg.sig, msg.sender, msg.data);
    }

    /// @dev    Only the authorized contracts can make requests.
    function _onlyAggregator() internal view {
        require(contractRegistry.requireAndGetAddress("PlennyOracleValidator") == msg.sender, "ERR_NON_AGGR");
    }
}

