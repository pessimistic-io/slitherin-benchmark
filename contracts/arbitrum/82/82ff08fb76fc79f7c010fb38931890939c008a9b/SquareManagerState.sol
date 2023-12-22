//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC721Upgradeable.sol";

import "./ISquareManager.sol";
import "./ISquare.sol";
import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";

abstract contract SquareManagerState is
    Initializable,
	ISquareManager,
	ERC721HolderUpgradeable,
	AdminableUpgradeable
{   
    using CountersUpgradeable for CountersUpgradeable.Counter;
	using SafeERC20Upgradeable for IERC20Upgradeable;
    event SquareClaimed(address _owner, uint256 _tokenId);

    IERC721Upgradeable public square;
    ISquare public iSquare;

    uint256[] public homeNumbers;
    uint256[] public awayNumbers;    
    uint256 public maxTokensPerWallet;
    bool public tableSet;
    bool public freeze;
    
    function __SquareManagerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        maxTokensPerWallet = 2; // by default, will increase depending on # of users
        tableSet = false;
    }
}

struct BoardRevealed {
    uint256 x_;
    uint256 y_;
}


