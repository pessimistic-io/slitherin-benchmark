// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721EnumerableUpgradeable.sol";
import "./extensions_IERC20MetadataUpgradeable.sol";
import "./IERC4626Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./EIP712Upgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./IERC1271Upgradeable.sol";
import "./CountersUpgradeable.sol";

import "./IStakingDepositNFT.sol";
import "./IStakingDepositNFTDesign.sol";
import "./IUnlimitedStaking.sol";

contract StakingDepositNFT is
    IStakingDepositNFT,
    ERC721EnumerableUpgradeable,
    EIP712Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    mapping(uint256 => CountersUpgradeable.Counter) private _nonces;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256(
            "Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)"
        );

    IERC20MetadataUpgradeable public UWU;
    IStakingDepositNFTDesign public design;
    IUnlimitedStaking public uwuStaking;

    uint8 public designDecimals;

    event UnlimitedStakingUpdated(IUnlimitedStaking unlimitedStaking);
    event DesignUpdated(IStakingDepositNFTDesign newValue);
    event DesignDecimalsUpdated(uint8 newValue);

    function initialize(
        string memory name,
        string memory symbol,
        IERC20MetadataUpgradeable _uwu,
        IStakingDepositNFTDesign _design,
        uint8 _designDecimals
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __EIP712_init(name, "1");
        __UUPSUpgradeable_init();
        __Ownable_init();

        UWU = _uwu;
        design = _design;
        designDecimals = _designDecimals;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @notice Returns the nonce of an NFT, which is useful for creating permits.
    /// @param tokenId The ID of the NFT to get the nonce of.
    /// @return The uint256 representation of the nonce.
    function nonces(
        uint256 tokenId
    ) external view virtual override returns (uint256) {
        return _nonces[tokenId].current();
    }

    /// @notice Returns the domain separator used in the encoding of the signature for permits, as defined by EIP-712.
    /// @return The bytes32 domain separator.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(IERC165Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IStakingDepositNFTDesign).interfaceId || // 0x5604e225
            super.supportsInterface(interfaceId);
    }

    /// @notice Approves a spender to transfer an NFT on behalf of the owner, using a signed permit.
    /// @param spender The address to approve as a spender.
    /// @param tokenId The ID of the NFT to approve the spender on.
    /// @param deadline A timestamp that specifies the permit's expiration.
    /// @param signature A traditional or EIP-2098 signature.
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        bytes memory signature
    ) external override {
        _permit(spender, tokenId, deadline, signature);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        _nonces[tokenId].increment();
        super._transfer(from, to, tokenId);
    }

    function _permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        bytes memory signature
    ) internal virtual {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "ERC721Permit: expired deadline");

        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_TYPEHASH,
                spender,
                tokenId,
                _nonces[tokenId].current(),
                deadline
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);

        (address signer, ) = ECDSAUpgradeable.tryRecover(hash, signature);
        bool isValidEOASignature = signer != address(0) &&
            _isApprovedOrOwner(signer, tokenId);

        require(
            isValidEOASignature ||
                _isValidContractERC1271Signature(
                    ownerOf(tokenId),
                    hash,
                    signature
                ) ||
                _isValidContractERC1271Signature(
                    getApproved(tokenId),
                    hash,
                    signature
                ),
            "ERC721Permit: invalid signature"
        );

        _approve(spender, tokenId);
    }

    function _isValidContractERC1271Signature(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) private view returns (bool) {
        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeWithSelector(
                IERC1271Upgradeable.isValidSignature.selector,
                hash,
                signature
            )
        );
        return (success &&
            result.length == 32 &&
            abi.decode(result, (bytes4)) ==
            IERC1271Upgradeable.isValidSignature.selector);
    }

    modifier onlyUWUStaking() {
        require(msg.sender == address(uwuStaking), "ONLY_UNLIMITED_STAKING");
        _;
    }

    /// @notice Updates the NFT design with a new design.
    /// @param newValue The new design for the NFT.
    function updateDesign(
        IStakingDepositNFTDesign newValue
    ) external override onlyOwner {
        design = newValue;
        emit DesignUpdated(newValue);
    }

    /// @notice Sets the UWUStaking contract.
    /// @param unlimitedStaking The UnlimitedStaking contract.
    function setUWUStaking(
        IUnlimitedStaking unlimitedStaking
    ) external override onlyOwner {
        uwuStaking = unlimitedStaking;
        emit UnlimitedStakingUpdated(unlimitedStaking);
    }

    /// @notice Updates the design decimals with a new value.
    /// @param newValue The new value for the design decimals.
    function updateDesignDecimals(uint8 newValue) external override onlyOwner {
        designDecimals = newValue;
        emit DesignDecimalsUpdated(newValue);
    }

    /// @notice Mints a new NFT.
    /// @param to The address to mint the NFT to.
    /// @param tokenId The ID of the NFT to be minted.
    function mint(address to, uint tokenId) external override onlyUWUStaking {
        _safeMint(to, tokenId);
    }

    /// @notice Burns an existing NFT.
    /// @param tokenId The ID of the NFT to be burned.
    function burn(uint tokenId) external override onlyUWUStaking {
        _burn(tokenId);
    }

    /**
     * @notice Safe permit and transfer from.
     * @param from The address to approve as a spender.
     * @param to The address to approve as a spender.
     * @param tokenId The ID of the NFT to approve the spender on.
     * @param _data Data to send along with a safe transfer check.
     * @param deadline A timestamp that specifies the permit's expiration.
     * @param signature A traditional or EIP-2098 signature.
     */
    function safeTransferFromWithPermit(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data,
        uint256 deadline,
        bytes memory signature
    ) external override {
        _permit(msg.sender, tokenId, deadline, signature);
        safeTransferFrom(from, to, tokenId, _data);
    }

    /// @notice Returns the URI of the specified NFT.
    /// @param tokenId The ID of the NFT to get the URI of.
    /// @return The string representation of the NFT's URI.
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, IStakingDepositNFT)
        returns (string memory)
    {
        _requireMinted(tokenId);

        return
            design.buildTokenURI(
                tokenId,
                uwuStaking.getUserInfo(tokenId),
                uwuStaking.userPendingRewards(tokenId),
                uwuStaking.getUserMultiplier(tokenId),
                uwuStaking.getCurrentEpochInfo(),
                uwuStaking.getCurrentEpochNumber(),
                UWU.symbol(),
                UWU.decimals(),
                designDecimals
            );
    }
}

