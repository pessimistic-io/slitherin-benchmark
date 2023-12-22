// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {Clones} from "./Clones.sol";
import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {TypeAndVersion} from "./TypeAndVersion.sol";
import {IRandomProvider} from "./IRandomProvider.sol";
import {Sets} from "./Sets.sol";
import {Withdrawable} from "./Withdrawable.sol";
import {ClassicRafflerVRF} from "./ClassicRafflerVRF.sol";
import {ChainlinkVRFV2Randomiser} from "./ChainlinkVRFV2Randomiser.sol";

/// @title ClassicRafflerVRFFactory
/// @author kevincharm
/// @notice Deploys classic raffles!
contract ClassicRafflerVRFFactory is
    TypeAndVersion,
    Initializable,
    IRandomProvider,
    UUPSUpgradeable,
    OwnableUpgradeable,
    Withdrawable
{
    using Sets for Sets.Set;
    /// @notice Set of deployed rafflers
    Sets.Set private rafflers;
    /// @notice Master copy of ClassicRaffler
    address public rafflerMasterCopy;
    /// @notice RaffleChef
    address public raffleChef;
    /// @notice Randomiser
    address public randomiser;
    /// @notice User nonces
    mapping(address => uint256) public nonces;
    /// @notice Fee for creating a raffle
    uint256 public fee;

    uint256[44] private __ClassicRafflerFactory_gap;

    event RafflerMasterCopyUpdated(address oldRaffler, address newRaffler);
    event RaffleChefUpdated(address oldRaffleChef, address newRaffleChef);
    event RandomiserUpdated(address oldRandomiser, address newRandomiser);
    event RafflerDeployed(address raffler);
    event FeeChanged(uint256 oldFee, uint256 newFee);
    event FeePaid(uint256 fee);

    constructor() {
        _disableInitializers();
    }

    function init(
        uint256 fee_,
        address rafflerMasterCopy_,
        address raffleChef_,
        address randomiser_
    ) public initializer {
        __Ownable_init();
        rafflers.init();
        fee = fee_;
        rafflerMasterCopy = rafflerMasterCopy_;
        raffleChef = raffleChef_;
        randomiser = randomiser_;
    }

    function typeAndVersion()
        external
        pure
        virtual
        override
        returns (string memory)
    {
        return "ClassicRafflerVRFFactory 1.0.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _authoriseWithdrawal() internal override onlyOwner {}

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function setFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = fee;
        fee = newFee;
        emit FeeChanged(oldFee, newFee);
    }

    function setRafflerMasterCopy(address newRafflerMasterCopy)
        external
        onlyOwner
    {
        address oldMasterCopy = rafflerMasterCopy;
        rafflerMasterCopy = newRafflerMasterCopy;
        emit RafflerMasterCopyUpdated(oldMasterCopy, newRafflerMasterCopy);
    }

    function setRaffleChef(address newRaffleChef) external onlyOwner {
        address oldRaffleChef = raffleChef;
        raffleChef = newRaffleChef;
        emit RaffleChefUpdated(oldRaffleChef, newRaffleChef);
    }

    function setRandomiser(address newRandomiser) external onlyOwner {
        address oldRandomiser = randomiser;
        randomiser = newRandomiser;
        emit RandomiserUpdated(oldRandomiser, newRandomiser);
    }

    /// @notice Get a random number from VRF
    function getRandomNumber(uint16 minBlocksToWait)
        external
        returns (uint256)
    {
        require(isRaffler(msg.sender), "Caller must be a raffler");
        return
            ChainlinkVRFV2Randomiser(randomiser).getRandomNumber(
                msg.sender,
                minBlocksToWait
            );
    }

    /// @notice Create a raffler!
    function createRaffle(
        bytes32 participantsMerkleRoot_,
        uint256 nParticipants_,
        uint256 nWinners_,
        string calldata provenance_,
        uint16 minBlocksToWait
    ) external payable returns (address) {
        require(msg.value >= fee, "Insufficient fee payment");
        emit FeePaid(msg.value);

        address rafflerProxy = Clones.clone(rafflerMasterCopy);
        rafflers.add(rafflerProxy);
        ClassicRafflerVRF(rafflerProxy).init(
            raffleChef,
            randomiser,
            participantsMerkleRoot_,
            nParticipants_,
            nWinners_,
            provenance_,
            minBlocksToWait
        );
        ClassicRafflerVRF(rafflerProxy).transferOwnership(msg.sender);
        emit RafflerDeployed(rafflerProxy);
        return rafflerProxy;
    }

    /// @notice Returns true if `raffler` was deployed by this factory
    /// @param raffler Contract address of deployed raffler
    function isRaffler(address raffler) public view returns (bool) {
        return rafflers.has(raffler);
    }

    /// @notice Fetch paginated list of deployed rafflers
    /// @param startFrom Raffle address to start fetching from
    /// @param pageSize Maximum size of returned list
    function getRafflersPaginated(address startFrom, uint256 pageSize)
        external
        view
        returns (address[] memory out, address next)
    {
        out = new address[](pageSize);

        address element = rafflers.ll[startFrom];
        uint256 i;
        if (startFrom > address(0x1) && element != address(0)) {
            out[i] = startFrom;
            unchecked {
                ++i;
            }
        }
        for (
            ;
            i < pageSize && element != address(0) && element != address(0x1);
            ++i
        ) {
            out[i] = element;
            element = rafflers.prev(element);
        }
        assembly {
            // Change size of output arrays to number of fetched addresses
            mstore(out, i)
        }
        return (out, element);
    }
}

