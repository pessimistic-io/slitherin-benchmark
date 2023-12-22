// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {SolidStateERC721} from "./SolidStateERC721.sol";
import {IERC721} from "./IERC721.sol";
import {ERC721Metadata, IERC721Metadata} from "./ERC721Metadata.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import {ERC721MetadataStorage} from "./ERC721MetadataStorage.sol";
import {Counters} from "./Counters.sol";
import {IERC20Metadata, IERC20} from "./IERC20Metadata.sol";
import {Base64} from "./Base64.sol";

import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {IBinaryVaultNFTFacet, ISolidStateERC721} from "./IBinaryVaultNFTFacet.sol";
import {IBinaryVaultLiquidityFacet} from "./IBinaryVaultLiquidityFacet.sol";
import {BinaryVaultFacetStorage, IVaultDiamond} from "./BinaryVaultBaseFacet.sol";
import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";
import {Strings} from "./StringUtils.sol";

library BinaryVaultNFTFacetStorage {
    using Counters for Counters.Counter;
    struct Layout {
        Counters.Counter counter;
        // prevent to call initialize function twice
        bool initialized;
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
    using Strings for uint256;
    using Strings for string;

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

    modifier initializer() {
        BinaryVaultNFTFacetStorage.Layout storage s = BinaryVaultNFTFacetStorage
            .layout();
        require(!s.initialized, "Already initialized");
        _;
        s.initialized = true;
    }

    function initialize(
        string memory name_,
        string memory symbol_
    ) external onlyOwner initializer {
        ERC721MetadataStorage.layout().name = name_;
        ERC721MetadataStorage.layout().symbol = symbol_;
    }

    function tokenURI(
        uint256 tokenId
    )
        external
        view
        virtual
        override(ERC721Metadata, IERC721Metadata)
        returns (string memory)
    {
        string memory json = getManifestPlainText(tokenId);

        return string(abi.encodePacked("data:application/json;base64,", json));
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

    function tokensOfOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 balance = _balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }

    /// @notice constructs manifest metadata in plaintext for base64 encoding
    /// @param _tokenId token id
    /// @return _manifestInJson manifest for base64 encoding
    function getManifestPlainText(
        uint256 _tokenId
    ) internal view returns (string memory _manifestInJson) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        string memory image = getImagePlainText(_tokenId);

        string memory _manifest = string(
            abi.encodePacked(
                '{"name": ',
                '"',
                IBinaryVaultNFTFacet(address(this)).name(),
                '", "description": "',
                s.config.vaultDescription(),
                '", "image": "',
                image,
                '"}'
            )
        );

        _manifestInJson = Base64.encode(bytes(_manifest));
    }

    function getImagePlainText(
        uint256 tokenId
    ) internal view returns (string memory) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        string memory template = s.config.binaryVaultImageTemplate();

        string memory result = template.replaceString(
            "<!--TOKEN_ID-->",
            tokenId.toString()
        );
        result = result.replaceString(
            "<!--SHARE_BIPS-->",
            getShareBipsExpression(tokenId)
        );
        result = result.replaceString(
            "<!--VAULT_NAME-->",
            IERC20Metadata(s.underlyingTokenAddress).symbol()
        );
        result = result.replaceString(
            "<!--VAULT_STATUS-->",
            getWithdrawalExpression(tokenId)
        );
        result = result.replaceString(
            "<!--DEPOSIT_AMOUNT-->",
            getInitialInvestExpression(tokenId)
        );
        result = result.replaceString(
            "<!--VAULT_LOGO_IMAGE-->",
            s.config.tokenLogo(s.underlyingTokenAddress)
        );
        result = result.replaceString(
            "<!--VAULT_VALUE-->",
            getCurrentValueExpression(tokenId)
        );

        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(
            bytes(string(abi.encodePacked(result)))
        );

        return string(abi.encodePacked(baseURL, svgBase64Encoded));
    }

    function getShareBipsExpression(
        uint256 tokenId
    ) internal view virtual returns (string memory) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 percent = (s.shareBalances[tokenId] * 10_000) /
            s.totalShareSupply;
        string memory percentString = percent.getFloatExpression();
        return string(abi.encodePacked(percentString, " %"));
    }

    function getInitialInvestExpression(
        uint256 tokenId
    ) internal view virtual returns (string memory) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 _value = s.initialInvestments[tokenId];
        string memory floatExpression = ((_value * 10 ** 2) /
            10 ** IERC20Metadata(s.underlyingTokenAddress).decimals())
            .getFloatExpression();
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(s.underlyingTokenAddress).symbol()
                )
            );
    }

    function getCurrentValueExpression(
        uint256 tokenId
    ) internal view virtual returns (string memory) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        (, , uint256 netValue, ) = IBinaryVaultLiquidityFacet(address(this))
            .getSharesOfToken(tokenId);
        string memory floatExpression = ((netValue * 10 ** 2) /
            10 ** IERC20Metadata(s.underlyingTokenAddress).decimals())
            .getFloatExpression();
        return
            string(
                abi.encodePacked(
                    floatExpression,
                    " ",
                    IERC20Metadata(s.underlyingTokenAddress).symbol()
                )
            );
    }

    function getWithdrawalExpression(
        uint256 tokenId
    ) internal view virtual returns (string memory) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        BinaryVaultDataType.WithdrawalRequest memory withdrawalRequest = s
            .withdrawalRequests[tokenId];
        if (withdrawalRequest.timestamp == 0) {
            return "Active";
        } else if (
            withdrawalRequest.timestamp + s.withdrawalDelayTime <=
            block.timestamp
        ) {
            return "Executable";
        } else {
            return "Pending";
        }
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

