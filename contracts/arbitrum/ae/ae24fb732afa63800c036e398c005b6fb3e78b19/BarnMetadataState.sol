//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";


import "./AdminableUpgradeable.sol";
import "./BarnMetadata.sol";

abstract contract BarnMetadataState is Initializable, AdminableUpgradeable {
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	EnumerableSetUpgradeable.AddressSet internal barns;

	string public baseURI;
	mapping(uint256 => BarnType) public tokenIdToBarnType;
	mapping(uint256 => BarnInfo) public barnIdentifierToBarnInfo;
	uint256[16] public weights;
	mapping(BarnType => uint256) public barnTypeToCount;
	mapping(BarnType => string) public barnTypeToImageURI;

	function __BarnMetadataState_init() internal initializer {
		AdminableUpgradeable.__Adminable_init();
		initialize_state();
	}

	function initialize_state() private {
		// Sorted by most-rare -> least-rare
		// Solidity does not support doubles, standardizing to remove decimals
		// Weights are determined by its region weight multiplied by the probability of
		// Barn type. Asterisk means a small buffer to account for random generated observed
		// during testing.
		weights[0] = 295; //SHAMBHALA_SUPER    | Region weight: 2.5% | Super barn: 5% *
		barnIdentifierToBarnInfo[0] = BarnInfo(weights[0], BarnType.SHAMBHALA_SUPER, BarnRarity.SUPER);

		weights[1] = 370; //VOLCANIC_SUPER     | Region weight: 7.5% | Super barn: 5%
		barnIdentifierToBarnInfo[1] = BarnInfo(weights[1], BarnType.VOLCANIC_SUPER, BarnRarity.SUPER);
		
		weights[2] = 370; //ARID_SUPER         | Region weight: 7.5% | Super barn: 5%
		barnIdentifierToBarnInfo[2] = BarnInfo(weights[2], BarnType.ARID_SUPER, BarnRarity.SUPER);
		
		weights[3] = 620; //TROPICAL_SUPER     | Region weight: 12.5% | Super barn: 5%
		barnIdentifierToBarnInfo[3] = BarnInfo(weights[3], BarnType.TROPICAL_SUPER, BarnRarity.SUPER);

		weights[4] = 745; //COASTAL_SUPER      | Region weight: 15% | Super barn: 5% *
		barnIdentifierToBarnInfo[4] = BarnInfo(weights[4], BarnType.COASTAL_SUPER, BarnRarity.SUPER);

		weights[5] = 745; //FOREST_SUPER       | Region weight: 15% | Super barn: 5% *
		barnIdentifierToBarnInfo[5] = BarnInfo(weights[5], BarnType.FOREST_SUPER, BarnRarity.SUPER);

		weights[6] = 1000; //HILLS_SUPER       | Region weight: 20% | Super barn: 5%
		barnIdentifierToBarnInfo[6] = BarnInfo(weights[6], BarnType.HILLS_SUPER, BarnRarity.SUPER);

		weights[7] = 1000; //PLAINS_SUPER      | Region weight: 20% | Super barn: 5%
		barnIdentifierToBarnInfo[7] = BarnInfo(weights[7], BarnType.PLAINS_SUPER, BarnRarity.SUPER);

		weights[8] = 2230; //SHAMBHALA_NORMAL  | Region weight: 2.5% | Super barn: 95%
		barnIdentifierToBarnInfo[8] = BarnInfo(weights[8], BarnType.SHAMBHALA_NORMAL, BarnRarity.NORMAL);

		weights[9] = 7125; //VOLCANIC_NORMAL   | Region weight: 7.5% | Super barn: 95%
		barnIdentifierToBarnInfo[9] = BarnInfo(weights[9], BarnType.VOLCANIC_NORMAL, BarnRarity.NORMAL);

		weights[10] = 7125; //ARID_NORMAL      | Region weight: 7.5% | Super barn: 95%
		barnIdentifierToBarnInfo[10] = BarnInfo(weights[10], BarnType.ARID_NORMAL, BarnRarity.NORMAL);

		weights[11] = 11875; //TROPICAL_NORMAL | Region weight: 12.5% | Super barn: 95%
		barnIdentifierToBarnInfo[11] = BarnInfo(weights[11], BarnType.TROPICAL_NORMAL, BarnRarity.NORMAL);

		weights[12] = 14250; //COASTAL_NORMAL  | Region weight: 15% | Super barn: 95%
		barnIdentifierToBarnInfo[12] = BarnInfo(weights[12], BarnType.COASTAL_NORMAL, BarnRarity.NORMAL);

		weights[13] = 14250; //FOREST_NORMAL   | Region weight: 15% | Super barn: 95%
		barnIdentifierToBarnInfo[13] = BarnInfo(weights[13], BarnType.FOREST_NORMAL, BarnRarity.NORMAL);

		weights[14] = 19000; //HILLS_NORMAL    | Region weight: 20% | Super barn: 95% 
		barnIdentifierToBarnInfo[14] = BarnInfo(weights[14], BarnType.HILLS_NORMAL, BarnRarity.NORMAL);

		weights[15] = 19000; //PLAINS_NORMAL   | Region weight: 20% | Super barn: 95%
		barnIdentifierToBarnInfo[15] = BarnInfo(weights[15], BarnType.PLAINS_NORMAL, BarnRarity.NORMAL);
	}
} 

enum BarnType {
	SHAMBHALA_SUPER, // 0
	VOLCANIC_SUPER, // 1
	ARID_SUPER, // 2
	TROPICAL_SUPER, // 3
	COASTAL_SUPER, // 4
	FOREST_SUPER, // 5
	HILLS_SUPER, // 6
	PLAINS_SUPER, // 7
	SHAMBHALA_NORMAL, // 8
	VOLCANIC_NORMAL, // 9
	ARID_NORMAL, // 10
	TROPICAL_NORMAL, // 11
	COASTAL_NORMAL, // 12
	FOREST_NORMAL, // 13
	HILLS_NORMAL, // 14
	PLAINS_NORMAL // 15
}

enum BarnRarity {
	NORMAL,
	SUPER
}

struct BarnInfo {
	uint256 weight;
	BarnType barnType;
	BarnRarity barnRarity;
}

