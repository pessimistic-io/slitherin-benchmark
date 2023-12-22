// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PlennyBaseUpgradableV2.sol";
import "./PlennyCoordinatorStorage.sol";
import "./RewardLibV2.sol";

import "./ArbSys.sol";

/// @title  PlennyCoordinator
/// @notice Coordinator contract between the Lightning Network and the Ethereum blockchain. Coordination and storing of
///         the data from the LN on-chain. Allows the users to provide info about their lightning nodes/channels,
///         and manages the channel rewards (i.e. NCCR) due for some actions.
contract PlennyCoordinatorV2 is PlennyBaseUpgradableV2, PlennyCoordinatorStorage {

    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IPlennyERC20;
    using RewardLibV2 for uint256;

    /// An event emitted when a lightning node is added, but not yet verified.
    event LightningNodePending(address indexed by, uint256 verificationCapacity, string publicKey, address validatorAddress, uint256 indexed nodeIndex);
    /// An event emitted when a lightning node is verified.
    event LightningNodeVerified(address indexed to, string publicKey, uint256 indexed nodeIndex);
    /// An event emitted when a lightning channel is added, but not yet confirmed.
    event LightningChannelOpeningPending(address indexed by, string channelPoint, uint256 indexed channelIndex);
    /// An event emitted when a lightning channel is confirmed.
    event LightningChannelOpeningConfirmed(address to, uint256 amount, string node1, string node2, uint256 indexed channelIndex, uint256 blockNumber);
    /// An event emitted when a lightning channel is closed.
    event LightningChannelClosed(uint256 channelIndex);
    /// An event emitted when a reward is collected.
    event RewardReleased(address to, uint256 amount);
    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @notice Allows the user to add provisional information about their own lightning node.
    /// @dev    The lightning node is considered as "pending" in the system until the user verifies it by opening a channel
    ///         with a given capacity on the lightning network and submitting info (channel point) about that channel
    ///         in this contract.
    /// @param  nodePublicKey Public key of the lightning node.
    /// @param  validatorAddress An oracle validator address is responsible for validating the lightning node.
    /// @return uint256 The capacity of the channel that the user needs to open on the lightning network.
    function addLightningNode(string calldata nodePublicKey, address validatorAddress) external returns (uint256) {
        uint256 nodeIndex = nodeIndexPerPubKey[nodePublicKey][msg.sender];

        LightningNode storage node = nodes[nodeIndex];

        require(node.validatorAddress != validatorAddress, "ERR_DUPLICATE");
        if (nodeIndex > 0) {
            node.status = 2;
        }

        IPlennyDappFactory factory = contractRegistry.factoryContract();
        require(factory.isOracleValidator(validatorAddress), "ERR_NOT_ORACLE");

        uint256 verificationCapacity = factory.random();

        nodesCount++;
        nodes[nodesCount] = LightningNode(verificationCapacity, _blockNumber(), nodePublicKey, validatorAddress,
            0, 0, msg.sender);

        nodeIndexPerPubKey[nodePublicKey][msg.sender] = nodesCount;
        nodeOwnerCount[msg.sender]++;
        nodesPerAddress[msg.sender].push(nodesCount);

        emit LightningNodePending(msg.sender, verificationCapacity, nodePublicKey, validatorAddress, nodesCount);

        return (verificationCapacity);
    }

    /// @notice Submits a claim/info that a certain channel has been opened on the lightning network.
    /// @dev    The information can be submitted either by the end-user directly or by the maker that has opened
    ///         the channel via the lightning ocean/marketplace.
    /// @param  _channelPoint Channel point of the lightning channel.
    /// @param  _oracleAddress an address of the lightning oracle that is the counter-party of the lightning channel.
    /// @param  capacityRequest if this channel is opened via the lightning ocean/marketplace.
    function openChannel(string memory _channelPoint, address payable _oracleAddress, bool capacityRequest) external override {

        require(_oracleAddress != msg.sender, "ERR_SELF");

        require(contractRegistry.factoryContract().isOracleValidator(_oracleAddress)
            || contractRegistry.oceanContract().makerIndexPerAddress(_oracleAddress) > 0, "ERR_NOT_ORACLE");

        address payable nodeOwner;
        if (capacityRequest) {
            nodeOwner = _oracleAddress;
        } else {
            nodeOwner = msg.sender;
        }

        // check if the user has at least one verified node
        uint256 ownedNodes = nodeOwnerCount[nodeOwner];
        require(ownedNodes > 0, "ERR_NOT_FOUND");

        // check if this channel was already added
        uint256 channelIndex = channelIndexPerId[_channelPoint][nodeOwner];
        require(channelIndex == 0, "ERR_DUPLICATE");
        require(confirmedChannelIndexPerId[_channelPoint] == 0, "ERR_DUPLICATE");

        channelsCount++;
        channels[channelsCount] = LightningChannel(0, _blockNumber(), 0, 0, 0, nodeOwner,
            _oracleAddress, 0, 0, _channelPoint, 0, _altBlockNumber());

        channelsPerAddress[nodeOwner].push(channelsCount);
        channelIndexPerId[_channelPoint][nodeOwner] = channelsCount;
        channelStatusCount[0]++;

        emit LightningChannelOpeningPending(nodeOwner, _channelPoint, channelsCount);
    }

    /// @notice Instant verification of the initial(ZERO) lightning node. Managed by the contract owner.
    /// @param  publicKey The public key of the initial lightning node.
    /// @param  account address of the initial lightning oracle.
    /// @return uint256 node index
    function verifyDefaultNode(string calldata publicKey, address payable account) external override returns (uint256){
        _onlyFactory();

        nodesCount++;
        nodes[nodesCount] = LightningNode(0, _blockNumber(), publicKey, account, 1, _blockNumber(), account);
        nodeIndexPerPubKey[publicKey][account] = nodesCount;
        nodesPerAddress[account].push(nodesCount);
        uint256 newNodeIndex = nodeIndexPerPubKey[publicKey][account];

        nodeOwnerCount[account]++;
        return newNodeIndex;
    }

    /// @notice Confirms that a lightning channel with the provided information was indeed opened on the lightning network.
    ///         Once a channel is confirmed, the submitter of the channel info becomes eligible for collecting rewards as long
    ///         as the channel is kept open on the lightning network. In case this channel is opened as a result of
    ///         verification of a lightning node, the node gets also marked as "verified".
    /// @dev    This is only called by the validation mechanism once the validators have reached the consensus on the
    ///         information provided below.
    /// @param  channelIndex index/id of the channel submission as registered in this contract.
    /// @param  _channelCapacitySat The capacity of the channel expressed in satoshi.
    /// @param  channelId Id of the channel as registered on the lightning network.
    /// @param  node1PublicKey The public key of the first node in the channel.
    /// @param  node2PublicKey The public key of the second node in the channel.
    function confirmChannelOpening(uint256 channelIndex, uint256 _channelCapacitySat,
        uint256 channelId, string memory node1PublicKey, string memory node2PublicKey) external override nonReentrant {
        _onlyAggregator();
        require(channelIndex > 0, "ERR_CHANNEL_NOT_FOUND");
        require(_channelCapacitySat > 0, "ERR_EMPTY");

        LightningChannel storage channel = channels[channelIndex];
        require(channel.status == 0, "ERR_WRONG_STATE");
        require(confirmedChannelIndexPerId[channel.channelPoint] == 0, "ERR_DUPLICATE");

        NodeInfo memory nodeInfo = NodeInfo(0, "0", "0");
        if (nodeIndexPerPubKey[node1PublicKey][channel.to] > 0) {
            nodeInfo.nodeIndex = nodeIndexPerPubKey[node1PublicKey][channel.to];
            nodeInfo.ownerPublicKey = node1PublicKey;
            nodeInfo.validatorPublicKey = node2PublicKey;
        } else {
            if (nodeIndexPerPubKey[node2PublicKey][channel.to] > 0) {
                nodeInfo.nodeIndex = nodeIndexPerPubKey[node2PublicKey][channel.to];
                nodeInfo.ownerPublicKey = node2PublicKey;
                nodeInfo.validatorPublicKey = node1PublicKey;
            }
        }

        // check if the channel matches data in smart contracts
        require(nodeInfo.nodeIndex > 0, "ERR_NODE_NOT_FOUND");
        LightningNode storage node = nodes[nodeInfo.nodeIndex];
        require(stringsEqual(node.publicKey, nodeInfo.ownerPublicKey), "ERR_WRONG_STATE");
        require(node.to == channel.to, "ERR_NODE_CHANNEL_MATCH");

        if (node.status == 0) {
            // verify the node
            if (node.capacity == _channelCapacitySat) {
                node.status = 1;
                node.verifiedDate = _blockNumber();
                emit LightningNodeVerified(node.to, node.publicKey, nodeInfo.nodeIndex);
            }
        }

        require(node.status == 1, "ERR_WRONG_STATE");

        // reserve the amount in the escrow
        channel.id = channelId;
        channel.status = 1;
        channel.capacity = _channelCapacitySat;
        channel.confirmedDate = _blockNumber();
        channel.blockNumber = contractRegistry.validatorElectionContract().latestElectionBlock();
        channelRewardStart[channel.id] = _blockNumber();
        confirmedChannelIndexPerId[channel.channelPoint] = channelIndex;

        channelStatusCount[0]--;
        channelStatusCount[1]++;

        uint256 potentialTreasuryRewardAmount = 0;

        IPlennyOcean plennyOcean = contractRegistry.oceanContract();
        uint256 capacityRequestIndex = plennyOcean.capacityRequestPerChannel(channel.channelPoint);
        if (capacityRequestIndex > 0) {
            (uint256 capacity,,,,,, string memory channelPoint,) = plennyOcean.capacityRequests(capacityRequestIndex);
            if (stringsEqual(channelPoint, channel.channelPoint)) {
                potentialTreasuryRewardAmount = _calculatePotentialReward(_channelCapacitySat, true);
                channel.rewardAmount = potentialTreasuryRewardAmount.add(rewardBaseline);
                //increment total inbound capacity
                totalInboundCapacity += capacity;
                // process the request
                plennyOcean.processCapacityRequest(capacityRequestIndex);
            }
        } else {
            potentialTreasuryRewardAmount = _calculatePotentialReward(_channelCapacitySat, false);
            channel.rewardAmount = potentialTreasuryRewardAmount.add(rewardBaseline);

            IPlennyDappFactory factory = contractRegistry.factoryContract();
            (,uint256 validatorNodeIndex,,,,,,) = factory.validators(factory.validatorIndexPerAddress(channel.oracleAddress));
            require(stringsEqual(nodeInfo.validatorPublicKey, nodes[validatorNodeIndex].publicKey), "ERR_WRONG_STATE");
            totalOutboundCapacity += channel.capacity;
        }

        emit LightningChannelOpeningConfirmed(channel.to, potentialTreasuryRewardAmount, nodeInfo.ownerPublicKey, nodeInfo.validatorPublicKey, channelIndex, _blockNumber());
    }

    /// @notice Marks that a previously opened channel on the lightning network has been closed.
    /// @dev    This is only called by the validation mechanism once the validators have reached the consensus that
    ///         the channel has been indeed closed on the lightning network.
    /// @param  channelIndex index/id of the channel submission as registered in this contract.
    function closeChannel(uint256 channelIndex) external override nonReentrant {
        _onlyAggregator();
        require(channelIndex > 0, "ERR_EMPTY");

        LightningChannel storage channel = channels[channelIndex];
        require(channel.status == 1, "ERR_WRONG_STATE");

        channel.status = 2;
        channel.closureDate = _blockNumber();
        channelStatusCount[1]--;

        IPlennyOcean ocean = contractRegistry.oceanContract();
        uint256 capacityRequestIndex = ocean.capacityRequestPerChannel(channel.channelPoint);
        if (ocean.capacityRequestsCount() > 0) {
            totalInboundCapacity -= channel.capacity;
            (,,,,,, string memory channelPoint,) = ocean.capacityRequests(capacityRequestIndex);
            if (stringsEqual(channelPoint, channel.channelPoint)) {
                ocean.closeCapacityRequest(capacityRequestIndex, channel.id, channel.confirmedDate);
            }
        } else {
            totalOutboundCapacity -= channel.capacity;
        }

        _collectChannelRewardInternal(channel);

        emit LightningChannelClosed(channelIndex);
    }

    /// @notice Batch collect of all pending rewards for all the channels opened by the sender.
    /// @param  channelIndex indexes/ids of the channel submissions as registered in this contract.
    function claimAllChannelsReward(uint256 [] calldata channelIndex) external nonReentrant {
        for (uint256 i = 0; i < channelIndex.length; i++) {
            _collectChannelReward(channelIndex[i]);
        }
    }

    /// @notice Collects pending rewards only for the provided channel opened by the sender.
    /// @param  channelIndex index/id of the channel submission as registered in this contract.
    function collectChannelReward(uint256 channelIndex) external nonReentrant {
        _collectChannelReward(channelIndex);
    }

    /// @notice Gets the number of opened channels as registered in this contract.
    /// @return uint256 opened channels count
    function getChannelsCount() external view returns (uint256){
        return channelStatusCount[1];
    }

    /// @notice Gets all the submitted nodes for the given address.
    /// @param  addr Address to check for
    /// @return array indexes of all the nodes that belong to the address
    function getNodesPerAddress(address addr) external view returns (uint256[] memory){
        return nodesPerAddress[addr];
    }

    /// @notice Gets all the submitted channels for the given address.
    /// @param  addr Address to check for
    /// @return array indexes of all the channels that belong to the address
    function getChannelsPerAddress(address addr) external view returns (uint256[] memory){
        return channelsPerAddress[addr];
    }

    /// @notice Calculates the potential reward for the given channel capacity. If the channel is opened through the
    ///         ocean/marketplace the reward is increased.
    /// @param  capacity capacity of the channel
    /// @param  marketplace if the reward comes as a result of marketplace action.
    /// @return potentialReward channel reward
    function _calculatePotentialReward(uint256 capacity, bool marketplace) public view returns (uint256 potentialReward){
        uint256 treasuryBalance = contractRegistry.plennyTokenContract().balanceOf(contractRegistry.getAddress("PlennyTreasury"));

        IPlennyDappFactory factory = contractRegistry.factoryContract();

        return capacity.calculateReward(
            marketplace,
            channelRewardThreshold,
            maximumChannelCapacity,
            factory.makersFixedRewardAmount(),
            factory.makersRewardPercentage(),
            factory.capacityFixedRewardAmount(),
            factory.capacityRewardPercentage(),
            treasuryBalance);
    }


    /// @notice Check string equality
    /// @param  a first string
    /// @param  b second string
    /// @return bool true/false
    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    /// @notice Only oracle consensus validators
    function _onlyAggregator() internal view {
        require(contractRegistry.getAddress("PlennyOracleValidator") == msg.sender, "ERR_NON_AGGR");
    }

    /// @notice Only plenny oracle factory
    function _onlyFactory() internal view {
        require(contractRegistry.getAddress("PlennyDappFactory") == msg.sender, "ERR_NOT_FACTORY");
    }

    /// @notice In case the contract is deployed on Arbitrum, get the Arbitrum block number.
    /// @return uint256 L1 block number or L2 block number
    function _altBlockNumber() internal view returns (uint256){
        uint chainId = getChainId();
        if (chainId == 42161 || chainId == 421611) {
            return ArbSys(address(100)).arbBlockNumber();
        } else {
            return block.number;
        }
    }

    /// @notice id of the network the contract is deployed to.
    /// @return chainId Network id
    function getChainId() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    /// @notice Collects a reward for a given channel
    /// @param  channel opened/active channel
    function _collectChannelRewardInternal(LightningChannel storage channel) private {
        address payable _to = channel.to;

        IPlennyDappFactory factory = contractRegistry.factoryContract();
        uint256 _reward = _blockNumber() - channelRewardStart[channel.id] > factory.userChannelRewardPeriod()
        ? channel.rewardAmount.mul(factory.userChannelReward()).mul(_blockNumber() - channelRewardStart[channel.id])
        .div(factory.userChannelRewardPeriod()).div(10000) : 0;
        if (_reward > channel.rewardAmount) {
            _reward = channel.rewardAmount;
        }

        uint256 rewardFee = _reward.mul(factory.userChannelRewardFee()).div(100).div(100);

        totalTimeReward += _reward;
        channel.rewardAmount -= _reward;
        channelRewardStart[channel.id] = _blockNumber();
        emit RewardReleased(_to, _reward);

        IPlennyTreasury treasury = contractRegistry.treasuryContract();

        require(treasury.approve(address(this), rewardFee), "failed");
        contractRegistry.plennyTokenContract().safeTransferFrom(address(treasury),
            contractRegistry.getAddress("PlennyRePLENishment"), rewardFee);

        require(treasury.approve(contractRegistry.getAddress("PlennyCoordinator"), _reward - rewardFee), "failed");
        contractRegistry.plennyTokenContract().safeTransferFrom(address(treasury), _to, _reward - rewardFee);
    }

    /// @notice Collects a reward for a given index/id of a channel
    /// @param  channelIndex channel index/id
    function _collectChannelReward(uint256 channelIndex) private {
        require(channelIndex > 0, "ERR_EMPTY");

        LightningChannel storage channel = channels[channelIndex];
        require(channel.status == 1, "ERR_WRONG_STATE");

        IPlennyOcean ocean = contractRegistry.oceanContract();

        uint256 capacityRequestIndex = ocean.capacityRequestPerChannel(channel.channelPoint);
        if (ocean.capacityRequestsCount() > 0) {
            (,,,,,, string memory channelPoint,) = ocean.capacityRequests(capacityRequestIndex);
            if (stringsEqual(channelPoint, channel.channelPoint)) {
                ocean.collectCapacityRequestReward(capacityRequestIndex, channel.id, channel.confirmedDate);
            }
        }

        _collectChannelRewardInternal(channel);
    }

    /// @notice Set the maximum channel capacity (in satoshi).
    /// @dev    Only the owner of the contract can set this.
    /// @param  newMaximum maximum channel capacity (in satoshi)
    function setMaximumChannelCapacity(uint256 newMaximum) external onlyOwner {
        require(newMaximum > minimumChannelCapacity, "ERR_BELOW_MINIMUM");
        maximumChannelCapacity = newMaximum;
    }

    /// @notice Set the minimum channel capacity (in satoshi).
    /// @dev    Only the owner of the contract can set this.
    /// @param  newMinimum channel threshold (in satoshi)
    function setMinimumChannelCapacity(uint256 newMinimum) external onlyOwner {
        require(newMinimum < maximumChannelCapacity, "ERR_VALUE_TOO_LOW");
        minimumChannelCapacity = newMinimum;
    }

    /// @notice Set the channel threshold (in satoshi) for which a reward is given.
    /// @dev    Only the owner of the contract can set this.
    /// @param  threshold minimum channel capacity (in satoshi)
    function setChannelRewardThreshold(uint256 threshold) external onlyOwner {
        require(threshold > minimumChannelCapacity, "ERR_BELOW_THRESHOLD");
        require(threshold < maximumChannelCapacity, "ERR_ABOVE_THRESHOLD");
        channelRewardThreshold = threshold;
    }

    /// @notice Changes the reward baseline. Managed by the contract owner.
    /// @param  value reward baseline
    function setRewardBaseline(uint256 value) external onlyOwner {
        rewardBaseline = value;
    }
}
