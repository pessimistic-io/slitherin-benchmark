// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./StringsUpgradeable.sol";

contract Assets is
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = bytes32("MINTER_ROLE");

    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    event TokenCreated(uint256 __id);
    event TokenCreatedBatch(uint256 __fromId, uint256 __toId);
    event TransactionLimitUpdated(uint256 __transactionLimit);
    event UriUpdated(string __uri);

    ////////////////////////////////////////////////////////////////////////////
    // STATE
    ////////////////////////////////////////////////////////////////////////////

    uint256 private _latestTokenId;

    string public name;
    string public symbol;
    uint256 public transactionLimit;

    ////////////////////////////////////////////////////////////////////////////
    // INITIALIZER
    ////////////////////////////////////////////////////////////////////////////

    function __Assets_init(
        string memory __uri,
        string memory __name,
        string memory __symbol
    ) internal onlyInitializing {
        __Assets_init_unchained(__uri, __name, __symbol);
    }

    function __Assets_init_unchained(
        string memory __uri,
        string memory __name,
        string memory __symbol
    ) internal onlyInitializing {
        __ERC1155_init(__uri);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __AccessControl_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        _latestTokenId = 0;

        name = __name;
        symbol = __symbol;
        transactionLimit = 100;
    }

    ////////////////////////////////////////////////////////////////////////////
    // MODIFIERS
    ////////////////////////////////////////////////////////////////////////////

    modifier onlyExists(uint256 __id) {
        require(exists(__id), "Token not found");
        _;
    }

    ////////////////////////////////////////////////////////////////////////////
    // INTERNAL
    ////////////////////////////////////////////////////////////////////////////

    function _mintToken(
        address __account,
        uint256 __tokenId,
        uint256 __amount
    ) internal onlyExists(__tokenId) {
        require(
            __amount < transactionLimit + 1,
            "Amount exceeds transaction limit"
        );

        _mint(__account, __tokenId, __amount, "");
    }

    ////////////////////////////////////////////////////////////////////////////
    // OWNER
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Create new a token.
     */
    function create() external onlyOwner {
        _latestTokenId++;

        emit TokenCreated(_latestTokenId);
    }

    /**
     * @dev Create new token(s).
     */
    function createBatch(uint256 __amount) external onlyOwner {
        uint256 nextTokenId = _latestTokenId + 1;

        _latestTokenId += __amount;

        emit TokenCreatedBatch(nextTokenId, _latestTokenId);
    }

    /**
     * @dev Refresh metadata for a token.
     */
    function refreshMetadata(uint256 __id) external onlyOwner {
        emit URI(uri(__id), __id);
    }

    /**
     * @dev Refresh all metadata.
     */
    function refreshMetadataAll() external onlyOwner {
        string memory uriAll = uri(0);
        for (uint256 id = 1; id < _latestTokenId + 1; id++) {
            emit URI(uriAll, id);
        }
    }

    /**
     * @dev Set transaction limit.
     */
    function setTransactionLimit(
        uint256 __transactionLimit
    ) external onlyOwner {
        transactionLimit = __transactionLimit;

        emit TransactionLimitUpdated(__transactionLimit);
    }

    /**
     * @dev Sets URI.
     */
    function setUri(string memory __uri) external onlyOwner {
        _setURI(__uri);

        emit UriUpdated(__uri);
    }

    ////////////////////////////////////////////////////////////////////////////
    // MINTER
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Mint an asset.
     */
    function mint(
        address __account,
        uint256 __id,
        uint256 __amount
    ) external virtual onlyRole(MINTER_ROLE) {
        _mintToken(__account, __id, __amount);
    }

    /**
     * @dev Mint an asset for many accounts/amounts.
     */
    function mintMany(
        address[] memory __accounts,
        uint256 __id,
        uint256[] memory __amounts
    ) external virtual onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < __accounts.length; i++) {
            _mintToken(__accounts[i], __id, __amounts[i]);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // READS
    ////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Indicates whether a token exists.
     */
    function exists(uint256 __id) public view override returns (bool) {
        return __id != 0 && __id < _latestTokenId + 1;
    }

    /**
     * @dev Total number of tokens.
     */
    function totalTokens() public view returns (uint256) {
        return _latestTokenId;
    }

    ////////////////////////////////////////////////////////////////////////////
    // OVERRIDES
    ////////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address __operator,
        address __from,
        address __to,
        uint256[] memory __ids,
        uint256[] memory __amounts,
        bytes memory __data
    ) internal override(ERC1155SupplyUpgradeable, ERC1155Upgradeable) {
        super._beforeTokenTransfer(
            __operator,
            __from,
            __to,
            __ids,
            __amounts,
            __data
        );
    }

    function supportsInterface(
        bytes4 __interfaceId
    )
        public
        view
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(__interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////////
    // UPGRADEABLE
    ////////////////////////////////////////////////////////////////////////////

    function _authorizeUpgrade(
        address __newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

