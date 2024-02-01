// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./AccessControlUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";

/// @custom:security-contact info@elseverse.io
contract ElseVerseBoxes is Initializable, ERC721Upgradeable, ERC721BurnableUpgradeable, OwnableUpgradeable  {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for ERC20Upgradeable;


    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

	mapping(address => int) public whitelist;
	
	int public totalMints;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC721_init("ElseVerseBoxes", "ELSL");
        __ERC721Burnable_init();
        __Ownable_init();
    }
	
	function addToWhitelist(address[] memory addrs) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
			if (whitelist[addrs[i]] > 0) {
				whitelist[addrs[i]]++;
			}
			else {
				whitelist[addrs[i]] = 1;
			}
        }
	}
	
	function removeFromWhitelist(address[] calldata toRemoveAddresses)
    external onlyOwner
    {
        for (uint i = 0; i < toRemoveAddresses.length; i++) {
			if (whitelist[toRemoveAddresses[i]] > 1) {
				whitelist[toRemoveAddresses[i]] = whitelist[toRemoveAddresses[i]] - 1;
			}
			else {
				delete whitelist[toRemoveAddresses[i]];
			}
        }
    }
	
	function bulkSafeMint(address[] memory tos) external onlyOwner {
		for (uint i = 0; i < tos.length; i++) {
			uint256 tokenId = _tokenIdCounter.current();
			_tokenIdCounter.increment();
			_safeMint(tos[i], tokenId);
		}
	}

    function safeMint() public {
		require(totalMints <= 9000, "Mint is over");
		
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
		
		totalMints++;
    }
	
    function withdraw(address _currency, address _to, uint256 _amount) external onlyOwner  {
        IERC20Upgradeable(_currency).safeTransfer(_to, _amount);
    }
	
	function _baseURI() internal view override virtual returns (string memory) {
		return "https://api.elseverse.io/nfts/mystery-box/";
	}
	
    function version() external pure returns (uint256) {
        return 101; // 1.0.1
    }

}
