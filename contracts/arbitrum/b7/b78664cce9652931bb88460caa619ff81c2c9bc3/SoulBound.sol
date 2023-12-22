//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./IERC5192.sol";
import "./ERC721AUpgradeable.sol";
import "./Initializable.sol";

abstract contract SoulBound is Initializable, IERC5192, ERC721AUpgradeable {
    mapping(uint256 => bool) private _isLocked;
    bytes4 private constant _INTERFACE_ID_ERC5192 = 0xb45a3c0e;

    function __SoulBound_init(
        string memory name,
        string memory symbol
    ) internal onlyInitializingERC721A onlyInitializing {
        __ERC721A_init(name, symbol);
    }

    function _mint(address to, uint256 quantity) internal virtual override {
        super._mint(to, quantity);
        // lock immediately after minting
        for (uint i = 0; i < quantity; ) {
            _lock(_totalMinted() - 1 - i);
            unchecked {
                i++;
            }
        }
    }

    function locked(uint256 tokenId) external view returns (bool) {
        return _isLocked[tokenId];
    }

    function _lock(uint256 tokenId) internal {
        _isLocked[tokenId] = true;
        emit Locked(tokenId);
    }

    function _unlock(uint256 tokenId) internal {
        _isLocked[tokenId] = false;
        emit Unlocked(tokenId);
    }

    function _beforeTokenTransfers(
        address,
        address,
        uint256 firstTokenId,
        uint256 quantity
    ) internal view virtual override {
        for (uint i = 0; i < quantity; i++) {
            // when minting, mapping is empty so `false` is retrieved as default value
            require(_isLocked[firstTokenId + i] != true, 'SoulBound: token is locked');
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        if (interfaceId == _INTERFACE_ID_ERC5192) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId, true);
        delete _isLocked[tokenId];
    }

    function _forceBurn(uint256 tokenId) internal virtual {
        super._burn(tokenId, false);
        delete _isLocked[tokenId];
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

