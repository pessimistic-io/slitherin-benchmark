//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./IBarnMetadata.sol";
import "./BarnMetadataState.sol";

contract BarnMetadata is Initializable, BarnMetadataState, IBarnMetadata {
	using StringsUpgradeable for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	function initialize() external initializer {
		BarnMetadataState.__BarnMetadataState_init();
	}
	
	function setBaseURI(string calldata _baseURI) override external onlyAdminOrOwner {
		baseURI = _baseURI;
	}

	/**
		Standard algorithm to disribute weighted random selection
		Take total sum of weights
		Choose a random number between 0 and sum of weights 
		If weight is less than target, we choose target
		otherwise, continue to find target
	 */
	function setBarnType(uint256 _tokenId, uint256 _randomNumber) 
		override 
		external
		onlyBarn {
		uint256 sumOfWeights = 100000;
		uint256 random = _randomNumber % sumOfWeights;
		for(uint8 i = 0; i < weights.length;i++) {
			if (random < barnIdentifierToBarnInfo[i].weight) {
				tokenIdToBarnType[_tokenId] = barnIdentifierToBarnInfo[i].barnType;
				barnTypeToCount[barnIdentifierToBarnInfo[i].barnType] += 1;
				break;
			} else {
				random -= weights[i];
			}
		}
	}

	function addBarnContract(address _barnAddress) public onlyAdminOrOwner {
		barns.add(_barnAddress);
	}

	function removeBarnContract(address _barnAddress) external onlyAdminOrOwner {
		barns.remove(_barnAddress);
	}

	function isBarn(address _barnAddress) external view returns (bool) {
		return barns.contains(_barnAddress);
	}

	modifier onlyBarn() {
		require(barns.contains(msg.sender), "Not a barn contract");

		_;
	}

	function getBarnTypeText(BarnType _barnType) private pure returns (string memory) {
		if (BarnType.SHAMBHALA_SUPER == _barnType) {
			return "shambhala";
		} else if (BarnType.VOLCANIC_SUPER == _barnType) {
			return "volcano";
		} else if (BarnType.ARID_SUPER == _barnType) {
			return "arid";
		} else if (BarnType.TROPICAL_SUPER == _barnType) {
			return "tropical";
		} else if (BarnType.COASTAL_SUPER == _barnType) {
			return "coastal";
		} else if (BarnType.FOREST_SUPER == _barnType) {
			return "forest";
		} else if (BarnType.HILLS_SUPER == _barnType) {
			return "hills";
		} else if (BarnType.PLAINS_SUPER == _barnType) {
			return "plains";
		} else if (BarnType.SHAMBHALA_NORMAL == _barnType) {
			return "shambhala";
		} else if (BarnType.VOLCANIC_NORMAL == _barnType) {
			return "volcano";
		} else if (BarnType.ARID_NORMAL == _barnType) {
			return "arid";
		} else if (BarnType.TROPICAL_NORMAL == _barnType) {
			return "tropical";
		} else if (BarnType.COASTAL_NORMAL == _barnType) {
			return "coastal";
		} else if (BarnType.FOREST_NORMAL == _barnType) {
			return "forest";
		} else if (BarnType.HILLS_NORMAL == _barnType) {
			return "hills";
		} else if (BarnType.PLAINS_NORMAL == _barnType) {
			return "plains";
		} else {
			return "NOT_FOUND";
		}
	}

	function tokenURI(uint256 _tokenId) public view override returns (string memory) {
		return string(
			abi.encodePacked(
				'data:application/json;base64,',
				Base64Upgradeable.encode(
					bytes(
						abi.encodePacked(
							'{"name":"Barn #',
							_tokenId.toString(),
							'", "description":"Just a barn in The Lost Land...", "image": "',
							_getImageUriForTokenId(_tokenId),
							'", "attributes": [',
							_getRegionAttributesForBarnJSON(_tokenId), ',',
							_getTypeAttributesForBarnJSON(_tokenId),
							']'
						)
					)
				)
			)
		);
	}

	function _setImageURIs() external onlyAdminOrOwner {
		for(uint8 i = 0; i < weights.length;i++) {
			BarnInfo memory barnInfo = barnIdentifierToBarnInfo[i];
			string memory filetype = barnInfo.barnRarity == BarnRarity.NORMAL ? '.png' : '.gif';
			string memory rarity = barnInfo.barnRarity == BarnRarity.SUPER ? 'super-' : '';
			barnTypeToImageURI[barnInfo.barnType] =  string(abi.encodePacked(baseURI, '/', rarity, getBarnTypeText(barnInfo.barnType), filetype));
		}
	}

	function _getImageUriForTokenId(uint256 _tokenId) private view returns (string memory) {
		BarnType barnType = tokenIdToBarnType[_tokenId];
		string memory imageURI = barnTypeToImageURI[barnType];
		return imageURI;
	}

	function _getRegionAttributesForBarnJSON(uint256 _tokenId) private view returns (string memory) {
		BarnType barnType = tokenIdToBarnType[_tokenId];
		return string(
		 abi.encodePacked(
			'{"trait_type": "Region",',
			'"value": "',getBarnRegionText(barnType),
			'"}'
		));
	}

	function _getTypeAttributesForBarnJSON(uint256 _tokenId) private view returns (string memory) {
		BarnType barnType = tokenIdToBarnType[_tokenId];
		BarnRarity barnRarity = barnIdentifierToBarnInfo[uint256(barnType)].barnRarity;
		return string(
		 abi.encodePacked(
			'{"trait_type": "Type",',
			'"value": "',getBarnRarityText(barnRarity),
			'"}'
		));
	}

	function getBarnRarityText(BarnRarity _barnRarity) private pure returns (string memory) {
		if (BarnRarity.NORMAL == _barnRarity) {
			return "Normal";
		}
		return "Super";
	}

	function getBarnRegionText(BarnType _barnType) private pure returns (string memory) {
		if (BarnType.SHAMBHALA_SUPER == _barnType || BarnType.SHAMBHALA_NORMAL == _barnType) {
			return "Shambhala";
		} else if (BarnType.VOLCANIC_SUPER == _barnType || BarnType.VOLCANIC_NORMAL == _barnType) {
			return "Volcano";
		} else if (BarnType.ARID_SUPER == _barnType || BarnType.ARID_NORMAL == _barnType) {
			return "Arid";
		} else if (BarnType.TROPICAL_SUPER == _barnType || BarnType.TROPICAL_NORMAL == _barnType) {
			return "Tropical";
		} else if (BarnType.COASTAL_SUPER == _barnType || BarnType.COASTAL_NORMAL == _barnType) {
			return "Coastal";
		} else if (BarnType.FOREST_SUPER == _barnType || BarnType.FOREST_NORMAL == _barnType) {
			return "Forest";
		} else if (BarnType.HILLS_SUPER == _barnType || BarnType.HILLS_NORMAL == _barnType) {
			return "Hills";
		} else if (BarnType.PLAINS_SUPER == _barnType || BarnType.PLAINS_NORMAL == _barnType) {
			return "Plains";
		} else {
			return "NOT_FOUND";
		}
	}
}
