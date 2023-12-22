// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

pragma experimental ABIEncoderV2;

import "./SafeMathUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyOracleValidatorStorage.sol";
import "./IPlennyERC20.sol";

/// @title  PlennyOracleValidatorV2 version 2
/// @notice Runs channel validations (for opening and closing) and contains the logic for reaching consensus among the
///         oracle validators participating in the  Decentralized Oracle Network (DON).
contract PlennyOracleValidatorV2 is PlennyBasePausableV2, PlennyOracleValidatorStorage {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// An event emitted when channel opening info is committed.
    event ChannelOpeningCommit(address indexed leader, uint256 indexed channelIndex);
    /// An event emitted when channel opening is verified.
    event ChannelOpeningVerify(address indexed validator, uint256 indexed channelIndex);
    /// An event emitted when channel opening info is revealed and checked.
    event ChannelOpeningReveal(address indexed leader, uint256 channelIndex);

    /// An event emitted when channel closing info committed.
    event ChannelClosingCommit(address indexed leader, uint256 indexed channelIndex);
    /// An event emitted when channel closing is verified.
    event ChannelClosingVerify(address indexed validator, uint256 indexed channelIndex);
    /// An event emitted when channel closing info is revealed and checked.
    event ChannelCloseReveal(address indexed leader, uint256 channelIndex);

    /// @dev    log function call.
    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /// @dev    only oracle validator check.
    modifier onlyValidators {

        IPlennyValidatorElection validatorElection = contractRegistry.validatorElectionContract();
        require(validatorElection.validators(validatorElection.latestElectionBlock(), msg.sender), "ERR_NOT_VALIDATOR");
        _;
    }

    /// @notice Called whenever an oracle has gathered enough signatures from other oracle validators offline,
    ///         containing the channel information on the Lightning Network.
    ///         The sender oracle validator (i.e leader) claims the biggest reward for posting the data on-chain.
    ///         Other off-chain validators also receive a smaller reward for their off-chain validation.
    /// @dev    All oracle validators are running the Plenny oracle service. When a new channel opening needs to be
    ///         verified on the Lightning Network, the validators are competing with each other to obtain the data from
    ///         the Lightning Network and get enough signatures for that data from other validators.
    ///         Whoever validator gets enough signatures first is entitled to call this function for posting the data on-chain.
    /// @param  channelIndex index/id of the channel submission as registered in this contract.
    /// @param  _channelCapacitySat capacity of the channel expressed in satoshi.
    /// @param  channelId Id of the channel as registered on the lightning network.
    /// @param  nodePublicKey Public key of the first node in the channel.
    /// @param  node2PublicKey Public key of the second node in the channel.
    /// @param  signatures array of validators signatures gathered offline. They are verified against the channel data.
    function execChannelOpening(uint256 channelIndex, uint256 _channelCapacitySat,
        uint256 channelId, string calldata nodePublicKey, string calldata node2PublicKey, bytes[] memory signatures)
    external onlyValidators whenNotPaused _logs_ {

        require(latestOpenChannelAnswer[channelIndex] == 0, "ERR_ANSWERED");

        bytes32 dataHash = keccak256(abi.encodePacked(channelIndex, _channelCapacitySat, channelId, nodePublicKey, node2PublicKey));
        IPlennyValidatorElection validatorElection = contractRegistry.validatorElectionContract();

        for (uint i = 0; i < signatures.length; i++) {
            address signatory = ECDSAUpgradeable.recover(
                keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)),
                signatures[i]);

            // check if the signatory is a validator
            if (validatorElection.validators(validatorElection.latestElectionBlock(), signatory)
                && !oracleOpenChannelAnswers[channelIndex][signatory]) {

                oracleOpenChannelConsensus[channelIndex].push(signatory);
                oracleOpenChannelAnswers[channelIndex][signatory] = true;
                oracleValidations[validatorElection.latestElectionBlock()][signatory]++;
            }
        }

        require(oracleOpenChannelAnswers[channelIndex][msg.sender], "ERR_SENDER_MISSING_SIGNATURE");
        require(oracleOpenChannelConsensus[channelIndex].length >= minQuorum(), "ERR_OPEN_CONSENSUS");

        latestOpenChannelAnswer[channelIndex] = dataHash;
        distributeOracleRewards(oracleOpenChannelConsensus[channelIndex], msg.sender);

        contractRegistry.coordinatorContract().confirmChannelOpening(channelIndex,
            _channelCapacitySat, channelId,
            nodePublicKey, node2PublicKey);
        emit ChannelOpeningReveal(msg.sender, channelIndex);

    }

    /// @notice Called whenever an oracle has gathered enough signatures from other oracle validators offline,
    ///         containing the information of the channel closing on the Lightning Network.
    ///         The sender oracle validator (i.e leader) claims the biggest reward for posting the data on-chain.
    ///         Other off-chain validators also receive a smaller reward for their off-chain validation.
    /// @dev    All oracle validators are running the Plenny oracle service. When a channel is closed on the Lightning Network,
    ///         the validators are competing with each other's to obtain the closing transaction data from the lightning Network
    ///         and get enough signature for that data from other validators off-chain.
    ///         Whoever validator gets enough signatures first is entitled to call this function for posting the data on-chain.
    /// @param  channelIndex channel index/id of an already opened channel
    /// @param  closingTransactionId bitcoin closing transaction id of the closing lightning channel
    /// @param  signatures signatures array of validators signatures gathered via validator's REST API. They are verified against the channel data.
    function execCloseChannel(uint256 channelIndex, string memory closingTransactionId, bytes[] memory signatures)
    external onlyValidators whenNotPaused nonReentrant _logs_ {

        require(latestCloseChannelAnswer[channelIndex] == 0, "ERR_ANSWERED");

        bytes32 dataHash = keccak256(abi.encodePacked(channelIndex, closingTransactionId));
        IPlennyValidatorElection validatorElection = contractRegistry.validatorElectionContract();

        for (uint i = 0; i < signatures.length; i++) {
            address signatory = ECDSAUpgradeable.recover(
                keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)),
                signatures[i]);

            // check if the signatory is a validator
            if (validatorElection.validators(validatorElection.latestElectionBlock(), signatory)
                && !oracleCloseChannelAnswers[channelIndex][signatory]) {

                oracleCloseChannelConsensus[channelIndex].push(signatory);
                oracleCloseChannelAnswers[channelIndex][signatory] = true;
                oracleValidations[validatorElection.latestElectionBlock()][signatory]++;
            }
        }

        require(oracleCloseChannelAnswers[channelIndex][msg.sender], "ERR_SENDER_MISSING_SIGNATURE");
        require(oracleCloseChannelConsensus[channelIndex].length >= minQuorum(), "ERR_CLOSE_CONSENSUS");

        latestCloseChannelAnswer[channelIndex] = dataHash;
        distributeOracleRewards(oracleCloseChannelConsensus[channelIndex], msg.sender);
        contractRegistry.coordinatorContract().closeChannel(channelIndex);

        emit ChannelCloseReveal(msg.sender, channelIndex);
    }

    /// @notice Changes the oracle reward percentage. Called by the contract owner.
    /// @param  value oracle validator reward
    function setOracleRewardPercentage(uint256 value) external onlyOwner {
        oracleRewardPercentage = value;
    }

    /// @notice Changes the oracle fixed reward amount. Called by the contract owner.
    /// @param  value oracle validator fixed reward
    function setOracleFixedRewardAmount(uint256 value) external onlyOwner {
        oracleFixedRewardAmount = value;
    }


    /// @notice Changes the leader reward percentage. Called by the contract owner.
    /// @param  amount leader percentage
    function setLeaderRewardPercent(uint256 amount) external onlyOwner {
        leaderRewardPercent = amount;
    }

    /// @notice Consensus length for the given channel (opening).
    /// @param  channelIndex channel id
    /// @return uint256 how many validators has reached consensus for this channel
    function oracleOpenChannelConsensusLength(uint256 channelIndex) external view returns (uint256) {
        return oracleOpenChannelConsensus[channelIndex].length;
    }

    /// @notice Consensus length for the given channel (closing).
    /// @param  channelIndex channel id
    /// @return uint256 how many validators has reached consensus for this channel
    function oracleCloseChannelConsensusLength(uint256 channelIndex) external view returns (uint256) {
        return oracleCloseChannelConsensus[channelIndex].length;
    }

    /// @notice Minimum quorum for reaching the oracle validator consensus.
    /// @return uint256 consensus quorum
    function minQuorum() public view returns (uint256) {

        IPlennyValidatorElection validatorElection = contractRegistry.validatorElectionContract();

        uint quorum = validatorElection.getElectedValidatorsCount(validatorElection.latestElectionBlock()).mul(minQuorumDivisor).div(100);
        return quorum > 0 ? quorum : 1;
    }

    /// @notice Distributes all the oracle validators reward for the given validation cycle.
    /// @param  signatories off-chain validators
    /// @param  leader on-chain validator
    function distributeOracleRewards(address[] memory signatories, address leader) internal {

        uint256 treasuryBalance = contractRegistry.plennyTokenContract().balanceOf(
            contractRegistry.requireAndGetAddress("PlennyTreasury"));
        uint256 oracleChannelReward;

        if (oracleFixedRewardAmount < oracleRewardPercentage.mul(treasuryBalance).div(100).div(100000)) {
            oracleChannelReward = oracleFixedRewardAmount;
        } else {
            oracleChannelReward = oracleRewardPercentage.mul(treasuryBalance).div(100).div(100000);
        }

        totalOracleReward = totalOracleReward.add(oracleChannelReward);

        // distribute the reward to the signatories
        for (uint i = 0; i < signatories.length; i++) {
            address signatory = signatories[i];

            uint256 signatoryReward = leader == signatory ? oracleChannelReward.mul(leaderRewardPercent).div(100)
            : (oracleChannelReward.sub(oracleChannelReward.mul(leaderRewardPercent).div(100))).div(signatories.length.sub(1));

            contractRegistry.factoryContract().updateReputation(signatory, signatoryReward);

            contractRegistry.treasuryContract().approve(address(this), signatoryReward);
            contractRegistry.plennyTokenContract().safeTransferFrom(contractRegistry.requireAndGetAddress("PlennyTreasury"),
                signatory, signatoryReward);
        }
    }
}

