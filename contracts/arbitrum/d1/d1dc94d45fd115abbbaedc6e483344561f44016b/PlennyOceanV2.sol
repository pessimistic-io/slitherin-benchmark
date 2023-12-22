// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyOceanStorage.sol";

/// @title  PlennyOcean
/// @notice Managing the capacity market. This smart contract refers to the non-custodial peer-to-peer marketplace for payment
///         channels to license liquidity of lightning nodes (i.e. inbound capacity). PlennyOcean enables lightning nodes
///         to publish offers in PL2/sat, and select counterparties. The Liquidity Maker is responsible for opening the
///         payment channel, and for providing the channel capacity to the Liquidity Taker over the Lightning Network,
///         and for giving the information on the smart contract that contains the payment channel data (from the PlennyCoordinator).
contract PlennyOceanV2 is PlennyBasePausableV2, PlennyOceanStorage {

    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when the capacity request is submitted.
    event CapacityRequestPending(address indexed by, uint256 capacity, address makerAddress,
        uint256 indexed capacityRequestIndex, uint256 paid);
    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;
    /// An event emitted when Liquidity Maker is added.
    event MakerAdded(address account, bool created);

    /// @dev    Only PlennyCoordinator contract checks.
    modifier onlyCoordinator {
        address coordAddress = contractRegistry.requireAndGetAddress("PlennyCoordinator");
        require(coordAddress == msg.sender, "ERR_NOT_COORDINATOR");
        _;
    }

    /// @notice Adds/registers a new maker in the ocean. A maker needs to have a previously verified Lightning node
    ///         (in the PlennyCoordinator).
    /// @param  name Maker's name
    /// @param  serviceUrl url of the Lightning oracle service
    /// @param  nodeIndex index/id of the verified Lightning node
    /// @param  providingAmount the amount of liquidity provided
    /// @param  priceInPl2 price PL2/sat
    function addMaker(string calldata name, string calldata serviceUrl, uint256 nodeIndex, uint256 providingAmount, uint256 priceInPl2) external whenNotPaused {
        (,,,, uint256 status,, address to) = contractRegistry.coordinatorContract().nodes(nodeIndex);
        require(to == msg.sender, "ERR_NOT_OWNER");
        require(status == 1, "ERR_NOT_VERIFIED");

        uint256 index = makerIndexPerAddress[msg.sender];

        if (index == 0) {
            makersCount++;
            makers[makersCount] = MakerInfo(name, serviceUrl, msg.sender, nodeIndex, providingAmount, priceInPl2);
            makerIndexPerAddress[msg.sender] = makersCount;
        } else {
            makers[index] = MakerInfo(name, serviceUrl, msg.sender, nodeIndex, providingAmount, priceInPl2);
        }
        emit MakerAdded(msg.sender, index == 0);
    }

    /// @notice Called by the maker whenever there is a new request for channel capacity signed by the taker.
    /// @param  nodeUrl Lightning node to provide liquidity for
    /// @param  capacity channel capacity in satoshi
    /// @param  makerAddress maker's address
    /// @param  owner taker's address
    /// @param  nonce nonce
    /// @param  signature this request signature as signed by the taker
    function requestLightningCapacity(string calldata nodeUrl, uint256 capacity, address payable makerAddress,
        address payable owner, uint256 nonce, bytes calldata signature) external whenNotPaused nonReentrant {
        require(capacity >= contractRegistry.coordinatorContract().channelRewardThreshold(), "ERR_MIN_CAPACITY");

        require(owner != makerAddress, "ERR_YOUR_NODE");
        _checkSignature(nodeUrl, capacity, makerAddress, owner, nonce, signature);
        seenNonces[owner][nonce] = true;

        uint256 index = makerIndexPerAddress[makerAddress];
        MakerInfo storage maker = makers[index];
        require(maker.makerProvidingAmount >= capacity, "ERR_NO_LIQUIDITY");

        uint256 openingCapacity = capacity.mul(maker.makerRatePl2Sat);
        uint256 fee = openingCapacity.mul(takerFee).div(100).div(100);

        IPlennyStaking staking = contractRegistry.stakingContract();
        require(staking.plennyBalance(owner) >= openingCapacity.add(fee).add(makerCapacityOneTimeReward), "ERR_NO_FUNDS");

        updateMakerProvidingAmount(index, capacity, false);
        openingCapacity = openingCapacity.add(makerCapacityOneTimeReward);

        LightningCapacityRequest memory newCapacityRequest = LightningCapacityRequest(capacity, _blockNumber(), nodeUrl,
            makerAddress, 0, openingCapacity, "", owner);

        capacityRequestsCount++;
        capacityRequests[capacityRequestsCount] = newCapacityRequest;
        capacityRequestPerMaker[makerAddress].push(capacityRequestsCount);

        //manage takers
        if (capacityRequestPerTaker[owner].length == 0) {
            takersCount++;
        }
        capacityRequestPerTaker[owner].push(capacityRequestsCount);

        staking.decreasePlennyBalance(owner, openingCapacity, address(this));
        staking.decreasePlennyBalance(owner, fee, contractRegistry.requireAndGetAddress("PlennyRePLENishment"));

        emit CapacityRequestPending(owner, capacity, makerAddress, capacityRequestsCount, openingCapacity.add(fee));
    }

    /// @notice Cancels previously requested capacity. Can be cancelled by the taker when it is expired.
    ///         The request is considered expired if not processed within canceling request period
    ///         (measured in blocks) of its creation.
    /// @param  capacityRequestIndex id of the request
    function cancelRequestLightningCapacity(uint256 capacityRequestIndex) external whenNotPaused nonReentrant {
        LightningCapacityRequest storage capacityRequest = capacityRequests[capacityRequestIndex];
        require(capacityRequest.status == 0, "ERR_WRONG_STATE");
        require(capacityRequest.to == msg.sender, "ERR_NOT_YOURS");

        uint256 sec = _blockNumber().sub(capacityRequest.addedDate);
        require(sec > cancelingRequestPeriod, "ERR_NOT_EXPIRED");

        uint256 index = makerIndexPerAddress[capacityRequest.makerAddress];

        updateMakerProvidingAmount(index, capacityRequest.capacity, true);

        uint256 plennyReward = capacityRequest.plennyReward;
        capacityRequest.status = 3;
        capacityRequest.plennyReward = 0;

        IPlennyStaking staking = contractRegistry.stakingContract();
        _approve(address(staking), plennyReward);
        staking.increasePlennyBalance(msg.sender, plennyReward, address(this));

    }

    /// @notice Submits a claim/info that a certain channel has been opened as a result of a liquidity request.
    ///         Delegates to PlennyCoordinator for the channel verification.
    /// @param  _channelPoint channel info
    /// @param  capacityRequestIndex request id
    function openChannelRequested(string calldata _channelPoint, uint256 capacityRequestIndex) external whenNotPaused nonReentrant {
        LightningCapacityRequest storage capacityRequest = capacityRequests[capacityRequestIndex];

        require(capacityRequest.status == 0, "ERR_WRONG_STATE");
        require(capacityRequest.makerAddress == msg.sender, "ERR_NOT_FOUND");

        capacityRequest.status = 1;
        capacityRequest.channelPoint = _channelPoint;
        capacityRequestPerChannel[_channelPoint] = capacityRequestIndex;

        contractRegistry.coordinatorContract().openChannel(_channelPoint, capacityRequest.makerAddress, true);
    }

    /// @notice Called by the PlennyCoordinator whenever the channel opened as a result of a liquidity request becomes verified.
    ///         There can be only one channel opened per liquidity request.
    /// @param  capacityRequestIndex capacity request
    function processCapacityRequest(uint256 capacityRequestIndex) external override whenNotPaused nonReentrant onlyCoordinator {
        LightningCapacityRequest storage capacityRequest = capacityRequests[capacityRequestIndex];

        require(capacityRequest.plennyReward >= makerCapacityOneTimeReward, "ERR_UNDERPRICED_CAPACITY_REQUEST");
        capacityRequest.plennyReward = capacityRequest.plennyReward.sub(makerCapacityOneTimeReward);
        capacityRequest.status = 2;

        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        uint256 makerOneTimeRewardFee = makerCapacityOneTimeReward.mul(makerRewardFee).div(100).div(100);

        _approve(address(this), makerCapacityOneTimeReward.sub(makerOneTimeRewardFee));
        token.safeTransfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), makerOneTimeRewardFee);
        token.safeTransferFrom(address(this), capacityRequest.makerAddress,
            makerCapacityOneTimeReward.sub(makerOneTimeRewardFee));
    }

    /// @notice Collects reward for a channel opened as a result of a liquidity request.
    /// @param  capacityRequestIndex liquidity request id
    /// @param  channelId channel id
    /// @param  confirmedDate date of opening
    function collectCapacityRequestReward(uint256 capacityRequestIndex, uint256 channelId, uint256 confirmedDate) external override whenNotPaused onlyCoordinator {
        _collectCapacityRequestReward(capacityRequestIndex, channelId, confirmedDate);
    }

    /// @notice Closes a given capacity request whenever its channel has been closed.
    /// @param  capacityRequestIndex liquidity request id
    /// @param  channelId channel id
    /// @param  confirmedDate date of opening
    function closeCapacityRequest(uint256 capacityRequestIndex, uint256 channelId, uint256 confirmedDate) external override whenNotPaused onlyCoordinator {
        (uint256 returningAmountForTaker, address payable taker) = _collectCapacityRequestReward(capacityRequestIndex, channelId, confirmedDate);

        IPlennyStaking staking = contractRegistry.stakingContract();
        _approve(address(staking), returningAmountForTaker);
        staking.increasePlennyBalance(taker, returningAmountForTaker, address(this));

    }

    /// @notice Changes the cancelling request period in blocks. Called by the owner.
    /// @param  amount period in blocks
    function setCancelingRequestPeriod(uint256 amount) external onlyOwner {
        cancelingRequestPeriod = amount;
    }

    /// @notice Changes the taker Fee. Called by the owner
    /// @param  value fee
    function setTakerFee(uint256 value) external onlyOwner {
        takerFee = value;
    }

    /// @notice Gets the ids of liquidity requests for the given maker address.
    /// @param  addr maker's address
    /// @return array of ids
    function getCapacityRequestPerMaker(address addr) external view returns (uint256[] memory){
        return capacityRequestPerMaker[addr];
    }

    /// @notice Gets the ids of liquidity requests for the given taker address.
    /// @param  addr taker's address
    /// @return array of ids
    function getCapacityRequestPerTaker(address addr) external view returns (uint256[] memory){
        return capacityRequestPerTaker[addr];
    }

    /// @notice Keep track of the maker capacity provided.
    /// @param  makerIndex maker index
    /// @param  amount amount to increase/decrease
    /// @param  incrementDecrement true if increased. false if decreased
    function updateMakerProvidingAmount(uint256 makerIndex, uint256 amount, bool incrementDecrement) internal {
        MakerInfo storage maker = makers[makerIndex];
        if (incrementDecrement) {
            maker.makerProvidingAmount = maker.makerProvidingAmount.add(amount);
        } else {
            maker.makerProvidingAmount = maker.makerProvidingAmount.sub(amount);
        }
    }

    /// @notice Collect the reward for the liquidity request provided.
    /// @param  capacityRequestIndex liquidity request id
    /// @param  channelId channel id
    /// @return reservedRewardAmount reward amount reserved for maker
    /// @return taker that has requested the liquidity
    function _collectCapacityRequestReward(uint256 capacityRequestIndex, uint256 channelId, uint256)
            internal returns (uint256 reservedRewardAmount, address payable taker) {
        LightningCapacityRequest storage capacityRequest = capacityRequests[capacityRequestIndex];

        IPlennyDappFactory factory = contractRegistry.factoryContract();

        uint256 _reward = _blockNumber().sub(contractRegistry.coordinatorContract().channelRewardStart(channelId))
            > factory.userChannelRewardPeriod() ?
        capacityRequest.plennyReward.mul(factory.userChannelReward())
        .mul(_blockNumber().sub(contractRegistry.coordinatorContract().channelRewardStart(channelId)))
        .div(factory.userChannelRewardPeriod()).div(10000) : 0;

        if (_reward > capacityRequest.plennyReward) {
            _reward = capacityRequest.plennyReward;
        }

        capacityRequest.plennyReward = capacityRequest.plennyReward.sub(_reward);
        uint256 rewardFee = _reward.mul(makerRewardFee).div(100).div(100);

        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        _approve(address(this), _reward.sub(rewardFee));
        token.safeTransfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), rewardFee);
        token.safeTransferFrom(address(this), capacityRequest.makerAddress, _reward.sub(rewardFee));

        return (capacityRequest.plennyReward, capacityRequest.to);
    }

    /// @notice Approve spending of PL2 token
    /// @param 	addr token owner address
    /// @param 	amount amount to approve
    function _approve(address addr, uint256 amount) internal {
        contractRegistry.plennyTokenContract().safeApprove(addr, amount);
    }

    /// @dev    logs the function calls
    function _logs_() internal {
        emit LogCall(msg.sig, msg.sender, msg.data);
    }

    /// @notice Check that ESDSA signature request is signed correctly by the taker
    /// @param  nodeUrl Lightning node to provide liquidity for
    /// @param  capacity channel capacity in satoshi
    /// @param  makerAddress maker's address
    /// @param  owner taker's address
    /// @param  nonce nonce
    /// @param  signature this request signature as signed by the taker
    function _checkSignature(string memory nodeUrl, uint256 capacity, address payable makerAddress,
        address payable owner, uint256 nonce, bytes memory signature) internal view {
        bytes32 hash = keccak256(abi.encodePacked(nodeUrl, capacity, makerAddress, owner, nonce));
        // bytes32 messageHash = ECDSA.toEthSignedMessageHash(hash);

        // Verify that the message's signer is the owner of the orderignature);
        require(ECDSAUpgradeable.recover(hash, signature) == owner, "ERR_NO_AUTH");

        require(!seenNonces[owner][nonce], "ERR_DUPLICATE");
    }
}

