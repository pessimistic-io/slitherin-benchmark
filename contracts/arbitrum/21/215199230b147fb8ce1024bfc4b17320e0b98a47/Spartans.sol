//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import "./ERC721AQueryable.sol";
import "./ISpartans.sol";
import "./MerkleProof.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";
import "./ERC2981.sol";

contract Spartans is ISpartans, Ownable, ERC2981, ERC721AQueryable {
    error OnlyMinterAccess();
    error MinterAlreadySet();

    event MinterSet(address indexed minter);
    bool _minterIsSet = false;
    address internal _minter;
    string internal _baseTokenURI;
    string internal _contractURI;

    constructor(
        address owner_,
        address treasuryWallet_,
        uint96 royaltyNumerator_,
        string memory baseTokenURI_,
        string memory contractURI_
    ) ERC721A("Spartans", "SPRTNS") {
        _baseTokenURI = baseTokenURI_;
        _contractURI = contractURI_;
        _currentIndex = 1;

        _transferOwnership(owner_);
        _setDefaultRoyalty(treasuryWallet_, royaltyNumerator_);
    }

    modifier onlyMinterAccess() {
        if (msg.sender != _minter) {
            revert OnlyMinterAccess();
        }
        _;
    }

    modifier onlyIfMinterIsNotSet() {
        if (_minterIsSet) {
            revert MinterAlreadySet();
        }
        _;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
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

    function setMinter(
        address minter_
    ) external onlyOwner onlyIfMinterIsNotSet {
        _minter = minter_;
        _minterIsSet = true;

        emit MinterSet(_minter);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}

