// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Burnable} from "./ERC721Burnable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {AccessControlEnumerable, AccessControlEnumerable, AccessControl, IAccessControl} from "./AccessControlEnumerable.sol";
import {BitMaps} from "./BitMaps.sol";
import {ICue} from "./ICue.sol";

contract Cue is Ownable, ReentrancyGuard, ERC721, ERC721Burnable, AccessControlEnumerable, ICue {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public immutable MAX_SUPPLY;

    uint256 public totalSupply;
    uint256 public nextTokenId;
    mapping(uint256 => uint256) public tokenCueTypes;
    string internal _tokenBaseURI;
    BitMaps.BitMap internal _cueTypes;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_
    ) ERC721(name_, symbol_) {
        MAX_SUPPLY = maxSupply_;
    }

    function grantRole(
        bytes32 role,
        address account
    ) public override(AccessControl, IAccessControl) onlyOwner {
        _grantRole(role, account);
    }

    function revokeRole(
        bytes32 role,
        address account
    ) public override(AccessControl, IAccessControl) onlyOwner {
        _revokeRole(role, account);
    }

    function setTokenBaseURI(string calldata uri) external onlyOwner {
        _tokenBaseURI = uri;
        emit TokenBaseURIUpdated(uri);
    }

    function addCueTypes(uint256[] calldata types) external onlyOwner {
        for (uint256 i = 0; i < types.length; i++) {
            _cueTypes.set(types[i]);
        }
    }

    function removeCueTypes(uint256[] calldata types) external onlyOwner {
        for (uint256 i = 0; i < types.length; i++) {
            _cueTypes.unset(types[i]);
        }
    }

    function mint(
        address wallet,
        uint256 cueType
    ) external onlyRole(MINTER_ROLE) nonReentrant returns (uint256) {
        if (!_cueTypes.get(cueType)) {
            revert CueTypeNotSupported();
        }
        if (nextTokenId >= MAX_SUPPLY) {
            revert ExceedMaxSupply();
        }
        uint256 tokenId = nextTokenId++;
        _safeMint(wallet, tokenId);
        tokenCueTypes[tokenId] = cueType;
        emit CueMinted(wallet, tokenId, cueType);
        return tokenId;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlEnumerable, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function queryCueType(uint256 cueType) external view returns (bool) {
        return _cueTypes.get(cueType);
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from == address(0)) {
            totalSupply += 1;
        } else if (to == address(0)) {
            totalSupply -= 1;
        }
    }
}

