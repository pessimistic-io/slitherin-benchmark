// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @author thirdweb

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

//  ==========  External imports    ==========
import "./ERC20BurnableUpgradeable.sol";
import "./ERC20VotesUpgradeable.sol";

import "./Multicall.sol";
import "./StringsUpgradeable.sol";

//  ==========  Internal imports    ==========

import "./CurrencyTransferLib.sol";

//  ==========  Features    ==========

import "./ContractMetadata.sol";
import "./PlatformFee.sol";
import "./PrimarySale.sol";
import "./PermissionsEnumerable.sol";
import "./Drop.sol";

import "./TokenMigrateERC20.sol";

contract DropERC20M is
    Initializable,
    ContractMetadata,
    PlatformFee,
    PrimarySale,
    PermissionsEnumerable,
    Drop,
    Multicall,
    ERC20BurnableUpgradeable,
    ERC20VotesUpgradeable,
    TokenMigrateERC20
{
    using StringsUpgradeable for uint256;

    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    /// @dev Only transfers to or from TRANSFER_ROLE holders are valid, when transfers are restricted.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 private constant MIGRATION_ROLE = keccak256("MIGRATION_ROLE");

    /// @dev Max bps in the thirdweb system.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev Global max total supply of tokens.
    uint256 public maxTotalSupply;

    /// @dev Emitted when the global max supply of tokens is updated.
    event MaxTotalSupplyUpdated(uint256 maxTotalSupply);

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

    constructor() initializer {}

    /// @dev Initializes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        address __originalContract,
        bytes32 __ownershipMerkleRoot,
        string memory _contractURI
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.

        string memory _name = DropERC20M(__originalContract).name();
        string memory _symbol = DropERC20M(__originalContract).symbol();

        __ERC20Permit_init(_name);
        __ERC20_init_unchained(_name, _symbol);

        _setupMerkleRoot(__ownershipMerkleRoot);
        _setupOriginalContract(__originalContract);
        _setupContractURI(_contractURI);

        try DropERC20M(__originalContract).maxTotalSupply() returns (uint256 _maxTotalSupply) {
            maxTotalSupply = _maxTotalSupply;
        } catch {}

        {
            (address platformFeeRecipient, uint256 platformFeeBps) = DropERC20M(__originalContract)
                .getPlatformFeeInfo();
            address primarySaleRecipient = DropERC20M(__originalContract).primarySaleRecipient();

            if (platformFeeRecipient != address(0)) {
                _setupPlatformFeeInfo(platformFeeRecipient, platformFeeBps);
            }

            if (primarySaleRecipient != address(0)) {
                _setupPrimarySaleRecipient(primarySaleRecipient);
            }
        }

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, address(0));
        _setupRole(MIGRATION_ROLE, _defaultAdmin);
        _setRoleAdmin(MIGRATION_ROLE, MIGRATION_ROLE);
    }

    /*///////////////////////////////////////////////////////////////
                        Contract identifiers
    //////////////////////////////////////////////////////////////*/

    function contractType() external pure returns (bytes32) {
        return bytes32("DropERC20M");
    }

    function contractVersion() external pure returns (uint8) {
        return uint8(4);
    }

    ///     =====   Token Migration  =====
    /// @notice Returns whether merkle root can be set in the given execution context.
    function _canSetMerkleRoot() internal virtual override returns (bool) {
        return hasRole(MIGRATION_ROLE, msg.sender);
    }

    /// @dev Mints migrated tokens to recipient.
    function _mintMigratedTokens(address _to, uint256 _amount) internal override {
        _checkMaxTotalSupply(_amount);
        _mint(_to, _amount);
    }

    /*///////////////////////////////////////////////////////////////
                        Setter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets a contract admin set the global maximum supply for collection's NFTs.
    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTotalSupply = _maxTotalSupply;
        emit MaxTotalSupplyUpdated(_maxTotalSupply);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Runs before every `claim` function call.
    function _beforeClaim(
        address,
        uint256 _quantity,
        address,
        uint256,
        AllowlistProof calldata,
        bytes memory
    ) internal view override {
        _checkMaxTotalSupply(_quantity);
    }

    function _checkMaxTotalSupply(uint256 _quantity) internal view {
        uint256 _maxTotalSupply = maxTotalSupply;
        require(_maxTotalSupply == 0 || totalSupply() + _quantity <= _maxTotalSupply, "exceed max total supply.");
    }

    /// @dev Collects and distributes the primary sale value of tokens being claimed.
    function _collectPriceOnClaim(
        address _primarySaleRecipient,
        uint256 _quantityToClaim,
        address _currency,
        uint256 _pricePerToken
    ) internal override {
        if (_pricePerToken == 0) {
            require(msg.value == 0, "!Value");
            return;
        }

        (address platformFeeRecipient, uint16 platformFeeBps) = getPlatformFeeInfo();

        address saleRecipient = _primarySaleRecipient == address(0) ? primarySaleRecipient() : _primarySaleRecipient;

        // `_pricePerToken` is interpreted as price per 1 ether unit of the ERC20 tokens.
        uint256 totalPrice = (_quantityToClaim * _pricePerToken) / 1 ether;
        require(totalPrice > 0, "quantity too low");

        uint256 platformFees = (totalPrice * platformFeeBps) / MAX_BPS;

        bool validMsgValue;
        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            validMsgValue = msg.value == totalPrice;
        } else {
            validMsgValue = msg.value == 0;
        }
        require(validMsgValue, "Invalid msg value");

        CurrencyTransferLib.transferCurrency(_currency, msg.sender, platformFeeRecipient, platformFees);
        CurrencyTransferLib.transferCurrency(_currency, msg.sender, saleRecipient, totalPrice - platformFees);
    }

    /// @dev Transfers the tokens being claimed.
    function _transferTokensOnClaim(address _to, uint256 _quantityBeingClaimed) internal override returns (uint256) {
        _mint(_to, _quantityBeingClaimed);
        return 0;
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetPlatformFeeInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether primary sale recipient can be set in the given execution context.
    function _canSetPrimarySaleRecipient() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetClaimConditions() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    function _mint(address account, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._burn(account, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @dev Runs on every transfer.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable) {
        super._beforeTokenTransfer(from, to, amount);

        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to), "transfers restricted.");
        }
    }

    function _dropMsgSender() internal view virtual override returns (address) {
        return msg.sender;
    }
}

