// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ERC721.sol";
import "./AccessControl.sol";
import "./Base64.sol";

interface IDiVampNames {
	function getName(uint256 id) external view returns (string memory);
	function setName(uint256 _tokenId, uint256[3] calldata _name) external;
}

contract DiVamps is ERC721, AccessControl {
	using Strings for uint256;

	IDiVampNames public diVampNames;

	uint256 public totalSupply;

	struct Asset {
		string name;
		string svg;
		string svgBehind;
		bool locked;
		mapping(address => bool) unlocked;
	}

	struct AssetUpdate {
    uint256 key;
    string name;
		string svg;
		string svgBehind;
		bool locked;
  }

	struct AssetUnlockedUpdate {
    uint256 key;
		address user;
    bool unlocked;
  }

	string public bodyAsset;

	mapping(uint256 => Asset) public headAssets;
	mapping(uint256 => Asset) public eyeAssets;
	mapping(uint256 => Asset) public mouthAssets;
	mapping(uint256 => Asset) public upperBodyAssets;
	mapping(uint256 => Asset) public lowerBodyAssets;
	mapping(uint256 => Asset) public feetAssets;
	mapping(uint256 => Asset) public leftHandAssets;
	mapping(uint256 => Asset) public rightHandAssets;
	mapping(uint256 => Asset) public dualWieldAssets;

	mapping(uint256 => string) public skinColors;
	mapping(uint256 => string) public classes;
	mapping(uint256 => uint256[11]) diVampDNAs;

	mapping(address => uint256) public tokenOfOwner;
	mapping(address => address) public referrers; // referee => referrer

	event Referred(
		address indexed referrer,
		address referee
	);

	event SetDNA(
		address indexed sender,
		uint256[11] dna
	);

	bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

	constructor() ERC721("DiVamps", "DIVAMP") {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(ASSET_MANAGER_ROLE, msg.sender);
	}

	function mint(uint256[11] memory _dna, uint256[3] calldata _name, address _referrer) external {
		require(balanceOf(msg.sender) == 0, "Only 1 DiVamp allowed per wallet");

		if (_referrer != address(0)) {
			require(balanceOf(_referrer) == 1, "Referrer does not own a DiVamp");

			referrers[msg.sender] = _referrer;

			emit Referred(_referrer, msg.sender);
		}

		totalSupply++;
		uint256 tokenId = totalSupply;
		_mint(msg.sender, tokenId);

		setDNA(tokenId, _dna);
		tokenOfOwner[msg.sender] = tokenId;
		diVampNames.setName(tokenId, _name);
	}

	function setDNA(uint256 _tokenId, uint256[11] memory _dna) public {
		require(ownerOf(_tokenId) == msg.sender, "Must be DiVamp owner");

		require(bytes(headAssets[_dna[0]].name).length != 0, "Invalid head asset");
		require(bytes(eyeAssets[_dna[1]].name).length != 0, "Invalid eyes asset");
		require(bytes(mouthAssets[_dna[2]].name).length != 0, "Invalid mouth asset");
		require(bytes(upperBodyAssets[_dna[3]].name).length != 0, "Invalid upper body asset");
		require(bytes(lowerBodyAssets[_dna[4]].name).length != 0, "Invalid lower body asset");
		require(bytes(feetAssets[_dna[5]].name).length != 0, "Invalid feet asset");
		require(bytes(leftHandAssets[_dna[6]].name).length != 0, "Invalid left hand asset");
		require(bytes(rightHandAssets[_dna[7]].name).length != 0, "Invalid right hand asset");
		require(bytes(dualWieldAssets[_dna[8]].name).length != 0, "Invalid dual wield asset");
		require(bytes(skinColors[_dna[9]]).length != 0, "Invalid skin color");

		require(headAssets[_dna[0]].locked == false || headAssets[_dna[0]].unlocked[msg.sender] == true, "Head asset locked");
		require(eyeAssets[_dna[1]].locked == false || eyeAssets[_dna[1]].unlocked[msg.sender] == true, "Eye asset locked");
		require(mouthAssets[_dna[2]].locked == false || mouthAssets[_dna[2]].unlocked[msg.sender] == true, "Mouth asset locked");
		require(upperBodyAssets[_dna[3]].locked == false || upperBodyAssets[_dna[3]].unlocked[msg.sender] == true, "Upper body asset locked");
		require(lowerBodyAssets[_dna[4]].locked == false || lowerBodyAssets[_dna[4]].unlocked[msg.sender] == true, "Lower body asset locked");
		require(feetAssets[_dna[5]].locked == false || feetAssets[_dna[5]].unlocked[msg.sender] == true, "Feet asset locked");
		require(leftHandAssets[_dna[6]].locked == false || leftHandAssets[_dna[6]].unlocked[msg.sender] == true, "Left hand asset locked");
		require(rightHandAssets[_dna[7]].locked == false || rightHandAssets[_dna[7]].unlocked[msg.sender] == true, "Right hand asset locked");
		require(dualWieldAssets[_dna[8]].locked == false || dualWieldAssets[_dna[8]].unlocked[msg.sender] == true, "Dual wield asset locked");

		// if dual wield, disable hands
		if (_dna[8] != 0) {
			_dna[6] = 0; // left hand
			_dna[7] = 0; // right hand
		}

		diVampDNAs[_tokenId] = _dna;

		emit SetDNA(msg.sender, _dna);
	}

	function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
		require(_tokenId > 0 && _tokenId <= totalSupply, "Nonexistent token");

		return string.concat(
			"data:application/json;base64,",
			Base64.encode(
				bytes(
					string.concat(
						'{',
							'"name": "', diVampNames.getName(_tokenId), '",', 
							'"description": "Create your DiVamp to help decentralize Ethereum and earn DIVA rewards",',
							'"image_data": "', imageData(_tokenId), '",',
							'"external_url": "https://divamps.com",',
							'"attributes": [', attributes(_tokenId), ']',
						'}'
					)
				)
			)
		);
	}

	function imageData(uint256 _tokenId) public view returns (string memory) {
		require(_tokenId > 0 && _tokenId <= totalSupply, "Nonexistent token");

		uint256[11] memory dna = diVampDNAs[_tokenId];

		return string.concat(
			"<svg id='divamp-", _tokenId.toString(), "' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>",
				styles(_tokenId, dna),
				paths(dna),
			"</svg>"
		);
	}

	function styles(uint256 _tokenId, uint256[11] memory _dna) internal view returns (string memory) {
		return string.concat("<style>#divamp-", _tokenId.toString(), " .skin { fill: #", skinColors[_dna[9]], "; }</style>");
	}

	function paths(uint256[11] memory _dna) internal view returns (string memory) {
		return string.concat(
			bodyAsset,
			headAssets[_dna[0]].svgBehind,
			upperBodyAssets[_dna[3]].svgBehind,
			feetAssets[_dna[5]].svg,
			lowerBodyAssets[_dna[4]].svg,
			upperBodyAssets[_dna[3]].svg,
			mouthAssets[_dna[2]].svg,
			eyeAssets[_dna[1]].svg,
			headAssets[_dna[0]].svg,
			leftHandAssets[_dna[6]].svg,
			rightHandAssets[_dna[7]].svg,
			dualWieldAssets[_dna[8]].svg
		);
	}

	function attributes(uint256 _tokenId) internal view returns (string memory) {
		uint256[11] memory dna = diVampDNAs[_tokenId];

		return string.concat(
			'{ "trait_type": "Head", "value": "', headAssets[dna[0]].name, '" },',
			'{ "trait_type": "Eyes", "value": "', eyeAssets[dna[1]].name, '" },',
			'{ "trait_type": "Mouth", "value": "', mouthAssets[dna[2]].name, '" },',
			'{ "trait_type": "Upper Body", "value": "', upperBodyAssets[dna[3]].name, '" },',
			'{ "trait_type": "Lower Body", "value": "', lowerBodyAssets[dna[4]].name, '" },',
			'{ "trait_type": "Feet", "value": "', feetAssets[dna[5]].name, '" },',
			'{ "trait_type": "Left Hand", "value": "', leftHandAssets[dna[6]].name, '" },',
			'{ "trait_type": "Right Hand", "value": "', rightHandAssets[dna[7]].name, '" },',
			'{ "trait_type": "Dual Wield", "value": "', dualWieldAssets[dna[8]].name, '" },',
			'{ "trait_type": "Class", "value": "', classes[dna[10]], '" }'
		);
	}

	function updateBodyAsset(string calldata _asset) external onlyRole(ASSET_MANAGER_ROLE) {
		bodyAsset = _asset;
	}

	function updateHeadAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			headAssets[key].name = _assets[i].name;
			headAssets[key].svg = _assets[i].svg;
			headAssets[key].svgBehind = _assets[i].svgBehind;
			headAssets[key].locked = _assets[i].locked;
		}
	}

	function updateEyeAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			eyeAssets[key].name = _assets[i].name;
			eyeAssets[key].svg = _assets[i].svg;
			eyeAssets[key].locked = _assets[i].locked;
		}
	}

	function updateMouthAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			mouthAssets[key].name = _assets[i].name;
			mouthAssets[key].svg = _assets[i].svg;
			mouthAssets[key].locked = _assets[i].locked;
		}
	}

	function updateUpperBodyAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			upperBodyAssets[key].name = _assets[i].name;
			upperBodyAssets[key].svg = _assets[i].svg;
			upperBodyAssets[key].svgBehind = _assets[i].svgBehind;
			upperBodyAssets[key].locked = _assets[i].locked;
		}
	}

	function updateLowerBodyAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			lowerBodyAssets[key].name = _assets[i].name;
			lowerBodyAssets[key].svg = _assets[i].svg;
			lowerBodyAssets[key].locked = _assets[i].locked;
		}
	}

	function updateFeetAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			feetAssets[key].name = _assets[i].name;
			feetAssets[key].svg = _assets[i].svg;
			feetAssets[key].locked = _assets[i].locked;
		}
	}

	function updateLeftHandAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			leftHandAssets[key].name = _assets[i].name;
			leftHandAssets[key].svg = _assets[i].svg;
			leftHandAssets[key].locked = _assets[i].locked;
		}
	}

	function updateRightHandAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			rightHandAssets[key].name = _assets[i].name;
			rightHandAssets[key].svg = _assets[i].svg;
			rightHandAssets[key].locked = _assets[i].locked;
		}
	}

	function updateDualWieldAssets(AssetUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			dualWieldAssets[key].name = _assets[i].name;
			dualWieldAssets[key].svg = _assets[i].svg;
			dualWieldAssets[key].locked = _assets[i].locked;
		}
	}

	function updateSkinColors(string[] calldata _colors) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _colors.length; i++) {
			skinColors[i] = _colors[i];
		}
	}

	function updateClasses(string[] calldata _classes) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _classes.length; i++) {
			classes[i] = _classes[i];
		}
	}

	function unlockHeadAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			headAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockEyeAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			eyeAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockMouthAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			mouthAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockupperBodyAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			upperBodyAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockLowerBodyAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			lowerBodyAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockFeetAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			feetAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockLeftHandAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			leftHandAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockRightHandAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			rightHandAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function unlockDualWieldAssets(AssetUnlockedUpdate[] calldata _assets) external onlyRole(ASSET_MANAGER_ROLE) {
		for (uint256 i = 0; i < _assets.length; i++) {
			uint256 key = _assets[i].key;
			address user = _assets[i].user;
			dualWieldAssets[key].unlocked[user] = _assets[i].unlocked;
		}
	}

	function getDiVampDNA(uint256 _tokenId) public view returns (uint256[11] memory) {
		return diVampDNAs[_tokenId];
	}

	function setNameContract(address _address) external onlyRole(ASSET_MANAGER_ROLE) {
		diVampNames = IDiVampNames(_address);
	}

	function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

	function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
		require(from == address(0), "DiVamps are soulbound and cannot be transferred");
	}
}

