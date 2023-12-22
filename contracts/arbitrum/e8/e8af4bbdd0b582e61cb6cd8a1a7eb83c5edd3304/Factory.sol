// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./NFT.sol";
import "./INFT.sol";

/// @title A Takalabs Factory
/// @author Kevin Tan
/// @notice You can manage this contract for events.
/// @dev All function calls are currently implemented without side effects
contract Factory is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    struct Event {
        string name;
        string symbol;
        string provenanceHash;
        string baseURI;
        uint256 eventId;
        uint256 mintStartTime;
        uint256 mintEndTime;
        uint256 maxMintAmount;
        address nftContract;
        bool isHidden;
    }

    // event id => event address
    mapping(uint256 => Event) private events;
    uint256 public totalEventCount;

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
    }

    /// @notice Owner can only create event.
    /// @param name the event name
    /// @param symbol the event symbol
    /// @param mintStartTime It's the designated time when minting of NFTs in a contract can commence.
    /// @param mintEndTime signifies the cutoff time for creating new NFTs within a contract.
    /// @param maxMintAmount limit on the total number of NFTs
    /// @param provenanceHash provenanceHash
    /// @param baseURI base URI
    function createEvent(
        string memory name,
        string memory symbol,
        uint256 mintStartTime,
        uint256 mintEndTime,
        uint256 maxMintAmount,
        string memory provenanceHash,
        string memory baseURI
    ) external onlyOwner {
        Event storage newEvent = events[totalEventCount];
        newEvent.name = name;
        newEvent.symbol = symbol;
        newEvent.mintStartTime = mintStartTime;
        newEvent.mintEndTime = mintEndTime;
        newEvent.maxMintAmount = maxMintAmount;
        newEvent.provenanceHash = provenanceHash;
        newEvent.baseURI = baseURI;
        newEvent.eventId = totalEventCount++;
        // Deploy a new NFT contract for the event
        NFT nft = new NFT(name, symbol, provenanceHash, baseURI, mintStartTime, mintEndTime, maxMintAmount);

        // Store the address of the deployed NFT contract
        newEvent.nftContract = address(nft);
    }

    /// @notice Owner can only add Legacy event.
    /// @param name the event name
    /// @param symbol the event symbol
    /// @param mintStartTime It's the designated time when minting of NFTs in a contract can commence.
    /// @param mintEndTime signifies the cutoff time for creating new NFTs within a contract.
    /// @param maxMintAmount limit on the total number of NFTs
    /// @param provenanceHash provenanceHash
    /// @param baseURI base URI
    function addLegacyEvent(
        string memory name,
        string memory symbol,
        uint256 mintStartTime,
        uint256 mintEndTime,
        uint256 maxMintAmount,
        string memory provenanceHash,
        string memory baseURI,
        address nftContract
    ) external onlyOwner {
        Event storage newEvent = events[totalEventCount];
        newEvent.name = name;
        newEvent.symbol = symbol;
        newEvent.mintStartTime = mintStartTime;
        newEvent.mintEndTime = mintEndTime;
        newEvent.maxMintAmount = maxMintAmount;
        newEvent.provenanceHash = provenanceHash;
        newEvent.baseURI = baseURI;
        newEvent.eventId = totalEventCount++;
        newEvent.nftContract = address(nftContract);
    }

    /// @notice Owner can only destroy event.
    /// @param eventId the event id
    function destroyEvent(uint256 eventId) external onlyOwner {
        address nftContract = events[eventId].nftContract;
        delete events[eventId];
        INFT(nftContract).destroy();
    }

    /// @notice Owner can only mint.
    /// @param eventId the event id
    /// @param tokenId the ERC721 token id
    /// @param toAddress the user address
    /// @return result status
    function mintTo(uint256 eventId, uint256 tokenId, address toAddress) external onlyOwner returns (uint256) {
        uint256 newTokenId = INFT(events[eventId].nftContract).mintNFT(tokenId, toAddress);
        return newTokenId;
    }

    /// @notice Owner can only burn.
    /// @param eventId the event id
    /// @param tokenId the ERC721 token id
    function burn(uint256 eventId, uint256 tokenId) external onlyOwner returns (bool result) {
        INFT(events[eventId].nftContract).burn(tokenId);
        return true;
    }

    /// @notice Owner can only update baseURI.
    /// @param eventId the event id
    /// @param newBaseURI the ERC721 base URI
    function updateURI(uint256 eventId, string memory newBaseURI) external onlyOwner {
        Event storage currentEvent = events[eventId];
        currentEvent.baseURI = newBaseURI;
        INFT(events[eventId].nftContract).setBaseURI(newBaseURI);
    }

    /// @notice Owner can only update mint max amount.
    /// @param eventId the event id
    /// @param maxMintAmount the mint end time
    function updateMaxMintAmount(uint256 eventId, uint256 maxMintAmount) external onlyOwner {
        Event storage currentEvent = events[eventId];
        currentEvent.maxMintAmount = maxMintAmount;
        INFT(events[eventId].nftContract).updateMaxMintAmount(maxMintAmount);
    }

    /// @notice Owner can only update mint end time.
    /// @param eventId the event id
    /// @param mintEndTime the mint end time
    function updateMintEndTime(uint256 eventId, uint256 mintEndTime) external onlyOwner {
        Event storage currentEvent = events[eventId];
        currentEvent.mintEndTime = mintEndTime;
        INFT(events[eventId].nftContract).updateMintEndTime(mintEndTime);
    }

    /// @notice Owner can only set the hidden option for the event.
    /// @param eventId the event id
    function setHidden(uint256 eventId, bool isHidden) external onlyOwner {
        Event storage currentEvent = events[eventId];
        currentEvent.isHidden = isHidden;
    }

    /// @notice can get events.
    function getAllEvents() external view returns (Event[] memory eventList) {
        eventList = new Event[](totalEventCount);
        for (uint256 i = 0; i < totalEventCount; i++) {
            eventList[i] = events[i];
        }
    }

    /// @notice can get the event by id.
    function getEventById(uint256 id) external view returns (Event memory event_) {
        event_ = events[id];
        return event_;
    }

    /// @notice can get on going events.
    function getOngoingEvents() external view returns (Event[] memory eventList) {
        uint256 currentTime = block.timestamp;
        uint256 count = 0;
        eventList = new Event[](totalEventCount);

        for (uint256 i = 0; i < totalEventCount; i++) {
            if (events[i].mintStartTime < currentTime && events[i].mintEndTime > currentTime) {
                eventList[count++] = events[i];
            }
        }

        assembly {
            mstore(eventList, count) // Set the actual length of the dynamic array
        }
    }

    /// @notice can get upcoming events.
    function getUpcomingEvents() external view returns (Event[] memory eventList) {
        uint256 currentTime = block.timestamp;
        uint256 count = 0;
        eventList = new Event[](totalEventCount);
        for (uint256 i = 0; i < totalEventCount; i++) {
            if (events[i].mintStartTime > currentTime) {
                eventList[count++] = events[i];
            }
        }
        assembly {
            mstore(eventList, count) // Set the actual length of the dynamic array
        }
    }

    /// @notice can get ended events.
    function getEndedEvents() external view returns (Event[] memory eventList) {
        uint256 currentTime = block.timestamp;
        uint256 count = 0;
        eventList = new Event[](totalEventCount);
        for (uint256 i = 0; i < totalEventCount; i++) {
            if (events[i].mintEndTime < currentTime) {
                eventList[count++] = events[i];
            }
        }
        assembly {
            mstore(eventList, count) // Set the actual length of the dynamic array
        }
    }

    /** @dev the function to authorize new versions of the marketplace.
     * @param newImplementation is the address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

