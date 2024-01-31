// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IDistributooor} from "./IDistributooor.sol";
import {IDistributooorFactory} from "./IDistributooorFactory.sol";
import {TypeAndVersion} from "./TypeAndVersion.sol";
import {Clones} from "./Clones.sol";
import {Sets} from "./Sets.sol";
import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ICollectooorFactory} from "./CollectooorFactory.sol";
import {CrossChainHub} from "./CrossChainHub.sol";
import {Withdrawable} from "./Withdrawable.sol";
import {Distributooor} from "./Distributooor.sol";
import {ChainlinkRandomiser} from "./ChainlinkRandomiser.sol";

contract DistributooorFactory is
    IDistributooorFactory,
    TypeAndVersion,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    CrossChainHub,
    Withdrawable
{
    using Sets for Sets.Set;

    Sets.Set private consumers;

    address public raffleChef;

    address public distributooorMasterCopy;

    address public chainlinkRandomiser;

    uint256[46] private __DistributooorFactory_gap;

    constructor() CrossChainHub(bytes("")) {
        _disableInitializers();
    }

    function init(
        address raffleChef_,
        address distributooorMasterCopy_,
        address chainlinkRandomiser_,
        address celerMessageBus_,
        uint256 maxCrossChainFee_
    ) public initializer {
        __Ownable_init();
        __CrossChainHub_init(celerMessageBus_, maxCrossChainFee_);

        raffleChef = raffleChef_;
        distributooorMasterCopy = distributooorMasterCopy_;
        chainlinkRandomiser = chainlinkRandomiser_;

        consumers.init();
    }

    fallback() external payable {}

    receive() external payable {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _authoriseWithdrawal() internal override onlyOwner {}

    function typeAndVersion()
        external
        pure
        virtual
        override(TypeAndVersion, CrossChainHub)
        returns (string memory)
    {
        return "DistributooorFactory 1.0.0";
    }

    function setDistributooorMasterCopy(
        address distributooorMasterCopy_
    ) external onlyOwner {
        address oldMasterCopy = distributooorMasterCopy;
        distributooorMasterCopy = distributooorMasterCopy_;
        emit DistributooorMasterCopyUpdated(
            oldMasterCopy,
            distributooorMasterCopy_
        );
    }

    /// @notice Deploy new Raffle consumer
    function createDistributooor(
        uint256 activationTimestamp,
        uint256 prizeExpiryTimestamp
    ) external onlyOwner returns (address) {
        address distributooorProxy = Clones.clone(distributooorMasterCopy);
        // Record as known consumer
        consumers.add(distributooorProxy);
        Distributooor(distributooorProxy).init(
            msg.sender,
            raffleChef,
            chainlinkRandomiser,
            activationTimestamp,
            prizeExpiryTimestamp
        );
        ChainlinkRandomiser(chainlinkRandomiser).authorise(distributooorProxy);
        emit DistributooorDeployed(distributooorProxy);
        return distributooorProxy;
    }

    function requestMerkleRoot(
        uint256 chainId,
        address collectooorFactory,
        address collectooor
    ) external {
        if (!isKnownCrossChainHub(chainId, collectooorFactory)) {
            revert UnknownCrossChainHub(chainId, collectooorFactory);
        }

        address consumer = msg.sender;
        // Only allow known consumers to request
        if (!consumers.has(consumer)) {
            revert UnknownConsumer(consumer);
        }

        _sendCrossChainMessage(
            chainId,
            collectooorFactory,
            uint8(ICollectooorFactory.CrossChainAction.RequestMerkleRoot),
            abi.encode(consumer, collectooor)
        );
    }

    function _executeValidatedMessage(
        address /** sender */,
        uint64 srcChainId,
        bytes calldata message,
        address /** executor */
    ) internal virtual override {
        (uint8 rawAction, bytes memory data) = abi.decode(
            message,
            (uint8, bytes)
        );
        CrossChainAction action = CrossChainAction(rawAction);
        if (action == CrossChainAction.ReceiveMerkleRoot) {
            (
                address requester,
                address collectooor,
                uint256 blockNumber,
                bytes32 merkleRoot,
                uint256 nodeCount
            ) = abi.decode(data, (address, address, uint256, bytes32, uint256));
            address consumer = requester;
            IDistributooor(consumer).receiveParticipantsMerkleRoot(
                srcChainId,
                collectooor,
                blockNumber,
                merkleRoot,
                nodeCount
            );
        }
    }

    function setMessageBus(address messageBus) external onlyOwner {
        _setMessageBus(messageBus);
    }

    function setMaxCrossChainFee(uint256 maxFee) external onlyOwner {
        _setMaxCrossChainFee(maxFee);
    }

    function setKnownCrossChainHub(
        uint256 chainId,
        address crossChainHub,
        bool isKnown
    ) external onlyOwner {
        _setKnownCrossChainHub(chainId, crossChainHub, isKnown);
    }

    function setRaffleChef(address newRaffleChef) external onlyOwner {
        address oldRaffleChef = raffleChef;
        raffleChef = newRaffleChef;
        emit RaffleChefUpdated(oldRaffleChef, newRaffleChef);
    }
}

