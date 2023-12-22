// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VibeERC721} from "./VibeERC721.sol";
import {IERC6551Registry} from "./IERC6551Registry.sol";

contract VibeERC721WithAccount is VibeERC721 {
    address public registry;
    address public accountImpl;

    event MintAccount(
        address indexed owner,
        address token,
        uint256 tokenId,
        uint256 chainId,
        address account
    );

    constructor() VibeERC721() {}

    function setAccountInfo(
        address _registry,
        address _accountImpl
    ) external onlyOwner {
        registry = _registry;
        accountImpl = _accountImpl;
    }

    function mintWithAccount(
        address _to,
        uint256 _tokenId
    ) external onlyMinter {
        _mint(_to, _tokenId);
        createAccount(_to, _tokenId);
    }

    function mint(address to) external override onlyMinter returns (uint256 tokenId) {
        tokenId = totalSupply++;
        _mint(to, tokenId);
        createAccount(to, tokenId);
    }

    function mintWithId(address to, uint256 tokenId) external override onlyMinter {
        _mint(to, tokenId);
        createAccount(to, tokenId);
    }

    function createAccount(address to, uint256 tokenId) internal {
        bytes memory noneBytes;
        address nftAccount = IERC6551Registry(registry).createAccount(
            accountImpl,
            block.chainid,
            address(this),
            tokenId,
            tokenId,
            noneBytes
        );

        emit MintAccount(to, address(this), tokenId, block.chainid, nftAccount);
    }
}

