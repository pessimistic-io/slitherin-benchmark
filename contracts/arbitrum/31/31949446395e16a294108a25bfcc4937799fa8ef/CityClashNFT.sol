//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./CityClashTypes.sol";
import { Base64 } from "./Base64.sol";

contract CityClashNFT is ERC721, Ownable, ReentrancyGuard {
    mapping(uint256 => CityClashTypes.City) public idToCities;
    mapping(address => uint8) public addressToFaction;
    mapping(string => CityClashTypes.CountryScore) public countryToScore;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _reservedTokenIds;

    uint256 public constant MAX_CITIES = 3000;
    uint256 public citiesWaveMax = 1000; //local max that can be updated
    uint256 public constant FOUNDERS_RESERVE_AMOUNT = 50;
    uint256 private constant MAX_PUBLIC_CITIES = MAX_CITIES - FOUNDERS_RESERVE_AMOUNT;
    uint256 private constant MAX_PER_ADDRESS = 30;

    uint256 private constant MAX_PER_EARLY_ACCESS_ADDRESS = 3;

    uint256 public earlyAccessStartTimestamp;
    uint256 public publicSaleStartTimestamp;
    uint256 public mintPrice = 0.07 ether;
    
    string placeHolderImage = "https://gateway.pinata.cloud/ipfs/Qmes6ARu9uVgs6FKtJovEcxwK2uTMerZwd7zhsJSxAygdZ";
    string baseUrl = "";
    address upgradeCityContractAddress;

    mapping(address => bool) public isOnEarlyAccessList;
    mapping(address => uint256) public earlyAccessMintedCounts;
    mapping(address => uint256) private founderMintCountsRemaining;
    mapping(address => bool) public isAddressAbleToUpgrade;

    constructor() ERC721("City Clash", "City Clash is a P2E, social strategy game where 3 factions compete by buying and selling NFTs based on real world cities. The game is built entirely on-chain, and is fully functional at mint time!") {
        // console.log("Deploying CityClash");
    }

    modifier whenPublicSaleActive() {
        require(isPublicSaleOpen(), "Public sale not open");
        _;
    }

    modifier whenEarlyAccessActive() {
        require(isEarlyAccessOpen(), "Early access not open");
        _;
    }

    function mintPublicSale(uint256 _count) external payable nonReentrant whenPublicSaleActive returns (uint256, uint256) {
        require(_count > 0 && _count <= MAX_PER_ADDRESS, "Invalid City count");
        require(_tokenIds.current() + _count <= MAX_PUBLIC_CITIES, "All Cities have been minted");
        require(totalSupply() + _count <= citiesWaveMax, "Current mint wave has been minted");
        require(_count * mintPrice == msg.value, "Incorrect amount of ether sent");

        uint256 firstMintedId = _tokenIds.current() + 1;

        for (uint256 i = 0; i < _count; i++) {
            _tokenIds.increment();
            mint(_tokenIds.current());
        }

        return (firstMintedId, _count);
    }

    function mintEarlyAccess(uint256 _count) external payable nonReentrant whenEarlyAccessActive returns (uint256, uint256) {
        require(_count != 0, "Invalid City count");
        require(isOnEarlyAccessList[msg.sender], "Address not on Early Access list");
        require(_tokenIds.current() + _count <= MAX_PUBLIC_CITIES, "All Cities have been minted");
        require(totalSupply() + _count <= citiesWaveMax, "Current mint wave has been minted");
        require(_count * mintPrice == msg.value, "Incorrect amount of ether sent");

        uint256 userMintedAmount = earlyAccessMintedCounts[msg.sender] + _count;
        require(userMintedAmount <= MAX_PER_EARLY_ACCESS_ADDRESS, "Max Early Access count per address exceeded");

        uint256 firstMintedId = _tokenIds.current() + 1;
        for (uint256 i = 0; i < _count; i++) {
            _tokenIds.increment();
            mint(_tokenIds.current());
        }
        earlyAccessMintedCounts[msg.sender] = userMintedAmount;
        return (firstMintedId, _count);
    }

    function allocateFounderMint(address _addr, uint256 _count) public onlyOwner nonReentrant {
        founderMintCountsRemaining[_addr] = _count;
    }

    function founderMint(uint256 _count) public nonReentrant returns (uint256, uint256) {
        require(_count > 0 && _count <= MAX_PER_ADDRESS, "Invalid City count");
        require(_reservedTokenIds.current() + _count <= FOUNDERS_RESERVE_AMOUNT, "All reserved Cities have been minted");
        require(founderMintCountsRemaining[msg.sender] >= _count, "You cannot mint this many reserved Cities");

        uint256 firstMintedId = MAX_PUBLIC_CITIES + _tokenIds.current() + 1;
        for (uint256 i = 0; i < _count; i++) {
            _reservedTokenIds.increment();
            mint(MAX_PUBLIC_CITIES + _reservedTokenIds.current());
        }
        founderMintCountsRemaining[msg.sender] -= _count;
        return (firstMintedId, _count);
    }

    function getAddressFaction(address _a) public view returns (uint8) {
        if(addressToFaction[_a] != 0) {
            return addressToFaction[_a];
        }
        uint num = uint(keccak256(abi.encodePacked(_a)));
        return uint8(num % 3) + 1;  //mod by the number of factions
    }

    function mint(uint256 _tokenId) internal {
        _safeMint(msg.sender, _tokenId);
    }

    function idToCitiesFunc(uint256 _id) external view returns (CityClashTypes.City memory) {
        return idToCities[_id];
    }

    function getRemainingEarlyAccessMints(address _addr) public view returns (uint256) {
        if (!isOnEarlyAccessList[_addr]) {
            return 0;
        }
        return MAX_PER_EARLY_ACCESS_ADDRESS - earlyAccessMintedCounts[_addr];
    }

    function getRemainingFounderMints(address _addr) public view returns (uint256) {
        return founderMintCountsRemaining[_addr];
    }

    function isPublicSaleOpen() public view returns (bool) {
        return block.timestamp >= publicSaleStartTimestamp && publicSaleStartTimestamp != 0;
    }

    function isEarlyAccessOpen() public view returns (bool) {
        return !isPublicSaleOpen() && block.timestamp >= earlyAccessStartTimestamp && earlyAccessStartTimestamp != 0;
    }

    function addToEarlyAccessList(address[] memory _toEarlyAccessList) external onlyOwner {
        for (uint256 i = 0; i < _toEarlyAccessList.length; i++) {
            isOnEarlyAccessList[_toEarlyAccessList[i]] = true;
        }
    }

    function addToFaction(CityClashTypes.AddressToFaction[] memory _toFactions) external onlyOwner {
        for (uint256 i = 0; i < _toFactions.length; i++) {
            addressToFaction[_toFactions[i].a] = _toFactions[i].faction;
        }
    }

    function setPublicSaleTimestamp(uint256 _timestamp) external onlyOwner {
        publicSaleStartTimestamp = _timestamp;
    }

    function setEarlyAccessTimestamp(uint256 _timestamp) external onlyOwner {
        earlyAccessStartTimestamp = _timestamp;
    }

    function setMintPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
    }

    function setCitiesWaveMax(uint256 _max) external onlyOwner {
        citiesWaveMax = _max;
    }

    function setPlaceHolderImage(string calldata _newPlaceHolder) external onlyOwner {
        placeHolderImage = _newPlaceHolder;
    }

    function getPlaceHolderImage() public view returns (string memory) {
        return placeHolderImage;
    }

    function setAddressAbleToUpgrade(address _address, bool _isAble) external onlyOwner {
        isAddressAbleToUpgrade[_address] = _isAble;
    }

    function getisAddressAbleToUpgrade(address _address) public view returns (bool) {
        return isAddressAbleToUpgrade[_address];
    }

    function setBaseUrl(string calldata _newBaseUrl) external onlyOwner {
        baseUrl = _newBaseUrl;
    }

    function getBaseUrl() public view returns (string memory) {
        return baseUrl;
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current() + _reservedTokenIds.current();
    }

    function getTokenIds() public view returns (uint256) {
        return _tokenIds.current();
    }

    function getReservedTokenIds() public view returns (uint256) {
        return _reservedTokenIds.current();
    }
}
