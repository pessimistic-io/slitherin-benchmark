// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ReentrancyGuard.sol";
import "./ERC721Holder.sol";
import "./ICitizen.sol";
import "./IAddToAllowList.sol";
import "./IAddToPacksAllowList.sol";
import "./ILandDistributor.sol";
import "./BoxTypes.sol";

/// @dev Farmland - box Smart Contract
contract Boxes is ReentrancyGuard, ERC721Holder, BoxTypes {

// CONSTRUCTOR

    constructor (
            address citizensAddress,
            address landDistributorAddress,
            address packsAddress,
            address mintMercenariesAddress
        )
        {
            require(citizensAddress != address(0), "Invalid Citizens Contract address");
            require(landDistributorAddress != address(0), "Invalid Land Distributor Contract address");
            require(packsAddress != address(0), "Invalid Packs Contract address");
            require(mintMercenariesAddress != address(0), "Invalid Mint Mercenaries Contract address");
            landDistributor = ILandDistributor(landDistributorAddress);
            citizens = ICitizen(citizensAddress);
            packs = IAddToPacksAllowList(packsAddress);
            mintMercenaries = IAddToAllowList(mintMercenariesAddress);
        }

// STATE VARIABLES

    /// @dev The Citizens contract
    ICitizen internal immutable citizens;

    /// @dev The Packs contract
    IAddToPacksAllowList internal immutable packs;

    /// @dev The Mint Mercenaries contract
    IAddToAllowList internal immutable mintMercenaries;

    /// @dev This is the Land Distributor contract
    ILandDistributor internal immutable landDistributor;

// EVENTS

    event BoxesMinted(address indexed account, uint256 boxesPrice, uint256 amountOfLand, uint256 packId, uint256 noOfPacks, uint256 noOfItems, uint256 noOfMercenaries);
    event SetPrice(address indexed sender, uint256 newPrice, bytes indicator);
    event SetLandAmount(address indexed sender, uint256 newPrice);
    event SetPackId(address indexed sender, uint256 packId);
    event SetNumberOfPacks(address indexed sender, uint256 noOfpacks);
    event SetNumberOfItemsInPack(address indexed sender, uint256 noOfItems);
    event SetNumberOfMercenaries(address indexed sender, uint256 noOfMercenaries);

// FUNCTIONS

    /// @dev Mint a box
    function mintBoxes(uint256 boxID, uint256 amount)
        external
        payable
        nonReentrant
        onlyWhenBoxEnabled(boxID)
    {
        // Set some variables
        Box memory box = boxes[boxID];
        uint256 totalPrice = box.boxPrice * amount;
        uint256 totalLand = box.amountOfLand * amount;
        uint256 numberOfMercenaries = box.numberOfMercenaries;
        uint256 numberOfPacks = box.numberOfPacks;
        uint256 numberOfCitizens = box.numberOfCitizens;

        // Check the correct ETH is sent
        require( msg.value >= totalPrice,"Boxes: ETH sent is not correct" );
        
        // Write an event
        emit BoxesMinted(_msgSender(), totalPrice, totalLand, box.packID, box.numberOfPacks, box.numberOfItemsInPack, box.numberOfMercenaries);

        // Send the Land
        landDistributor.issueLand(_msgSender(), totalLand);
        
        // For the amount of boxes requested
        for(uint256 i=0; i < amount;){
            // Add to the mercenary allowlists
            for(uint256 m=0; m < numberOfMercenaries;){
                mintMercenaries.addToAllowlist(singletonAddress(_msgSender()));
                unchecked { ++m; }
            }
            // Add to the packs allowlists
            for(uint256 p=0; p < numberOfPacks;){
                packs.addToAllowlist(singletonUint256(box.packID), singletonAddress(_msgSender()), singletonUint256(box.numberOfItemsInPack));
                unchecked { ++p; }
            }
            // Mint the required number of Citizen into this contract temporarily & then send to new owner
            for(uint256 c=0; c < numberOfCitizens;){
                citizens.mintCollectible{value: box.citizenPrice}(1);
                uint256 tokenID = citizens.totalSupply()-1;
                citizens.safeTransferFrom(address(this), _msgSender(), tokenID);
                unchecked { ++c; }
            }
            unchecked { ++i; }
        }
    }

    /// @dev Return a single address in an array
    function singletonAddress(address value)
        internal
        pure
        returns (address[] memory)
    {
        // Instantiate an array, assign the value to the first element of the array & then return the array
        address[] memory account = new address[](1);
        account[0] = value;
        return account;
    }

    /// @dev Return a single uint256 in an array
    function singletonUint256(uint256 value)
        internal
        pure
        returns (uint256[] memory)
    {
        // Instantiate an array, assign the value to the first element of the array & then return the array
        uint256[] memory number = new uint256[](1);
        number[0] = value;
        return number;
    }

    /// @dev Withdraw ETH
    function withdrawAll()
        external
        payable
        nonReentrant
        onlyOwner
    {
        (bool sent,) = payable(_msgSender()).call{value: address(this).balance}("");
        require(sent, "Box: Failed to retrieve Ether");
    }

    /// @dev Withdraw Citizen NFT Token
    function withdrawCitizen(uint256 tokenID)
        external
        nonReentrant
        onlyOwner
    {
        require(citizens.balanceOf(address(this))>0, "Box: No Citizens to retrieve");
        citizens.safeTransferFrom(address(this), _msgSender(), tokenID);
    }

    fallback() external payable { }
    receive() external payable { }

}
