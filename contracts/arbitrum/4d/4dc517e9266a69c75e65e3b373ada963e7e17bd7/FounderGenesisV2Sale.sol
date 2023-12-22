// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IBattleflyGame.sol";
import { MerkleProof } from "./MerkleProof.sol";


contract FounderGenesisV2Sale is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    mapping(address => bool) private adminAccess;
    IBattleflyGame Game;
    uint256 FounderGenesisV2TokenType;
    uint256 public totalSellAmount;
    uint256 public soldAmount;
    uint256 public timeStart;
    uint256 public price;
    address public fundAddress;
    
    uint256 public discountPrice;
    uint256 public discountSoldAmount;
    uint256 public discountTimeStart;
    bytes32 public merkleRoot;

    event MintFounderGenesisV2(address indexed to, uint256 price, uint256 indexed specialNFTType, uint256 tokenId, address fundAddress, bytes32 indexed ticket);


    function initialize(address battleflyGameContractAddress) public initializer {
        __Ownable_init();
        Game = IBattleflyGame(battleflyGameContractAddress);
        FounderGenesisV2TokenType = 151;
        soldAmount = 0;
        totalSellAmount = 1000;
        timeStart = 0;
        price = 2*10**16;
        fundAddress = 0xFf4a63aE43BF574e522F9D8bF9Ad1B94367836b0;
    }
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }
    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdminAccess {
        merkleRoot = _merkleRoot;
    }
    function mintFounderGenesisV2WithDiscount(uint256 amount, bytes32 ticket, bytes32[] calldata proof) external payable {
        address to = _msgSender();
        require(discountSoldAmount + soldAmount + amount <= totalSellAmount, "Sold out");
        require(msg.value == discountPrice.mul(amount), "Not enough ETH");
        require(block.timestamp >= discountTimeStart, "Not time yet");
        bytes32 leaf = keccak256(abi.encodePacked(ticket));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        require(isValidLeaf, "Not in merkle");
        uint256[] memory tokenIds = Game.mintSpecialNFTs(to, FounderGenesisV2TokenType, amount);
        discountSoldAmount += amount;
        if(fundAddress != address(0)) {
            (bool success, ) = payable(fundAddress).call{value: discountPrice.mul(amount)}("");
            require(success, "Failed to send Ether");
        }
        for(uint256 i = 0; i < amount; i++) {
            emit MintFounderGenesisV2(to, discountPrice, FounderGenesisV2TokenType, tokenIds[i], fundAddress, ticket);
        }
    }
    function setDiscountSaleInfo( uint256 _timeStart, uint256 _price) external onlyAdminAccess {
        discountTimeStart = _timeStart;
        discountPrice = _price;
    }
    function setSaleInfo(uint256 _totalSellAmount, uint256 _timeStart, uint256 _price) external onlyAdminAccess {
        totalSellAmount = _totalSellAmount;
        timeStart = _timeStart;
        price = _price;
    }
    function setfundAddress(address _fundAddress) external onlyAdminAccess {
        fundAddress = _fundAddress;
    }
    function mintFounderGenesisV2(uint256 amount) external payable {
        address to = _msgSender();
        require(discountSoldAmount + soldAmount + amount <= totalSellAmount, "Sold out");
        require(msg.value >= price.mul(amount), "Not enough ETH");
        require(block.timestamp >= timeStart, "Not time yet");
        uint256[] memory tokenIds = Game.mintSpecialNFTs(to, FounderGenesisV2TokenType, amount);
        soldAmount += amount;
        if(fundAddress != address(0)) {
            (bool success, ) = payable(fundAddress).call{value: price.mul(amount)}("");
            require(success, "Failed to send Ether");
        }
        for(uint256 i = 0; i < amount; i++) {
            emit MintFounderGenesisV2(to, price, FounderGenesisV2TokenType, tokenIds[i], fundAddress, "");
        }
    }
    function withdraw(address payable to, uint256 amount) external onlyAdminAccess {
        require(amount <= address(this).balance, "Not enough balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Failed to send Ether");
    }
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}
