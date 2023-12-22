// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IPlennyERC20.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyValidatorElectionStorage.sol";


/// @title  PlennyValidatorElection
/// @notice Contains the logic for the election cycle and the process of electing validators based on
///         Delegated Proof of Stake (DPoS), and reserves rewards.
contract PlennyValidatorElection is PlennyBasePausableV2, PlennyValidatorElectionStorage {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
    /// An event emitted when the rewards are distributed.
    event OracleReward(address indexed to, uint256 amount);

    /// @notice Initializes the smart contract instead of a constructor. Called once during deploy.
    /// @param  _registry Plenny contract registry
    function initialize(address _registry) external initializer {

        // 1 week in blocks
        newElectionPeriod = 45500;

        maxValidators = 3;

        // 0.5%
        userRewardPercent = 50;

        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Triggers a new election. Fails if not enough time has passed from the previous election.
    function newElection() external whenNotPaused nonReentrant {
        _logs_();

        if (latestElectionBlock > 0) {
            require(activeElection[latestElectionBlock][0].created + newElectionPeriod <= _blockNumber(), "ERR_LOCKED");
        }

        IPlennyERC20 token = contractRegistry.plennyTokenContract();

        require(contractRegistry.treasuryContract().approve(address(this),
            pendingElectionReward[latestElectionBlock]), "failed");
        token.safeTransferFrom(contractRegistry.requireAndGetAddress("PlennyTreasury"),
                address(this),
                pendingElectionReward[latestElectionBlock]);

        // send reward to the user
        token.safeTransfer(msg.sender, pendingUserReward[latestElectionBlock]);

        address[] memory existingValidators = electedValidators[latestElectionBlock];
        for (uint i = 0; i < existingValidators.length; i++) {
            address oracle = existingValidators[i];

            uint256 myReward = pendingElectionRewardPerValidator[latestElectionBlock][oracle];

            contractRegistry.factoryContract().updateReputation(oracle, myReward);

            if (myReward > 0) {
                uint256 potentialDelegatedReward = myReward.mul(elections[latestElectionBlock][oracle].delegatedBalance)
                .div(elections[latestElectionBlock][oracle].stakedBalance + elections[latestElectionBlock][oracle].delegatedBalance);
                uint256 sharedDelegatedReward = potentialDelegatedReward.mul(elections[latestElectionBlock][oracle].revenueShare).div(100);

                // Send reward to the oracle
                uint256 oracleReward = myReward - sharedDelegatedReward;
                token.safeTransfer(oracle, oracleReward);

                if (sharedDelegatedReward > 0) {
                    for (uint256 k = 0; k < elections[latestElectionBlock][oracle].delegators.length; k++) {
                        uint256 delegatorReward = elections[latestElectionBlock][oracle].delegatedBalance == 0 ? 0 :
                        sharedDelegatedReward.mul(elections[latestElectionBlock][oracle].delegatorsBalance[k])
                        .div(elections[latestElectionBlock][oracle].delegatedBalance);

                        if (delegatorReward > 0) {
                            token.safeTransfer(elections[latestElectionBlock][oracle].delegators[k], delegatorReward);
                            emit OracleReward(elections[latestElectionBlock][oracle].delegators[k], delegatorReward);
                        }
                    }
                }
            }
        }

        // scores holds a list of score for every validator
        (uint256[] memory scores, uint256 scoreSum) = contractRegistry.factoryContract().getValidatorsScore();
        ValidatorIndex [] memory oracles = new ValidatorIndex[](scores.length);

        // New election
        require(scores.length > 0 && scoreSum > 0, "ERR_NO_VALIDATORS");
        uint256 length = scores.length > maxValidators ? maxValidators : scores.length;
        address[] memory newValidators = new address[](length);

        uint256 randomNumber = contractRegistry.factoryContract().pureRandom();
        uint256 oraclesToBeElectedLength = scores.length;

        latestElectionBlock = _blockNumber();
        for (uint i = 0; i < newValidators.length; i++) {
            randomNumber = uint256(keccak256(abi.encode(randomNumber)));
            uint256 randomIndex = _getRandomIndex(scores, scoreSum, randomNumber);
            uint256 validatorIndex = _getValidatorIndex(oracles, randomIndex);

            (,,,,, uint256 revenueShare,address owner,) = contractRegistry.factoryContract().validators(validatorIndex);

            newValidators[i] = owner;
            validators[latestElectionBlock][owner] = true;

            scoreSum -= scores[randomIndex];
            oraclesToBeElectedLength--;
            scores[randomIndex] = scores[oraclesToBeElectedLength];
            if (oracles[oraclesToBeElectedLength].exists) {
                oracles[randomIndex] = oracles[oraclesToBeElectedLength];
            } else {
                oracles[randomIndex] = ValidatorIndex(oraclesToBeElectedLength, true);
            }

            // Creating snapshot
            uint256 stakedBalance = contractRegistry.stakingContract().plennyBalance(newValidators[i]);
            uint256 delegatedBalance = contractRegistry.factoryContract().getDelegatedBalance(newValidators[i]);

            address[] memory delegators = contractRegistry.factoryContract().getDelegators(newValidators[i]);
            uint256[] memory delegatorsBalance = new uint256[](delegators.length);
            for (uint256 j = 0; j < delegators.length; j++) {
                delegatorsBalance[j] = contractRegistry.stakingContract().plennyBalance(delegators[j]);
            }

            elections[latestElectionBlock][newValidators[i]] = Election(latestElectionBlock, revenueShare, stakedBalance, delegatedBalance, delegators, delegatorsBalance);
            activeElection[latestElectionBlock].push(Election(latestElectionBlock, revenueShare, stakedBalance, delegatedBalance, delegators, delegatorsBalance));
        }
        electedValidators[latestElectionBlock] = newValidators;

    }

    /// @notice Reserves a reward for a given validator as a result of a oracle validation done on-chain.
    /// @param  validator to reserve reward for
    /// @param  oracleChannelReward the reward amount
    function reserveReward(address validator, uint256 oracleChannelReward) external override whenNotPaused nonReentrant {
        _onlyAggregator();

        uint256 userReward = oracleChannelReward.mul(userRewardPercent).div(10000);
        uint256 validatorReward = oracleChannelReward - userReward;

        pendingUserReward[latestElectionBlock] += userReward;
        pendingElectionRewardPerValidator[latestElectionBlock][validator] += validatorReward;
        pendingElectionReward[latestElectionBlock] += oracleChannelReward;
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
            sum += _scores[index];
            index++;
        }
        return index - 1;
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

