//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";

import "./IExploration.sol";
import "./IERC721Upgradeable.sol";
import "./AdminableUpgradeable.sol";
import "./IBarn.sol";

abstract contract ExplorationState is Initializable, IExploration, ERC721HolderUpgradeable, AdminableUpgradeable {
	event StartedExploring(uint256 _tokenId, address _owner);
	event ClaimedBarn(uint256 _tokenId, address _owner, uint256 _timestamp);
	event StoppedExploring(uint256 _tokenId, address _owner);
	event DonkeyLocationChanged(uint256[] _tokenIds, address _owner, Location _newLocation);

	IERC721Upgradeable public tld;
	IBarn public barn;
	
	mapping(uint256 => bool) tokenIdToBarnClaimed;
	mapping(uint256 => StakeInfo) tokenToStakeInfo;
	mapping(uint256 => uint256) tokenIdToStakeTimeInSeconds;
	uint256 public minStakingTimeInSeconds;
	mapping(uint256 => TokenInfo) internal tokenIdToInfo;
	mapping(address => EnumerableSetUpgradeable.UintSet) internal ownerToStakedTokens;

	function __ExplorationState_init() internal initializer {
		AdminableUpgradeable.__Adminable_init();
		ERC721HolderUpgradeable.__ERC721Holder_init();
	}
}

struct StakeInfo {
	address owner;
	uint256 lastStakedTime;
}

struct TokenInfo {
	address owner;
	Location location;
}

// Expands on StakeInfo, can replace StakeInfo in mainnet implementation
struct DonkeyStakeInfo {
	address owner;
	bool isStaked;
	uint256 totalStakedTime;
	uint256 lastStakedTime;
}
