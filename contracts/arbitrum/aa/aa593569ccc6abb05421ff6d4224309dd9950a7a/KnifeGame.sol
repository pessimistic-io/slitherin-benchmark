// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "./Ownable.sol";
import {ERC20} from "./ERC20.sol";
import {ERC721Holder} from "./ERC721Holder.sol";

import {toWadUnsafe, toDaysWadUnsafe} from "./SignedWadMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {LibGOO} from "./LibGOO.sol";

import {LVRGDA} from "./LVRGDA.sol";
import {KnifeNFT, SpyNFT, GooBalanceUpdateType} from "./NFT.sol";

/// @title Knife Game Logic
/// @author Libevm <libevm32@gmail.com>
/// @notice A funny game
contract KnifeGame is ERC721Holder {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the SPY NFT contract
    SpyNFT public immutable spyNFT;

    /// @notice The address of the Knives NFT contract
    KnifeNFT public immutable knifeNFT;

    /// @notice Prices curves for the NFTs
    LVRGDA public spyLVRGDA;
    LVRGDA public knifeLVRGDA;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Safe multisig arbi.knifegamexyz.eth
    address public constant MULTISIG = 0x72aabF4Efa18e86C71CD9d53b23A243A0CcFA5C4;

    /// @notice arbi.kgtreasury.eth
    address public constant SHOUTS_FUNDS_RECIPIENT = 0x6690f96C2D499cfE9ee0D0a006c60476453cd917;

    /// @notice Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Delay for knives
    uint256 public constant KNIFE_LAUNCH_DELAY = 24 hours;

    /// @notice How much $$ per user
    uint256 public constant PURCHASE_SPY_ETH_PRICE = 0.02 ether;

    /// @notice Maximum batch size
    uint256 public constant MAX_BATCH_SIZE = 10;

    /*//////////////////////////////////////////////////////////////
                            GAME VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp for the start of minting.
    uint256 public immutable gameStart;
    uint256 public immutable purchasedStartTime;

    /// @notice Number of spies minted from moo.
    uint128 public spiesMintedFromMoo;

    /// @notice Number of knives minted from moo.
    uint128 public knivesMintedFromMoo;

    /// @notice Number of purchases per day (after game)
    mapping(address => mapping(uint256 => uint256)) public userPurchasesOnDay;

    /// @notice Have the users purchased pre-game, and when
    mapping(address => uint256) public userPrepuchasedTimestamp;

    /// @notice Have the users claimed free MOO tokens pre-game
    mapping(address => bool) public hasUserClaimedFreeMooTokens;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TooEarly();
    error TooLate();
    error TooPoor();
    error DumbMove();

    error NotOwner();
    error NoWhales();

    error LazyDev();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Shouted(address indexed sender, string message);

    event SpyPurchasedETH(address indexed recipient);
    event SpyPurchasedMoo(address indexed recipient, uint256 indexed amount);

    event SpyKilled(address indexed hitman, address indexed victim, uint256 amount);

    event KnifePurchased(address indexed recipient, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _purchaseStart, uint256 _gameStart, address _spyNft, address _knifeNFT) {
        // Time
        purchasedStartTime = _purchaseStart;
        gameStart = _gameStart;

        // NFTs
        spyNFT = SpyNFT(_spyNft);
        knifeNFT = KnifeNFT(_knifeNFT);

        // Price curves
        spyLVRGDA = new LVRGDA(
            6.9e18, // Target price
            0.5e18, // Price decay percent
            toWadUnsafe(4000),
            0.3e18 // Time scale.
        );
        knifeLVRGDA = new LVRGDA(
            4.2000e18, // Target price
            0.6e18, // Price decay percent
            toWadUnsafe(8000), // Max number of knives
            0.22e18 // Time scale.
        );
    }

    /*//////////////////////////////////////////////////////////////
                          Permissioned
    //////////////////////////////////////////////////////////////*/

    function updateSpyVRGDA(int256 _targetPrice, int256 _priceDecayPercent, uint256 _maxAmount, int256 _timeScale)
        public
    {
        // Only multisig can change
        if (msg.sender != MULTISIG) revert NotOwner();

        // Can't change after game starts
        if (block.timestamp >= gameStart) revert TooLate();

        spyLVRGDA = new LVRGDA(
            _targetPrice,
            _priceDecayPercent,
            toWadUnsafe(_maxAmount),
            _timeScale
        );
    }

    function updateKnifeVRGDA(int256 _targetPrice, int256 _priceDecayPercent, uint256 _maxAmount, int256 _timeScale)
        public
    {
        // Only multisig can change
        if (msg.sender != MULTISIG) revert NotOwner();

        // Can't change after game starts
        if (block.timestamp > gameStart) revert TooLate();

        knifeLVRGDA = new LVRGDA(
            _targetPrice,
            _priceDecayPercent,
            toWadUnsafe(_maxAmount),
            _timeScale
        );
    }

    /*//////////////////////////////////////////////////////////////
                          Minting Logic
    //////////////////////////////////////////////////////////////*/

    function claimFreeMoo(address user) external {
        // Only claimable after game starts
        if (block.timestamp < gameStart) revert TooEarly();

        // Only users who have pre purchased can claim
        if (userPrepuchasedTimestamp[user] == 0) revert DumbMove();

        // Cannot claim twice
        if (hasUserClaimedFreeMooTokens[user]) revert DumbMove();

        hasUserClaimedFreeMooTokens[user] = true;

        // Free moo, more moo the earlier you buy in
        uint256 maxTimeDelta = gameStart - purchasedStartTime;
        uint256 userTimeDelta = gameStart - userPrepuchasedTimestamp[user];

        // Max gets 10
        uint256 mooToGet = userTimeDelta * 1e18 / maxTimeDelta * 10;

        spyNFT.updateUserGooBalance(user, mooToGet, GooBalanceUpdateType.INCREASE);
    }

    /// @notice Buys a spy with ETH, pricing exponentially increases once game starts
    function purchaseSpy(address user) external payable returns (uint256 spyId) {
        // Can only purchase spies after this time period
        if (block.timestamp < purchasedStartTime) revert TooEarly();

        // Don't be cheap
        if (msg.value < spyPriceETH(user)) revert TooPoor();

        MULTISIG.call{value: msg.value}("");

        spyId = _purchaseSpy(user);

        unchecked {
            emit SpyPurchasedETH(user);
        }
    }

    /// @notice Mints a Spy using Moolah
    function mintSpyFromMoolah(uint256 _maxPrice) external returns (uint256 spyId) {
        // If game has not begun, revert
        if (block.timestamp < gameStart) revert TooEarly();

        // No need to check if we're at MAX_MINTABLE
        // spyPrice() will revert once we reach it due to its
        // logistic nature. It will also revert prior to the mint start
        uint256 currentPrice = spyPrice();

        // If the current price is above the user's specified max, revert
        if (currentPrice > _maxPrice) revert TooPoor();

        // Decrement the user's goo by the ERC20 balance
        spyNFT.updateUserGooBalance(msg.sender, currentPrice, GooBalanceUpdateType.DECREASE);

        spyId = spyNFT.mint(msg.sender, block.timestamp > gameStart ? block.timestamp : gameStart);

        unchecked {
            ++spiesMintedFromMoo; // Overflow should be impossible due to the supply cap
            emit SpyPurchasedMoo(msg.sender, 1);
        }
    }

    /// @notice Mints many Spy with Moolah
    function mintSpiesFromMoolah(uint256 _batch, uint256 _maxPrice) external returns (uint256[] memory) {
        // No whales
        if (_batch > MAX_BATCH_SIZE) revert NoWhales();

        // If game has not begun, revert
        if (block.timestamp < gameStart) revert TooEarly();

        // Make sure we can afford it
        uint256 currentPrice = spyPriceBatch(_batch);
        if (currentPrice > _maxPrice) revert TooPoor();

        spyNFT.updateUserGooBalance(msg.sender, currentPrice, GooBalanceUpdateType.DECREASE);

        uint256[] memory spyIds = new uint256[](_batch);
        for (uint256 i = 0; i < _batch; i++) {
            spyIds[i] = spyNFT.mint(msg.sender, block.timestamp > gameStart ? block.timestamp : gameStart);
        }

        spiesMintedFromMoo += uint128(_batch);

        unchecked {
            emit SpyPurchasedMoo(msg.sender, _batch);
        }

        return spyIds;
    }

    /// @notice Mints a Knife using Moolah
    function mintKnifeFromMoolah(uint256 _maxPrice) external returns (uint256 knifeId) {
        // If game has not begun, revert
        if (block.timestamp < gameStart) revert TooEarly();

        // No need to check if we're at MAX_MINTABLE
        // spyPrice() will revert once we reach it due to its
        // logistic nature. It will also revert prior to the mint start
        uint256 currentPrice = knifePrice();

        // If the current price is above the user's specified max, revert
        if (currentPrice > _maxPrice) revert TooPoor();

        // Decrement the user's goo by the virtual balance or ERC20 balance
        spyNFT.updateUserGooBalance(msg.sender, currentPrice, GooBalanceUpdateType.DECREASE);

        knifeId = knifeNFT.mint(msg.sender);

        unchecked {
            ++knivesMintedFromMoo; // Overflow should be impossible due to the supply cap
            emit KnifePurchased(msg.sender, 1);
        }
    }

    /// @notice Mints many knives using moolah
    function mintKnivesFromMoolah(uint256 _batch, uint256 _maxPrice) external returns (uint256[] memory) {
        // No whales
        if (_batch > MAX_BATCH_SIZE) revert NoWhales();

        // If game has not begun, revert
        if (block.timestamp < gameStart) revert TooEarly();

        // Make sure we can afford it
        uint256 currentPrice = knifePriceBatch(_batch);
        if (currentPrice > _maxPrice) revert TooPoor();

        spyNFT.updateUserGooBalance(msg.sender, currentPrice, GooBalanceUpdateType.DECREASE);

        uint256[] memory knifeIds = new uint256[](_batch);
        for (uint256 i = 0; i < _batch; i++) {
            knifeIds[i] = knifeNFT.mint(msg.sender);
        }

        knivesMintedFromMoo += uint128(_batch);

        unchecked {
            emit KnifePurchased(msg.sender, _batch);
        }

        return knifeIds;
    }

    /*//////////////////////////////////////////////////////////////
                          Pricing Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Spy pricing in terms of ETH
    /// @dev Allows people to buy Spies after the game has started
    ///      but disincentivies them to do so as it gets exponentially more expensive once the game starts
    /// @return Current price of a spy in terms of ETH for a particular user
    function spyPriceETH(address _user) public view returns (uint256) {
        // If the game hasn't started, its a flat rate
        if (block.timestamp < gameStart) return PURCHASE_SPY_ETH_PRICE;

        // How many days since game started, and how many spies have user *purchased* on this day
        uint256 daysSinceGameStarted = uint256(toDaysWadUnsafe(block.timestamp - gameStart) / 1e18);
        uint256 userPurchased = userPurchasesOnDay[_user][daysSinceGameStarted];

        // Magic algorithm
        uint256 priceIncrease = 0;
        for (uint256 i = 0; i < userPurchased; i++) {
            if (priceIncrease == 0) {
                priceIncrease = PURCHASE_SPY_ETH_PRICE;
            }

            priceIncrease = priceIncrease * 2;
        }

        return PURCHASE_SPY_ETH_PRICE + priceIncrease;
    }

    /// @notice Spy pricing in terms of moolah.
    /// @dev Will revert if called before minting starts
    /// or after all gobblers have been minted via VRGDA.
    function spyPrice() public view returns (uint256) {
        // We need checked math here to cause underflow
        // before minting has begun, preventing mints.
        uint256 timeSinceStart = block.timestamp - gameStart;
        return spyLVRGDA.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), spiesMintedFromMoo);
    }

    /// @notice Batch spy pricing in terms of moolah.
    /// @dev Will revert if called before minting starts
    /// or after all gobblers have been minted via VRGDA.
    function spyPriceBatch(uint256 _batch) public view returns (uint256) {
        uint256 acc = 0;
        uint256 minted = spiesMintedFromMoo;

        uint256 timeSinceStart = block.timestamp - gameStart;
        for (uint256 i = 0; i < _batch; i++) {
            acc += spyLVRGDA.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), minted + i);
        }
        return acc;
    }

    /// @notice Knife pricing in terms of moolah.
    /// @dev Will revert if called before minting starts
    /// or after all gobblers have been minted via VRGDA.
    function knifePrice() public view returns (uint256) {
        // We need checked math here to cause underflow
        // before minting has begun, preventing mints.
        uint256 timeSinceStart = block.timestamp - (gameStart + KNIFE_LAUNCH_DELAY);
        return knifeLVRGDA.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), knivesMintedFromMoo);
    }

    /// @notice Batch spy pricing in terms of moolah.
    /// @dev Will revert if called before minting starts
    /// or after all gobblers have been minted via VRGDA.
    function knifePriceBatch(uint256 _batch) public view returns (uint256) {
        uint256 acc = 0;
        uint256 minted = knivesMintedFromMoo;

        uint256 timeSinceStart = block.timestamp - (gameStart + KNIFE_LAUNCH_DELAY);
        for (uint256 i = 0; i < _batch; i++) {
            acc += knifeLVRGDA.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), minted + i);
        }
        return acc;
    }

    /*//////////////////////////////////////////////////////////////
                          Game Logic
    //////////////////////////////////////////////////////////////*/

    function killSpy(uint256 knifeId, uint256 spyId) public {
        (address hitman, address victim) = _killSpy(knifeId, spyId);
        emit SpyKilled(hitman, victim, 1);
    }

    function killSpyBatch(uint256[] memory _knifeIds, uint256[] memory _spyIds) public {
        if (_knifeIds.length != _spyIds.length) revert DumbMove();
        if (_knifeIds.length > MAX_BATCH_SIZE) revert DumbMove();

        address hitman;
        address prevVictim;
        address curVictim;

        (hitman, prevVictim) = _killSpy(_knifeIds[0], _spyIds[0]);
        for (uint256 i = 1; i < _knifeIds.length; i++) {
            (, curVictim) = _killSpy(_knifeIds[i], _spyIds[i]);

            // Make sure all spyIds belong to the same owner so event emitting is easier
            // ROFL LMAO
            if (curVictim != prevVictim) revert LazyDev();
        }

        emit SpyKilled(hitman, prevVictim, _knifeIds.length);
    }

    // For world chat functionality
    function shout(string calldata message) external {
        if (bytes(message).length > 256) {
            emit Shouted(msg.sender, string(message[:256]));
        } else {
            emit Shouted(msg.sender, message);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          Internal
    //////////////////////////////////////////////////////////////*/

    function _purchaseSpy(address user) internal returns (uint256 spyId) {
        // Only can purchase 1 spy pre game start
        if (block.timestamp < gameStart) {
            // Revert if user has purchased
            if (userPrepuchasedTimestamp[user] > 0) revert NoWhales();

            // Set purchased
            userPrepuchasedTimestamp[user] = block.timestamp;
        } else if (block.timestamp >= gameStart) {
            // Add purchase count
            userPurchasesOnDay[user][uint256(toDaysWadUnsafe(block.timestamp - gameStart) / 1e18)]++;
        }

        spyId = spyNFT.mint(user, block.timestamp > gameStart ? block.timestamp : gameStart);
    }

    function _killSpy(uint256 _knifeId, uint256 _spyId) internal returns (address knifeOwner, address spyOwner) {
        // Get the owners
        knifeOwner = knifeNFT.ownerOf(_knifeId);
        spyOwner = spyNFT.ownerOf(_spyId);

        // Make sure user owns the knife
        if (knifeOwner != msg.sender) revert NotOwner();

        // Cannot kill burn address
        if (spyOwner == BURN_ADDRESS) revert DumbMove();

        // Literally retarded
        if (knifeOwner == spyOwner) revert DumbMove();

        knifeNFT.sudoTransferFrom(msg.sender, BURN_ADDRESS, _knifeId);

        address victim = spyNFT.ownerOf(_spyId);
        spyNFT.sudoTransferFrom(victim, BURN_ADDRESS, _spyId);
    }
}

