// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {SolidStateERC721} from "./SolidStateERC721.sol";
import {IERC721} from "./IERC721.sol";
import {ERC721Metadata, IERC721Metadata} from "./ERC721Metadata.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import {ERC721MetadataStorage} from "./ERC721MetadataStorage.sol";
import {Counters} from "./Counters.sol";
import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {IBinaryVaultNFTFacet, ISolidStateERC721} from "./IBinaryVaultNFTFacet.sol";

interface IBinaryVaultFacet {
    function generateTokenURI(uint256 tokenId)
        external
        view
        returns (string memory);
}

interface IVaultDiamond {
    function owner() external view returns (address);
}

library BinaryVaultNFTFacetStorage {
    using Counters for Counters.Counter;
    struct Layout {
        Counters.Counter counter;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("balancecapital.ryze.storage.BinaryVaultNFTFacet");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

contract BinaryVaultNFTFacet is
    SolidStateERC721,
    IBinaryVaultPluginImpl,
    IBinaryVaultNFTFacet
{
    using Counters for Counters.Counter;

    modifier onlyFromDiamond() {
        require(msg.sender == address(this), "INVALID_CALLER");
        _;
    }
    modifier onlyOwner() {
        require(
            IVaultDiamond(address(this)).owner() == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    function initialize(string memory name_, string memory symbol_)
        external
        onlyOwner
    {
        ERC721MetadataStorage.layout().name = name_;
        ERC721MetadataStorage.layout().symbol = symbol_;
    }

    function tokenURI(uint256 tokenId)
        external
        view
        virtual
        override(ERC721Metadata, IERC721Metadata)
        returns (string memory)
    {
        return IBinaryVaultFacet(address(this)).generateTokenURI(tokenId);
    }

    function _nextTokenId() internal view returns (uint256) {
        return BinaryVaultNFTFacetStorage.layout().counter.current();
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId();
    }

    function mint(address owner) external onlyFromDiamond {
        _safeMint(owner, _nextTokenId());
        BinaryVaultNFTFacetStorage.layout().counter.increment();
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function burn(uint256 tokenId) external onlyFromDiamond {
        _burn(tokenId);
    }

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 balance = _balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    function pluginSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](18);
        s[0] = IBinaryVaultNFTFacet.nextTokenId.selector;
        s[1] = IBinaryVaultNFTFacet.mint.selector;
        s[2] = IBinaryVaultNFTFacet.exists.selector;
        s[3] = IBinaryVaultNFTFacet.burn.selector;
        s[4] = IBinaryVaultNFTFacet.tokensOfOwner.selector;

        s[5] = IERC721Metadata.tokenURI.selector;
        s[6] = IERC721Metadata.name.selector;
        s[7] = IERC721Metadata.symbol.selector;

        s[8] = IERC721Enumerable.totalSupply.selector;

        s[9] = IERC721.ownerOf.selector;
        s[10] = IERC721.balanceOf.selector;
        s[11] = IERC721.transferFrom.selector;
        s[12] = IERC721.approve.selector;
        s[13] = IERC721.getApproved.selector;
        s[14] = IERC721.setApprovalForAll.selector;
        s[15] = IERC721.isApprovedForAll.selector;
        s[16] = bytes4(
            keccak256(bytes("safeTransferFrom(address,address,uint256)"))
        );
        s[17] = bytes4(
            keccak256(bytes("safeTransferFrom(address,address,uint256,bytes)"))
        );
    }

    function pluginMetadata()
        external
        pure
        returns (bytes4[] memory selectors, bytes4 interfaceId)
    {
        selectors = pluginSelectors();
        interfaceId = type(IERC721).interfaceId;
    }
}

