// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {ERC721Upgradeable} from "./ERC721Upgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract MyFrenNFT is OwnableUpgradeable, ERC721Upgradeable {
    string public baseURI;
    uint256 public _tokenIds;
    mapping(address => bool) public isMinter;

    function initialize(string calldata _uri) public initializer {
        __Ownable_init();
        __ERC721_init("My Fren NFT", "MFN");
        baseURI = _uri;
        _tokenIds = 1;
    }

    /*//////////////////////////////////////////////////////////////
                        Game Actions
    //////////////////////////////////////////////////////////////*/

    function mint(address to) public {
        require(isMinter[msg.sender], "Unauthorized");

        // mint NFT
        _mint(to, _tokenIds);
        _tokenIds++;
    }

    function burnInGame(uint256 id) external {
        require(isMinter[msg.sender], "Unauthorized");

        _burn(id);
    }


    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /*//////////////////////////////////////////////////////////////
                        admin
    //////////////////////////////////////////////////////////////*/

    function setBaseURI(string calldata _uri) external onlyOwner {
        baseURI = _uri;
    }

    function setMinter(address _minter, bool _isAllowed) external onlyOwner {
        isMinter[_minter] = _isAllowed;
    }
}
