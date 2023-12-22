//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./ERC721AQueryable.sol";
import "./ISpartans.sol";
import "./MerkleProof.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";
import "./ERC2981.sol";

contract Spartans is ISpartans, Ownable, ERC2981, ERC721AQueryable {
    address internal minter;
    string internal baseTokenURI;

    error OnlyMinterAccess();

    constructor(
        address _owner,
        address _treasuryWallet,
        uint96 _roylatyNumerator,
        string memory _baseTokenURI
    ) ERC721A("Spartans", "SPRTNS") {
        baseTokenURI = _baseTokenURI;
        _currentIndex = 1;

        _transferOwnership(_owner);
        _setDefaultRoyalty(_treasuryWallet, _roylatyNumerator);
    }

    modifier onlyMinterAccess() {
        if (msg.sender != minter) {
            revert OnlyMinterAccess();
        }
        _;
    }

    function safeMint(
        address to,
        uint256 amount
    ) external override onlyMinterAccess {
        _safeMint(to, amount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC721A, ERC2981, ERC721A) returns (bool) {
        return
            ERC2981.supportsInterface(interfaceId) ||
            ERC721A.supportsInterface(interfaceId);
    }

    function setBaseTokenURI(string calldata _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
}

