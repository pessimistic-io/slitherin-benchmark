// SPDX-License-Identifier: None
pragma solidity 0.8.10;
import "./console.sol";
import "./IERC2981.sol";
import {UintUtils} from "./UintUtils.sol";
import {SolidStateERC1155, ERC165} from "./SolidStateERC1155.sol";
import {ERC1155MetadataStorage} from "./ERC1155MetadataStorage.sol";
import {WithStorage, WithModifiers, TokensConstants} from "./LibStorage.sol";
import {LibCharacters} from "./LibCharacters.sol";
import {LibTokens} from "./LibTokens.sol";
import "./LibPrices.sol";
import {LibUtils} from "./LibUtils.sol";
import {LibAccessControl} from "./LibAccessControl.sol";

// NOTE: Keep this reference in mind for packing ids and structuring uris https://github.com/thesandboxgame/sandbox-smart-contracts/blob/master/src/solc_0.8/asset/libraries/ERC1155ERC721Helper.sol

contract TokensFacet is
    SolidStateERC1155,
    IERC2981,
    WithStorage,
    WithModifiers
{
    using UintUtils for uint256;

    string public name = "The Beacon";

    event NftLocked(address indexed owner, uint256 indexed tokenId);

    event NftUnlocked(address indexed owner, uint256 indexed tokenId);

    event WithdrawalConfirmed(string apiId, address owner);

    string public symbol = "The Beacon NFTs";

    function contractURI() public view returns (string memory) {
        return _tc().contractUri;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override pausable {
        // TODO: Modify this when we have fungibles
        for (uint256 i; i < ids.length; i++) {
            require(!_ts().isTokenLocked[ids[i]], "Token(s) locked");

            if (
                ids[i] < LibTokens.NFTS_BASE_ID &&
                ids[i] >= LibTokens.EGGS_BASE_ID
            ) {
                require(
                    _ts().gen0EggMintStatus ==
                        LibAccessControl.Gen0EggMintStatus.FINALIZED ||
                        from == address(0),
                    "Egg transfer locked"
                );
            }

            _ts().ownerOf[ids[i]] = to;
        }

        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // TODO: Adapt to mintBatch
    function mintGameAsset(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data,
        uint256 mintId
    ) internal pausable {
        require(!_ts().mintedByMintId[mintId], "Already minted by mint ID");

        _mint(account, id, amount, data);

        _ts().mintedByMintId[mintId] = true;
    }

    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (
            _ts().royaltiesRecipient,
            (salePrice * _ts().royaltiesPercentage) / 100
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return (interfaceId == type(IERC2981).interfaceId ||
            interfaceId == 0xd9b67a26 ||
            super.supportsInterface(interfaceId));
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        /** @dev OpenSea whitelisting. */
        // TODO: Set on initializer when we know if it works
        // TODO: Also set trove address
        // TODO: Implement
        // if (operator == address(0x1E0049783F008A0085193E00003D00cd54003c71)) {
        //     return true;
        // }

        /** @dev Standard ERC1155 approvals. */
        return super.isApprovedForAll(account, operator);
    }

    function lockNft(uint256 id) public pausable {
        require(balanceOf(msg.sender, id) != 0, "Does not own token");
        require(!_ts().isTokenLocked[id], "Already locked");
        require(id >= LibTokens.NFTS_BASE_ID, "Not NFT");

        _ts().isTokenLocked[id] = true;
        emit NftLocked(msg.sender, id);
    }

    function _lockNftInternal(uint256 id) internal pausable {
        require(!_ts().isTokenLocked[id], "Already locked");
        require(id >= LibTokens.NFTS_BASE_ID);

        _ts().isTokenLocked[id] = true;
        emit NftLocked(_ts().ownerOf[id], id);
    }

    function confirmWithdrawalIntention(string memory apiId)
        external
        payable
        pausable
    {
        uint256 cost = getWithdrawalGasOffset();

        require(msg.value == cost, "Payment amount missmatch");
        require(
            !_ts().pendingWithdrawalByApiId[apiId],
            "Already pending withdrawal"
        );

        _ts().pendingWithdrawalByApiId[apiId] = true;

        emit WithdrawalConfirmed(apiId, msg.sender);
    }

    //  TODO: (address owner) -> pass as second parameter
    function unlockNft(uint256 id)
        external
        roleOnly(LibAccessControl.Roles.BORIS)
        pausable
    {
        require(_ts().isTokenLocked[id], "Already unlocked");
        _ts().isTokenLocked[id] = false;

        // TODO: Uncomment this when we have DB transfers
        // if (owner != _ts().ownerOf[id]) {
        //     _transfer(address(this), _ts().ownerOf[id], owner, id, 1, "");
        // }

        // Pass owner parameter instead of ownerOf
        emit NftUnlocked(_ts().ownerOf[id], id);
    }

    function burnNft(uint256 id)
        external
        roleOnly(LibAccessControl.Roles.BORIS)
        pausable
    {
        require(id >= LibTokens.NFTS_BASE_ID, "Not NFT");

        _ts().isTokenLocked[id] = false;

        _burn(_ts().ownerOf[id], id, 1);
    }

    function getPendingWithdrawalByApiId(string memory apiId)
        external
        view
        returns (bool)
    {
        return _ts().pendingWithdrawalByApiId[apiId];
    }

    function setPendingWithdrawalByApiId(string memory apiId, bool value)
        external
        roleOnly(LibAccessControl.Roles.BORIS)
        pausable
    {
        _ts().pendingWithdrawalByApiId[apiId] = value;
    }

    function isNftLocked(uint256 id) external view returns (bool) {
        return _ts().isTokenLocked[id];
    }

    function getOwnerOf(uint256 id) external view returns (address) {
        return _ts().ownerOf[id];
    }

    function getNftsIndex() external view returns (uint256) {
        return _ts().nftsIndex;
    }

    /// @notice Mints a character
    /// @param apiId should always be passed when possible, if not, pass empty string
    function mintCharacter(
        address owner,
        string memory characterUri,
        bool lock,
        string memory apiId,
        uint256 mintId
    )
        external
        roleOnly(LibAccessControl.Roles.FORGER)
        pausable
        returns (uint256)
    {
        uint256 characterId = _generateNftTokenId();

        mintGameAsset(owner, characterId, 1, "", mintId);
        _setTokenURI(characterId, characterUri);
        _ts().pendingWithdrawalByApiId[apiId] = false;

        if (lock) {
            _lockNftInternal(characterId);
        }

        return characterId;
    }

    /// @notice Mints an item
    /// @param apiId should always be passed when possible, if not, pass empty strings
    function mintItem(
        address owner,
        string memory itemUri,
        bool lock,
        string memory apiId,
        uint256 mintId
    )
        external
        roleOnly(LibAccessControl.Roles.FORGER)
        pausable
        returns (uint256)
    {
        uint256 itemId = _generateNftTokenId();

        mintGameAsset(owner, itemId, 1, "", mintId);
        _setTokenURI(itemId, itemUri);
        _ts().pendingWithdrawalByApiId[apiId] = false;

        if (lock) {
            _lockNftInternal(itemId);
        }

        return itemId;
    }

    function mintEgg()
        external
        payable
        pausable
        allowlisted(msg.sender)
        returns (uint256)
    {
        require(
            _ts().gen0EggMintStatus !=
                LibAccessControl.Gen0EggMintStatus.NULL &&
                _ts().gen0EggMintStatus !=
                LibAccessControl.Gen0EggMintStatus.FINALIZED,
            "Purchase disabled"
        );

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.WHITELIST
        ) {
            require(
                _ts().purchasedGen0EggsCountByAddress[msg.sender] <
                    _ts().firstStageUserGen0EggLimit,
                "Already bought egg"
            );
            require(_acs().whitelisted[msg.sender], "Whitelist required");
        }

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.COMMUNITY
        ) {
            require(
                _ts().purchasedGen0EggsCountByAddress[msg.sender] <
                    _ts().firstStageUserGen0EggLimit,
                "Already bought egg"
            );
        }

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.LASTCHANCE
        ) {
            require(
                _ts().purchasedGen0EggsCountByAddress[msg.sender] <
                    _ts().lastStageUserGen0EggLimit,
                "Already bought eggs"
            );
        }

        uint256 discountedCost = _discountGen0EggUsdPrice();

        uint256 fullCost = getGen0EggFullCost(discountedCost);

        require(
            msg.value >= ((fullCost * 980) / 1000) &&
                msg.value <= (fullCost * 1020) / 1000,
            "Payment amount missmatch"
        );

        uint256 eggId = _generateEggTokenId();

        _mint(msg.sender, eggId, 1, "");

        _ts().purchasedGen0EggsCountByAddress[msg.sender]++;

        return eggId;
    }

    function getTotalMintedEggs()
        external
        view
        returns (uint16 totalMintedEggs)
    {
        return (_ts().totalMintedEggs);
    }

    function getGen0EggUsdCredits(address owner) public view returns (uint256) {
        return _ts().gen0EggUsdCreditsByAddress[owner];
    }

    function setGen0EggUri(string memory uriToSet) public ownerOnly {
        _tc().gen0EggUri = uriToSet;
    }

    // function setBaseUri(string memory baseMetadataUri) public ownerOnly {
    //     _setBaseURI(baseMetadataUri);
    // }

    function setContractUri(string memory contractUri) public ownerOnly {
        _tc().contractUri = contractUri;
    }

    function setTokenUri(uint256 tokenId, string memory tokenUri)
        public
        ownerOnly
    {
        _setTokenURI(tokenId, tokenUri);
    }

    /// @notice Returns the metadata URI of a token
    function uri(uint256 tokenId) public view override returns (string memory) {
        ERC1155MetadataStorage.Layout storage l = ERC1155MetadataStorage
            .layout();

        if (
            tokenId < LibTokens.NFTS_BASE_ID &&
            (tokenId >= LibTokens.EGGS_BASE_ID)
        ) {
            return _tc().gen0EggUri;
        }

        string memory tokenIdURI = l.tokenURIs[tokenId];
        string memory baseURI = l.baseURI;

        if (bytes(baseURI).length == 0) {
            return tokenIdURI;
        } else if (bytes(tokenIdURI).length > 0) {
            return tokenIdURI;
        } else {
            return baseURI;
        }
    }

    function tokensByAccount(address account)
        public
        view
        override
        returns (uint256[] memory)
    {
        return _tokensByAccount(account);
    }

    /// @notice Get the count of all tokens in existence for a given token ID
    /// @param tokenId The ID of the token
    function getTotalSupply(uint256 tokenId) public view returns (uint256) {
        return _totalSupply(tokenId);
    }

    function getBaseTokenIds()
        public
        pure
        returns (
            uint64 seedPetsBaseId,
            uint64 resourcesBaseId,
            uint64 fungiblesBaseId,
            uint64 nftsBaseId,
            uint64 eggsBaseId
        )
    {
        return (
            LibTokens.SEED_PETS_BASE_ID,
            LibTokens.RESOURCES_BASE_ID,
            LibTokens.FUNGIBLES_BASE_ID,
            LibTokens.NFTS_BASE_ID,
            LibTokens.EGGS_BASE_ID
        );
    }

    // Returns the USD cost of a gen 0 egg (x1000 for precision)
    function getGen0EggUsdCost() public view returns (uint32) {
        if (
            _ts().gen0EggMintStatus == LibAccessControl.Gen0EggMintStatus.NULL
        ) {
            return _ts().gen0EggUsdCostWhitelist;
        }

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.WHITELIST
        ) {
            return _ts().gen0EggUsdCostWhitelist;
        }

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.COMMUNITY
        ) {
            return _ts().gen0EggUsdCostCommunity;
        }

        if (
            _ts().gen0EggMintStatus ==
            LibAccessControl.Gen0EggMintStatus.LASTCHANCE
        ) {
            return _ts().gen0EggUsdCostLastChance;
        }

        return _ts().gen0EggUsdCostLastChance;
    }

    function getGen0EggCost(uint256 usdCost) public view returns (uint256) {
        return
            LibPrices.getPerDollarTokenPrice(
                usdCost,
                _ps().nativeTokenPriceInUsdFixed
            );
    }

    function getGen0EggGasOffset() public view returns (uint256) {
        return _ts().gen0EggGasOffset;
    }

    function getGen0EggFullCost(uint256 usdCost) public view returns (uint256) {
        return getGen0EggCost(usdCost) + getGen0EggGasOffset();
    }

    function _discountGen0EggUsdPrice() internal returns (uint256) {
        uint32 usdCost = getGen0EggUsdCost();

        uint256 discountedCost = usdCost -
            LibUtils.min(usdCost, _ts().gen0EggUsdCreditsByAddress[tx.origin]);

        if (usdCost >= _ts().gen0EggUsdCreditsByAddress[tx.origin]) {
            _ts().gen0EggUsdCreditsByAddress[tx.origin] = 0;
        } else {
            _ts().gen0EggUsdCreditsByAddress[tx.origin] -= usdCost;
        }

        return discountedCost;
    }

    function getWithdrawalGasOffset() public view returns (uint256) {
        return _ts().withdrawalGasOffset;
    }

    function getMintedByMintId(uint256 mintId) public view returns (bool) {
        return _ts().mintedByMintId[mintId];
    }

    /// @dev Generates a unique incremental id for an NftToken
    function _generateEggTokenId() internal pausable returns (uint256) {
        require(
            _ts().eggsIndex <
                (LibTokens.NFTS_BASE_ID - _ts().reservedGen0EggCount),
            "Max eggs minted"
        );

        return _ts().eggsIndex++;
    }

    /// @dev Generates a unique incremental id for an NftToken
    function _generateNftTokenId() internal pausable returns (uint256) {
        return _ts().nftsIndex++;
    }

    function getPurchasedEggsCountByAddress() external view returns (uint16) {
        return _ts().purchasedGen0EggsCountByAddress[msg.sender];
    }
}

