// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Counters.sol";

/*
   ___  ____
  / _ )/ __/
 / _  / _/  
/____/___/  

*/

contract SacredCreatures is ERC721Enumerable, ReentrancyGuard, Ownable  {
    using Counters for Counters.Counter;
    Counters.Counter _tokenIds;


    uint256 public price = 50000000000000000; //0.05 ETH
    uint256 public discountPerUnit = 5000000000000000; // 0.005 ETH 
    uint256 public changeNamePrice = 10000000000000000; // 0.01 ETH 
    uint256 public priceMintWithName = 75000000000000000; //0.075 ETH
    bool public paused = false; // Enable disable
    uint256 public maxTokens = 7000;
    uint256 public maxLevel = 100;


    struct creature {
        string nickname;
        uint256 defense;
        uint256 attack;
        uint256 soul;
        uint256 wisdom;
        string rarity;
        string family;
    }

    struct range {
        uint256 defenseMin;
        uint256 defenseMax;
        uint256 attackMin;
        uint256 attackMax;
        uint256 soulMin;
        uint256 soulMax;
        uint256 wisdomMin;
        uint256 wisdomMax;
    }


    mapping(uint256 => creature) public creatures;
    mapping(string => range) public rangesByFamily;

    
    event CreatureCreated(
        string name,
        uint256 tokenId,
        creature creatureCreated
    );

    event NameChanged(uint256 tokenId, string name);

    constructor() ERC721("SacredCreatures", "SacredCreatures") Ownable() {
        rangesByFamily["god"].defenseMin = 10;
        rangesByFamily["god"].defenseMax = 30;
        rangesByFamily["god"].attackMin = 10;
        rangesByFamily["god"].attackMax = 30;
        rangesByFamily["god"].soulMin = 40;
        rangesByFamily["god"].soulMax = 70;
        rangesByFamily["god"].wisdomMin = 50;
        rangesByFamily["god"].wisdomMax = 70;

        rangesByFamily["reincarnate"].defenseMin = 20;
        rangesByFamily["reincarnate"].defenseMax = 50;
        rangesByFamily["reincarnate"].attackMin = 20;
        rangesByFamily["reincarnate"].attackMax = 50;
        rangesByFamily["reincarnate"].soulMin = 30;
        rangesByFamily["reincarnate"].soulMax = 60;
        rangesByFamily["reincarnate"].wisdomMin = 40;
        rangesByFamily["reincarnate"].wisdomMax = 70;

        rangesByFamily["demon"].defenseMin = 15;
        rangesByFamily["demon"].defenseMax = 40;
        rangesByFamily["demon"].attackMin = 30;
        rangesByFamily["demon"].attackMax = 60;
        rangesByFamily["demon"].soulMin = 20;
        rangesByFamily["demon"].soulMax = 45;
        rangesByFamily["demon"].wisdomMin = 15;
        rangesByFamily["demon"].wisdomMax = 60;
        
        rangesByFamily["ai"].defenseMin = 20;
        rangesByFamily["ai"].defenseMax = 80;
        rangesByFamily["ai"].attackMin = 40;
        rangesByFamily["ai"].attackMax = 60;
        rangesByFamily["ai"].soulMin = 10;
        rangesByFamily["ai"].soulMax = 20;
        rangesByFamily["ai"].wisdomMin = 20;
        rangesByFamily["ai"].wisdomMax = 50;

        rangesByFamily["chosenOne"].defenseMin = 25;
        rangesByFamily["chosenOne"].defenseMax = 50;
        rangesByFamily["chosenOne"].attackMin = 30;
        rangesByFamily["chosenOne"].attackMax = 50;
        rangesByFamily["chosenOne"].soulMin = 20;
        rangesByFamily["chosenOne"].soulMax = 40;
        rangesByFamily["chosenOne"].wisdomMin = 20;
        rangesByFamily["chosenOne"].wisdomMax = 50;

        rangesByFamily["wizard"].defenseMin = 40;
        rangesByFamily["wizard"].defenseMax = 70;
        rangesByFamily["wizard"].attackMin = 20;
        rangesByFamily["wizard"].attackMax = 40;
        rangesByFamily["wizard"].soulMin = 40;
        rangesByFamily["wizard"].soulMax = 50;
        rangesByFamily["wizard"].wisdomMin = 50;
        rangesByFamily["wizard"].wisdomMax = 70;

        rangesByFamily["savage"].defenseMin = 30;
        rangesByFamily["savage"].defenseMax = 80;
        rangesByFamily["savage"].attackMin = 40;
        rangesByFamily["savage"].attackMax = 70;
        rangesByFamily["savage"].soulMin = 20;
        rangesByFamily["savage"].soulMax = 30;
        rangesByFamily["savage"].wisdomMin = 10;
        rangesByFamily["savage"].wisdomMax = 30;
    }

    // Pause or resume minting
    function flipPause() public onlyOwner {
        paused = !paused;
    }

    // Change the public price of the token
    function setPublicPrice(uint256 newPrice) public onlyOwner {
        price = newPrice;
    }

    function setPriceMintWithName(uint256 newPrice) public onlyOwner {
        priceMintWithName = newPrice;
    }

    // Change the maximum amount of tokens
    function setMaxtokens(uint256 newMaxtokens) public onlyOwner {
        maxTokens = newMaxtokens;
    }

    // Change the max level for ranges
    function setMaxRangeLevel(uint256 _newMaxLevel) public onlyOwner {
        maxLevel = _newMaxLevel;
    }

    // Claim deposited eth
    function ownerWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }


    string[] public  families = [       
        "god",
        "demon",
        "chosenOne",
        "reincarnate",
        "wizard",
        "savage",
        "ai"
    ];

    function addFamily(string memory family) public onlyOwner {
        families.push(family);
    }

    function resetFamilies(string[] memory _fams) public onlyOwner {
        families = _fams;
    }

    function addRange(range memory _range, string memory _name) public onlyOwner {
        rangesByFamily[_name] = _range;
    }

    function randomFromString(string memory _salt, uint256 _limit)
        internal
        view
        returns (uint256)
    {
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.number, block.timestamp, _salt)
                )
            ) % _limit;
    }

    // Returns a random item from the list, always the same for the same token ID
    function pluck(uint256 tokenId, string memory keyPrefix, string[] memory sourceArray) internal view returns (string memory) {
        uint256 rand = randomFromString(string(abi.encodePacked(keyPrefix, toString(tokenId))), sourceArray.length);

        return sourceArray[rand];
    }


    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
   

    function getRarity(uint _tokenId, string memory _family) internal view returns (string memory) {
        uint256 rarity = randomFromString(string(abi.encodePacked("rarity", toString(_tokenId), _family)), 100);
        
        if (rarity < 40) {
            return "basic";
        } else if (rarity < 70) {
            return "common";
        } else if (rarity < 84) {
            return "rare";
        } else if (rarity < 91) {
            return "veryRare";
        } else if (rarity < 96) {
            return "exotic";
        } else if (rarity < 99) {
            return "celestial";
        } else {
            return "epic";
        }
    }

    function multiplyUp(uint256 base, uint256 multiplier, uint256 limit) internal pure returns (uint256) {
        uint256 scaled = base * multiplier;
        uint256 value = scaled / 100;
        return value > limit ? limit : value;
    }

    function getRangeWith(string memory rarity, range memory rangeValues) internal view returns(range memory) {
        uint256 multiplier = 100;

        if (compareStrings(rarity, "common")) {
            multiplier = 110;
        } else if (compareStrings(rarity, "rare")) {
            multiplier = 120;
        } else if (compareStrings(rarity, "veryRare")) {
            multiplier = 140;
        } else if (compareStrings(rarity, "exotic")) {
            multiplier = 170;
        } else if (compareStrings(rarity, "celestial")) {
            multiplier = 190;
        }  else if (compareStrings(rarity, "epic")) {
            multiplier = 250;
        }
        

        return range({
            defenseMin: multiplyUp(rangeValues.defenseMin, multiplier, maxLevel),
            defenseMax: multiplyUp(rangeValues.defenseMax, multiplier, maxLevel),
            attackMin: multiplyUp(rangeValues.attackMin, multiplier, maxLevel) ,
            attackMax: multiplyUp(rangeValues.attackMax, multiplier, maxLevel),
            soulMin: multiplyUp(rangeValues.soulMin, multiplier, maxLevel),
            soulMax: multiplyUp(rangeValues.soulMax, multiplier, maxLevel),
            wisdomMin: multiplyUp(rangeValues.wisdomMin, multiplier, maxLevel),
            wisdomMax: multiplyUp(rangeValues.wisdomMax, multiplier, maxLevel)
        });
    }

    // Normal mint
    function mint() public payable nonReentrant {
        require(!paused, "Minting is paused");
        require(price <= msg.value, "Ether value sent is not correct");
        _internalMint("", _msgSender());
    }

    function mintMany(uint amount, string[] memory names) public payable nonReentrant {
        require(names.length > 0 ? names.length == amount: true, "Not correct names");
        require(!paused, "Minting is paused");
        require(amount <= 15, "Maximum mint amount is 15");

        uint256 initialPrice = names.length > 0 ? priceMintWithName : price;
        uint256 totalPrice = initialPrice * amount;
        if (amount > 1 && amount < 10) {
            uint256 discount = discountPerUnit * (amount - 1);
            totalPrice = totalPrice - discount;
        } else if (amount >= 10) {
            uint256 discount = discountPerUnit * 2 * (amount - 1);
            totalPrice = totalPrice - discount;
        }
        
        require(totalPrice <= msg.value, "Ether value sent is not correct");
        
        for(uint i = 0; i < amount; i++) {
            _internalMint(names.length > 0 ? names[i] : "", _msgSender());
        }
    }

     // Normal mint
    function mintWithName(string memory _name) public payable nonReentrant {
        require(!paused, "Minting is paused");
        require(priceMintWithName <= msg.value, "Ether value sent is not correct");
        _internalMint(_name, _msgSender());
    }

    // Allow the owner to claim a nft
    function ownerClaim(uint amount, address _address) public nonReentrant onlyOwner {
        for(uint i = 0; i < amount; i++) {
            _internalMint("", _address);
        }
    }

    function changeName(uint256 _tokenId, string memory _name)
        external
        payable
        nonReentrant
    {
        require(msg.value >= changeNamePrice, "Eth sent is not enough");
        require(_isApprovedOrOwner(msg.sender, _tokenId));
        require(bytes(_name).length <= 20 && bytes(_name).length > 2, "Name between 3 and 20 characters");
        creatures[_tokenId].nickname = _name;
        emit NameChanged(_tokenId, _name);
    }

      // Called by every function after safe access checks
    function _internalMint(string memory _name, address _address) internal returns (uint256) {
        require(bytes(_name).length <= 20, "Name is too long, max 20 characters");

        // minting logic
        uint256 current = _tokenIds.current();
        require(current <= maxTokens, "Max token reached");

        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();

        _createCreature(tokenId, _name);
        _safeMint(_address, tokenId);
        return tokenId;
    }

    // Create creature
    function _createCreature(uint256 _tokenId, string memory _name) internal {
        string memory family = pluck(_tokenId, "type", families);
        string memory rarity = getRarity(_tokenId, family);
        range memory rangeValues = getRangeWith(rarity, rangesByFamily[family]);

        creatures[_tokenId].nickname = _name;
        creatures[_tokenId].rarity = rarity;
        creatures[_tokenId].family = family;
        creatures[_tokenId].defense = rangeValues.defenseMax > rangeValues.defenseMin ? randomFromString(string(abi.encodePacked("defense", toString(_tokenId), family)), rangeValues.defenseMax - rangeValues.defenseMin) + rangeValues.defenseMin : rangeValues.defenseMax;
        creatures[_tokenId].attack =  rangeValues.attackMax > rangeValues.attackMin ?randomFromString(string(abi.encodePacked("attack", toString(_tokenId), family)), rangeValues.attackMax - rangeValues.attackMin) + rangeValues.attackMin : rangeValues.attackMax;
        creatures[_tokenId].soul = rangeValues.soulMax > rangeValues.soulMin ? randomFromString(string(abi.encodePacked("soul", toString(_tokenId), family)), rangeValues.soulMax - rangeValues.soulMin) + rangeValues.soulMin : rangeValues.soulMax;
        creatures[_tokenId].wisdom =  rangeValues.wisdomMax > rangeValues.wisdomMin ?randomFromString(string(abi.encodePacked("wisdom", toString(_tokenId), family)), rangeValues.wisdomMax - rangeValues.wisdomMin) + rangeValues.wisdomMin : rangeValues.wisdomMax;
       
        emit CreatureCreated(
            creatures[_tokenId].nickname,
            _tokenId,
            creatures[_tokenId]
        );
    }
  

    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    string private baseURI = "ipfs://";

    function _baseURI() override internal view virtual returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    } 

    function toString(uint256 value) internal pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT license
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

   
}

