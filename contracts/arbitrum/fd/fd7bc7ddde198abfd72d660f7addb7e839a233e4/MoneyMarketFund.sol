// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import "./ERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

import {ModuleRegistry} from "./ModuleRegistry.sol";
import {IAuthorization} from "./IAuthorization.sol";
import {ITransferAgent} from "./ITransferAgent.sol";
import {IHoldings} from "./IHoldings.sol";

/**
 * @title Implementation of a Money Market Fund
 *
 * This implementation represents a 40 Act Fund in which all operations are cash based.
 * It means all amounts passed to the contract functions with the exception of the contructor's
 * _seed parameter represent the value (in terms of fiat currency) of the fund shares to buy or sell.
 *
 * Purchases or sells of shares requested are settled calling any of the settleTransactions or EndOfDay functions.
 * The price supplied in the settlement functions corresponds to the NAV per share at the moment of the market closing.
 *
 */
contract MoneyMarketFund is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IHoldings
{
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_PAGE_SIZE_BALANCE = 10;
    uint256 public constant NUMBER_SCALE_FACTOR = 1E18;

    bytes32 public constant ROLE_TOKEN_OWNER = keccak256("ROLE_TOKEN_OWNER");
    bytes32 constant AUTHORIZATION_MODULE = keccak256("MODULE_AUTHORIZATION");
    bytes32 constant TRANSACTIONAL_MODULE = keccak256("MODULE_TRANSACTIONAL");

    // ******************** State Variables ******************** //
    // ********************************************************* //

    uint256 public lastKnownPrice;
    ModuleRegistry moduleRegistry;
    EnumerableSet.AddressSet accountsWithHoldings;

    // ********************* Modifiers ********************* //
    // ***************************************************** //

    modifier onlyAdminOrWriteAccess() {
        require(
            IAuthorization(
                moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
            ).isAdminAccount(_msgSender()) ||
                AccessControlUpgradeable(
                    moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
                ).hasRole(keccak256("WRITE_ACCESS_TOKEN"), _msgSender()),
            "NO_WRITE_ACCESS"
        );
        _;
    }

    // -------------------- Pagination --------------------  //

    modifier onlyWithValidPageSize(uint256 pageSize, uint256 maxPageSize) {
        require(
            pageSize > 0 && pageSize <= maxPageSize,
            "INVALID_PAGINATION_SIZE"
        );
        _;
    }

    // ********************************************************************* //
    // **********************     MoneyMarketFund     ********************** //
    // ********************************************************************* //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _initToken(address owner, uint256 seed, uint256 price) private {
        lastKnownPrice = price;
        if (seed > 0) {
            _mint(owner, seed);
        }
    }

    function initialize(
        address _owner_,
        uint256 _seed_,
        uint256 _price_,
        string memory _name_,
        string memory _symbol_,
        address _moduleRegistry_
    ) public initializer {
        require(_owner_ != address(0), "Owner must not be empty!");
        require(_moduleRegistry_ != address(0), "INVALID_REGISTRY_ADDRESS");
        __ERC20_init(_name_, _symbol_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        moduleRegistry = ModuleRegistry(_moduleRegistry_);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner_);
        _setRoleAdmin(ROLE_TOKEN_OWNER, ROLE_TOKEN_OWNER);
        _grantRole(ROLE_TOKEN_OWNER, _owner_);

        _initToken(_owner_, _seed_, _price_);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(ROLE_TOKEN_OWNER) {}

    // ************************* Public Interface ************************* //
    // ******************************************************************** //

    function mintShares(
        address account,
        uint256 shares
    ) external virtual onlyAdminOrWriteAccess {
        _mint(account, shares);
    }

    function burnShares(
        address account,
        uint256 shares
    ) external virtual onlyAdminOrWriteAccess {
        _burn(account, shares);
    }

    function updateHolderInList(
        address account
    ) external virtual onlyAdminOrWriteAccess {
        if (balanceOf(account) > 0) {
            accountsWithHoldings.add(account);
        } else {
            accountsWithHoldings.remove(account);
        }
    }

    function removeEmptyHolderFromList(
        address account
    ) external virtual onlyAdminOrWriteAccess {
        if (balanceOf(account) == 0) {
            accountsWithHoldings.remove(account);
        }
    }

    function updateLastKnownPrice(
        uint256 price
    ) external virtual onlyAdminOrWriteAccess {
        lastKnownPrice = price;
    }

    // -------------------- Utility view functions --------------------  //

    function hasEnoughHoldings(
        address account,
        uint256 amount
    ) external view virtual override returns (bool) {
        uint256 holdings = ((balanceOf(account) * lastKnownPrice) /
            NUMBER_SCALE_FACTOR);
        return (holdings > 0 && holdings >= amount);
    }

    function getShareHoldings(
        address account
    ) external view virtual override returns (uint256) {
        return balanceOf(account);
    }

    // **************** Info Query Utilities (External) **************** //

    function getShareholdersWithHoldingsCount()
        external
        view
        virtual
        returns (uint256)
    {
        return accountsWithHoldings.length();
    }

    function getSharesOutstanding() external view virtual returns (uint256) {
        return totalSupply();
    }

    function hasHoldings(address account) external view virtual returns (bool) {
        return accountsWithHoldings.contains(account);
    }

    function getAccountsBalances(
        uint256 pageSize,
        uint256 startIndex
    )
        external
        view
        virtual
        onlyWithValidPageSize(pageSize, MAX_PAGE_SIZE_BALANCE)
        returns (
            bool hasNext,
            uint256 nextIndex,
            address[] memory accounts,
            uint256[] memory balances
        )
    {
        uint256 count = IAuthorization(
            moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
        ).getAuthorizedAccountsCount();
        require(startIndex <= count, "INVALID_PAGINATION_INDEX");

        uint256 arraySize = pageSize;
        hasNext = true;

        uint256 end = startIndex + pageSize;
        if (end >= count) {
            end = count;
            arraySize = end - startIndex;
            hasNext = false;
        }

        accounts = new address[](arraySize);
        balances = new uint256[](arraySize);
        nextIndex = end;

        for (uint256 i = startIndex; i < end; ) {
            uint256 resIdx = i - startIndex;
            accounts[resIdx] = IAuthorization(
                moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
            ).getAuthorizedAccountAt(i);
            balances[resIdx] = balanceOf(accounts[resIdx]);
            unchecked {
                i++;
            }
        }
    }

    // **************** Internal Functions ***************** //
    // ***************************************************** //

    // -------------------- ERC20 --------------------  //
    // https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC20-_beforeTokenTransfer-address-address-uint256-
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        // token transfers must comply with the policy
        // defined by the concrete fund implementation.
        _checkTransferPolicy(from, to);
    }

    // -------------------- Compliance --------------------  //

    // Token transfer policy for this fund
    // 1. Tokens can only be minted to the admin or shareholder accounts
    // 2. Only the admin account is allowed to perform token transfers (this could change in the future)
    // 3. Token transfers by accounts other than the admin account will revert
    function _checkTransferPolicy(
        address from,
        address to
    ) internal view virtual {
        if (from == address(0)) {
            // Minting policy
            require(
                IAuthorization(
                    moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
                ).isAdminAccount(to) ||
                    IAuthorization(
                        moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
                    ).isAccountAuthorized(to),
                "TRANSFER_RESTRICTION"
            );
        } else if (
            IAuthorization(
                moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
            ).isAdminAccount(from)
        ) {
            // Transfer policy
            if (to != address(0)) {
                require(
                    IAuthorization(
                        moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
                    ).isAccountAuthorized(to),
                    "TRANSFER_RESTRICTION"
                );
            }
        } else if (
            IAuthorization(
                moduleRegistry.getModuleAddress(AUTHORIZATION_MODULE)
            ).isAccountAuthorized(from)
        ) {
            // Burning policy
            require(to == address(0), "TRANSFER_RESTRICTION");
        } else {
            // Any other transfer is restricted
            revert("TRANSFER_RESTRICTION");
        }
    }
}

