pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

import "./WandMetadataSvg.sol";

pragma experimental ABIEncoderV2;

interface IConnector {
  function ownerOf(uint256 tokenId) external view returns (address owner);
  function balanceOf(address _owner) external view returns (uint256);
}

struct Connector {
    address _contract;
    uint256 start;
    uint256 end;
    bool exists;
}

contract Wands is ERC721Enumerable, ReentrancyGuard, Ownable {
	uint256 public partnerPrice = 10000000000000000; // 0.01 ETH
	uint256 public price = 50000000000000000; //0.05 ETH

	using Strings for uint256;

	mapping(address => Connector) public connectors;

	event ConnectorCreated(address _contract, uint256 start, uint256 end);
	event ConnectorRemoved(address _contract);

	// Allow to extract from the smart contract, otherwise.. you're ded
    function ownerWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

	function setConnector(
		address _contract,
		uint256 _start,
		uint256 _end
	) external onlyOwner {
		connectors[_contract]._contract = _contract;
		connectors[_contract].start = _start;
		connectors[_contract].end = _end;
		connectors[_contract].exists = true;

		emit ConnectorCreated(_contract, _start, _end);
	}

	function removeConnector(address _contract) external onlyOwner {
		delete connectors[_contract];
		emit ConnectorRemoved(_contract);
	}

	function hasConnector(address _contract) external view returns (bool) {
		return connectors[_contract].exists;
	}

	function balanceOfPartner(address _contract, address sender) external view returns (uint256) {
		IConnector connector = IConnector(_contract);
		require(connectors[_contract].exists);
		return connector.balanceOf(sender);
	}
	
	struct Wands {
		uint256 tokenId;
		bool exists;
	}

	mapping (uint256 => Wands) public wandItems;

	constructor() public ERC721("Wands", "WAND") {

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

	function random(string memory input) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

	function getRandom(uint256 tokenId) public view returns (uint256) {
		uint256 rand = random(string(abi.encodePacked( blockhash(block.number-1), msg.sender, address(this), toString(tokenId) )));
		return rand % 100;
	}

	//Attributes
	string[] private creatures = [
		"Cat",
		"Cow",
		"Horse",
		"Pangolin",
		"Axolotl",
		"Deer",
		"Spider",
		"Salamander",
		"Centaur",
		"Griffin",
		"Minotaur",
		"Mermaid",
		"Unicorn",
		"Cyclops",
		"Phoenix",
		"Dragon",
		"Warewolf"
	];

	string[] private rareBreeds = [
		"Sphynx",
		"Angus",
		"Appaloosa",
		"Giant",
		"Blue",
		"Barasingha",
		"Tarantula",
		"Proteidae",
		"Elaphocentaur",
		"Keythongs",
		"Poseidon",
		"Ningyo",
		"Pegasi",
		"Semiserratus",
		"Phoenician",
		"Quetzalcoatl",
		"Therianthropic"
	];

	string[] private parts = [
		"Feather",
		"Skin",
		"Fur",
		"Hair",
		"Claw",
		"Tooth",
		"Whisker",
		"Bone",
		"Hoof",
		"Antler",
		"Flesh",
		"Blood"
	];

	string[] private prefix = [
		"Red",
		"Golden",
		"Ebony"
	];

	string[] private woodType = [
		"Ash",
		"Pine",
		"Maple",
		"Hazelnut",
		"Redwood",
		"Rowan",
		"Spruce",
		"Walnut",
		"Holly",
		"Willow",
		"Yew",
		"Sandalwood",
		"Pink Ivory",
		"Bubinga",
		"African Blackwood",
		"Purple Heart",
		"Lignum Vitae"
	];

	string[] private wandMakers = [
		"Romeo Zeigler",
		"Johannes Jonker",
		"Willow Wisp",
		"Arnold Peasegood",
		"Alfons Bloemenberg",
		"Penguin Brothers",
		"Penzy's Wands",
		"Hildebrande",
		"Juan Jose Bolibar",
		"Goblin Stick Makers",
		"Hartebeck"
	];

	string[] private specialty = [
		"Theurgy", 
		"Arcane Magic", 
		"Rune Magic", 
		"Necromancy", 
		"Shamanism", 
		"Elemental magic", 
		"Storm magic",
		"Blood magic", 
		"Aeromancy", 
		"Alchemy", 
		"Thaumaturgy", 
		"Bilocation", 
		"Pyrokinesis", 
		"Divination", 
		"Telepathy", 
		"Levitation", 
		"Telekinesis", 
		"Hydrokinesis"
	];

	string[] private spellSymbols = [
		unicode"Θ",
		unicode"δ",
		unicode"λ",
		unicode"ɜ",
		unicode"ʓ",
		unicode"Ψ",
		unicode"Ϯ",
		unicode"Ϡ",
		unicode"Ѩ",
		unicode"֍"
	];

	event WandMinted(uint256 tokenId, address sender);

	function pluck(uint256 tokenId, uint size) internal view returns (string[] memory) {
		uint256 rand = getRandom(tokenId);
		string[] memory results = new string[](size);

		uint start = 0;
		uint end = 8;
		if(rand > 70) {
			start = 8;
			end = 13;
			if(rand > 90) {
				start = 12;
				end = creatures.length;
			}
		}

		string memory part = parts[rand%parts.length];
		uint idx = (rand % (end-start))+ start;
		string memory creature = creatures[idx];
		if(rand < 10) {
			creature = string(abi.encodePacked("'", rareBreeds[idx], "' ", creature));
		}
		string memory coreType = unicode"Birthstone";
		if(idx < 9 && rand < 40) {
			coreType = unicode"Synthetic";
		}
		if(rand > 90) {
			start = 12;
			end = woodType.length;
		}
		uint lengthIdx = rand % 9+9;
		string memory length = string(abi.encodePacked(lengthIdx.toString(), '"'));
		string memory pre = "";
		if(rand > 50) {
			pre = prefix[rand%prefix.length];
			pre = string(abi.encodePacked(pre, ' '));
		}

		string memory specialtyStr = specialty[rand%specialty.length];
		string memory symbolStr = spellSymbols[rand%spellSymbols.length];
		
		uint woodIdx = (rand % (end-start))+ start;
		results[0] = string(abi.encodePacked(pre,part," of ", creature));
		results[1] = coreType;
		results[2] = woodType[woodIdx];
		results[3] = wandMakers[rand%wandMakers.length];
		results[4] = length;
		results[5] = specialtyStr;
		results[6] = symbolStr;
		return results;
	}

	function mint(uint256 tokenId) public payable nonReentrant {
		require(tokenId > 0 && tokenId <= 10000, "Token ID invalid");
		require(price == msg.value, "Ether value sent is not correct");
		_safeMint(_msgSender(), tokenId);
		emit WandMinted(tokenId, _msgSender());
	}

	function exists(uint256 tokenId) external view returns(bool) {
		return _exists(tokenId);
	}

	function mintAsPartner(
		address _contract,
		uint256 _partnerId,
		uint256 _wandsId
	) external payable nonReentrant {
		require(connectors[_contract].exists, "Contract not allowed");
		require(msg.value >= partnerPrice, "Eth sent is not enough");
		require(_wandsId > connectors[_contract].start && _wandsId < connectors[_contract].end, "_wandsId not in range");
		require(!_exists(_wandsId), "_wandsId doesn't exist");

		IConnector connector = IConnector(_contract);

		require(connector.ownerOf(_partnerId) == msg.sender, "You do not own the _partnerId");

		_safeMint(_msgSender(), _wandsId);
		emit WandMinted(_wandsId, _msgSender());
	}

	function randomTokenURI(uint256 id) public view returns (string memory) {
		// require(_exists(id), "not exist");
		string[] memory results = pluck(id, 7);
		return WandMetadataSvg.tokenURI( address(this), id, results);
	}

	function getTokenURI(uint256 id) public view returns (string memory) {
		// require(_exists(id), "not exist");
		string[] memory results = pluck(id, 7);
		return WandMetadataSvg.tokenURI( address(this), id, results);
	}

	function getTokenOwner(uint256 id) public view returns (address) {
		if(!_exists(id)) return address(0);
		return ownerOf(id);
	}

	// Allow the owner to claim in case some item remains unclaimed in the future
    function ownerClaim(uint256 tokenId) public nonReentrant onlyOwner {
        require(tokenId <= 10000, "Token ID invalid");
        _safeMint(owner(), tokenId);
    }
}
