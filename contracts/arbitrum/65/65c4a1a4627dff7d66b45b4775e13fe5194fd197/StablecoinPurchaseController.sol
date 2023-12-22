// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// use SafeERC20: https://soliditydeveloper.com/safe-erc20
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Pausable} from "./Pausable.sol";
import {IERC721Rails} from "./IERC721Rails.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";

import {SetupController} from "./SetupController.sol";
import {PermitController} from "./PermitController.sol";
import {FeeController} from "./FeeController.sol";
import {PayoutAddressExtension} from "./PayoutAddressExtension.sol";

/// @title Station Network StablecoinPurchaseController Contract
/// @author symmetry (@symmtry69), frog (@0xmcg)
/// @notice Mint membership tokens when users pay a fixed quantity of a stablecoin
/// @dev Storage is designed to minimize costs for accepting multiple stablecoins as
/// payment by packing all data into 1 slot. Updating the price for N stablecoins has
/// constant G(1) gas complexity. Additionally, it is guaranteed that all stablecoins
/// will use the same price value and can never get out of sync. Deploy one instance
/// of this module per currency, per chain (e.g. USD, EUR, BTC).

contract StablecoinPurchaseController is SetupController, PermitController, FeeController, Pausable {
    using SafeERC20 for IERC20Metadata;

    /// @dev Struct of collection price data
    /// @param price The price in ERC20 tokens set for a collection's mint
    /// Max value of uint128 (~3.4e38) is several orders of magnitude larger than the current total supply of Ethereum (1.2e26 wei)
    /// @param enabledCoins A bitmap of single byte keys that correspond to supported stablecoins
    struct Parameters {
        uint128 price;
        bytes16 enabledCoins;
    }

    /*=============
        STORAGE
    =============*/

    /// @dev Decimals of precision for this module's currency
    uint8 public immutable decimals;
    // currency type for this particular contract. (USD, EUR, etc.)
    string public currency;
    /// @dev The total number of keys currently in bitmap, initialized to the number of default addresses in StablecoinRegistry
    /// @notice This counter supports up to 255 stablecoin address keys in a bytes16 map
    uint8 public keyCounter;
    /// @dev Mapping of stablecoin address => associated key in bitmap
    mapping(address => uint8) internal _keyOf;
    /// @dev Mapping of bitmap key => stablecoin address
    mapping(uint8 => address) internal _stablecoinOf;
    /// @dev Mapping of each collection => mint parameters configuration
    mapping(address => Parameters) internal _parameters;
    /// @dev collection => permits disabled, permits are enabled by default
    mapping(address => bool) internal _disablePermits;

    /*============
        EVENTS
    ============*/

    event Register(address indexed stablecoin, uint8 indexed key);
    /// @dev Events share names but differ in parameters to differentiate them between controllers
    event SetUp(address indexed collection, uint128 price, address[] enabledCoins, bool indexed enablePermits);

    /*============
        CONFIG
    ============*/

    /// @param _owner The owner of this contract
    /// @param _feeManager The FeeManager module's address
    /// @param _decimals The decimals value for this module's supported stablecoin payments
    /// @param _currency The type of currency managed by this module
    constructor(
        address _owner,
        address _feeManager,
        uint8 _decimals,
        string memory _currency
    ) PermitController() FeeController(_owner, _feeManager) {
        decimals = _decimals;
        currency = _currency;
    }

    /// @dev Function to register new stablecoins when requested by clients
    /// @param stablecoin The stablecoin token contract to register in the bitmap
    function register(address stablecoin) external onlyOwner returns (uint8 newKey) {
        return _register(stablecoin);
    }

    function _register(address stablecoin) internal returns (uint8 newKey) {
        require(_keyOf[stablecoin] == 0, "STABLECOIN_ALREADY_REGISTERED");
        newKey = ++keyCounter; // increment then set, first key starts at 1 to leave 0 empty for null value
        _keyOf[stablecoin] = newKey;
        _stablecoinOf[newKey] = stablecoin;
        emit Register(stablecoin, newKey);
    }

    /// @dev Function to check the bitmap key for a stablecoin
    /// @param stablecoin The stablecoin address to query against the _keyOf storage mapping
    function keyOf(address stablecoin) public view returns (uint8 key) {
        key = _keyOf[stablecoin];
        require(key > 0, "STABLECOIN_NOT_REGISTERED");
    }

    /// @dev Function to get the stablecoin contract address for a specific bitmap key
    /// @param key The bitmap key to query against the _stablecoinOf storage mapping
    function stablecoinOf(uint8 key) public view returns (address stablecoin) {
        stablecoin = _stablecoinOf[key];
        require(stablecoin != address(0), "KEY_NOT_REGISTERED");
    }

    /// @dev Function to get the entire set of stablecoins supported by this module
    function stablecoinOptions() public view returns (address[] memory stablecoins) {
        uint256 len = keyCounter;
        stablecoins = new address[](len);
        for (uint8 i; i < len; i++) {
            stablecoins[i] = _stablecoinOf[i + 1]; // key index starts at 1
        }
    }

    /*============
        SET UP
    ============*/

    /// @dev Function to set up and configure a new collection's purchase prices and payment options
    /// @param collection The new collection to configure
    /// @param price The price in a stablecoin currency for this collection's mints
    /// @param enabledCoins The stablecoin addresses to be supported for this collection's mints
    /// @param enablePermits A boolean to represent whether this collection will repeal or support grant functionality
    function setUp(address collection, uint128 price, address[] memory enabledCoins, bool enablePermits)
        public
        canSetUp(collection)
    {
        require(price > 0, "ZERO_PRICE");
        _parameters[collection] = Parameters(price, _enabledCoinsValue(enabledCoins));
        if (_disablePermits[collection] != !enablePermits) {
            _disablePermits[collection] = !enablePermits;
        }
        emit SetUp(collection, price, enabledCoins, enablePermits);
    }

    /// @dev note that this relies on the canSetUp modifier being used in the public function
    function setUp(uint128 price, address[] memory enabledCoins, bool enablePermits) external {
        setUp(msg.sender, price, enabledCoins, enablePermits);
    }

    /*===================
        ENABLED COINS
    ===================*/

    /// @dev Function to get the enabled stablecoins of a collection
    /// @param collection The collection for which stablecoins are enabled
    function enabledCoinsOf(address collection) external view returns (address[] memory stablecoins) {
        // cache state to save reads
        uint256 len = keyCounter;
        bytes16 enabledCoins = _parameters[collection].enabledCoins;
        // construct array of max length, front-packed
        address[] memory fullArray = new address[](len);
        uint8 enabledCount;
        for (uint256 i; i < len; i++) {
            uint8 key = uint8(i + 1);
            if (enabledCoins & bytes16(uint128(1 << key)) > 0) {
                fullArray[enabledCount] = _stablecoinOf[key];
                enabledCount++;
            }
        }
        // trim down array size using enabledCount
        stablecoins = new address[](enabledCount);
        for (uint256 i; i < enabledCount; i++) {
            stablecoins[i] = fullArray[i];
        }
    }

    /// @dev Function to check if a specific stablecoin is enabled for a collection. Reverts for unregistered stablecoins.
    /// @param collection The collection to check against _collectionConfig storage mapping
    /// @param stablecoin The stablecoin being queried against the provided collection address
    function stablecoinEnabled(address collection, address stablecoin) external view returns (bool) {
        return _stablecoinEnabled(_parameters[collection].enabledCoins, stablecoin);
    }

    function _stablecoinEnabled(bytes16 enabledCoins, address stablecoin) internal view returns (bool) {
        return (enabledCoins & _keyBitOf(stablecoin)) > 0;
    }

    /// @dev Internal function to process an array of stablecoin addresses into a packed 16 byte bitmap of their corresponding keys
    /// @param stablecoins The stablecoin addresses to process
    function _enabledCoinsValue(address[] memory stablecoins) internal view returns (bytes16 value) {
        for (uint256 i; i < stablecoins.length; i++) {
            value |= _keyBitOf(stablecoins[i]);
        }
    }

    function _keyBitOf(address stablecoin) internal view returns (bytes16) {
        return bytes16(uint128(1 << keyOf(stablecoin)));
    }

    /*====================
        PURCHASE PRICE
    ====================*/

    /// @dev Function to get the configuration of a collection, incl stablecoin price and enabled stablecoins
    /// @param collection The collection to query against _parameters storage mapping
    function priceOf(address collection) external view returns (uint128 price) {
        price = _parameters[collection].price;
        require(price > 0, "NO_PRICE");
    }

    /// @dev Function to handle decimal precision variation between stablecoin implementations
    /// @param price The desired stablecoin price to be checked against ERC20 decimals() and formatted if needed
    /// @param stablecoin The stablecoin implementation to which to conform
    function mintPriceToStablecoinAmount(uint256 price, address stablecoin) public view returns (uint256) {
        uint256 stablecoinDecimals = IERC20Metadata(stablecoin).decimals();
        if (stablecoinDecimals == decimals) {
            return price;
        } else if (stablecoinDecimals > decimals) {
            // pad zeros to input quantity
            return price * 10 ** (stablecoinDecimals - decimals);
        } else {
            // reduce price precision
            uint256 precisionLoss = 10 ** (decimals - stablecoinDecimals);
            uint256 trimmedPrice = price / precisionLoss;
            if (price % precisionLoss > 0) {
                // if remainder, round up as seller protection
                return trimmedPrice + 1;
            } else {
                // no remainder value lost, return trimmed price as is
                return trimmedPrice;
            }
        }
    }

    /*==========
        MINT
    ==========*/

    /// @dev Function to mint a single collection token to the caller, ie a user
    function mint(address collection, address paymentCoin) external whenNotPaused {
        _batchMint(collection, paymentCoin, msg.sender, 1);
    }

    /// @dev Function to mint a single collection token to a specified recipient
    function mintTo(address collection, address paymentCoin, address recipient) external whenNotPaused {
        _batchMint(collection, paymentCoin, recipient, 1);
    }

    /// @dev Function to mint collection tokens in batches to the caller, ie a user
    /// @notice returned tokenId range is inclusive
    function batchMint(address collection, address paymentCoin, uint256 quantity) external whenNotPaused {
        _batchMint(collection, paymentCoin, msg.sender, quantity);
    }

    /// @dev Function to mint collection tokens in batches to a specified recipient
    /// @notice returned tokenId range is inclusive
    function batchMintTo(address collection, address paymentCoin, address recipient, uint256 quantity)
        external
        whenNotPaused
    {
        _batchMint(collection, paymentCoin, recipient, quantity);
    }

    /// @dev Internal function to which all external user + client facing mint functions are routed.
    /// @param collection The token collection to mint from
    /// @param paymentCoin The stablecoin address being used for payment
    /// @param recipient The recipient of successfully minted tokens
    /// @param quantity The quantity of tokens to mint
    /// @notice returned tokenId range is inclusive
    function _batchMint(address collection, address paymentCoin, address recipient, uint256 quantity)
        internal
        usePermits(_encodePermitContext(collection))
    {
        require(quantity > 0, "ZERO_AMOUNT");

        Parameters memory params = _parameters[collection];
        require(_stablecoinEnabled(params.enabledCoins, paymentCoin), "STABLECOIN_NOT_ENABLED");
        // get decimals-formatted price
        uint256 formattedPrice = mintPriceToStablecoinAmount(params.price, paymentCoin);

        // prevent accidentally unset payoutAddress
        address payoutAddress = PayoutAddressExtension(collection).payoutAddress();
        require(payoutAddress != address(0), "MISSING_PAYOUT_ADDRESS");

        // calculate fee, require fee sent to this contract, transfer collection's revenue to payoutAddress
        _collectFeeAndForwardCollectionRevenue(
            collection, payoutAddress, paymentCoin, recipient, quantity, formattedPrice
        );

        // mint NFTs
        IERC721Rails(collection).mintTo(recipient, quantity);
    }
    /*===========
        PAUSE
    ===========*/

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /*============
        PERMIT
    ============*/

    function _encodePermitContext(address collection) internal pure returns (bytes memory context) {
        return abi.encode(collection);
    }

    function _decodePermitContext(bytes memory context) internal pure returns (address collection) {
        return abi.decode(context, (address));
    }

    function signerCanPermit(address signer, bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return IPermissions(collection).hasPermission(Operations.MINT_PERMIT, signer);
    }

    function requirePermits(bytes memory context) public view override returns (bool) {
        address collection = _decodePermitContext(context);
        return !_disablePermits[collection];
    }
}

