//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

// Libraries
import {Counters} from "./Counters.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {Math} from "./Math.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {AccessControl} from "./AccessControl.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {IAssetSwapper} from "./IAssetSwapper.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

/// @title Atlantic Straddles
/// @author Dopex
/// @notice - Accept stable deposits
/// - Deposits during an epoch will be for the next epoch
/// - Stables are used as collateral to sell ATM put options for the underlying
/// - n day epochs, deposits auto-rollover unless deactivated
/// - Withdrawal considers performance of pool since deposit
/// - On purchase of an Atlantic straddle, use 50% of the collateral locked in the PUT to purchase underlying asset
/// - At expiry, settle by selling purchased underlying asset to return AP collateral
contract AtlanticStraddle is
    ReentrancyGuard,
    ERC721,
    ERC721Enumerable,
    AccessControl,
    Pausable,
    ContractWhitelist
{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    /// @dev Token ID counter for write positions
    Counters.Counter private _tokenIdCounter;

    /// @dev Current epoch. 0-indexed
    uint256 public currentEpoch;

    /// @dev Managar Role
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev Contract addresses
    Addresses public addresses;

    /// @dev Total deposits for epoch (epoch => EpochData)
    mapping(uint256 => EpochData) public epochData;

    /// @dev Data for premium and funding collections for an epoch (epoch => EpochCollectionsData)
    mapping(uint256 => EpochCollectionsData) public epochCollectionsData;

    /// @dev Is vault ready for the epoch i.e can purchases begin (epoch => isVaultReady)
    mapping(uint256 => bool) public isVaultReady;

    /// @dev Toggled to true after an epoch has been marked pre-expired (epoch => isEpochPreExpired)
    mapping(uint256 => bool) public isEpochPreExpired;

    /// @dev Toggled to true after an epoch has been marked expired (epoch => isEpochExpired)
    mapping(uint256 => bool) public isEpochExpired;

    /// @dev Write positions (tokenId => WritePosition)
    mapping(uint256 => WritePosition) public writePositions;

    /// @dev Straddle positions (tokenId => StraddlePosition)
    mapping(uint256 => StraddlePosition) public straddlePositions;

    /// @dev Percentage precision
    uint256 public constant PERCENT_PRECISION = 1e6;

    /// @dev USDC decimals
    uint256 public constant USDC_DECIMALS = 1e6;

    /// @dev Min purchase 0.01 to prevent spam
    uint256 public constant MIN_PURCHASE_AMOUNT = 1e16;

    /// @dev Min deposit amount 1 usd to prevent spam
    uint256 public constant MIN_DEPOSIT_AMOUNT = USDC_DECIMALS;

    /// @dev Seconds a year
    uint256 internal constant SECONDS_A_YEAR = 365 days;

    /// @dev Purchase fee percent
    uint256 public purchaseFeePercent = 15e4;

    /// @dev Delegation fee
    uint256 public maxDelegationFee = USDC_DECIMALS;

    /// @dev Settlement fee percent
    uint256 public settlementFeePercent = 1e5;

    /// @dev AP funding percent
    uint256 public apFundingPercent = 36 * PERCENT_PRECISION;

    /// @dev Fee percent charged to owner, default to 0.1%
    uint256 public delegationFeePercent = PERCENT_PRECISION / 10;

    /// @dev Purchase time limit variable to prevent last min buyouts
    uint256 public blackoutPeriodBeforeExpiry = 4 hours;

    /// @dev PnL slippage percent
    uint256 public pnlSlippagePercent = 5e5;

    /// @dev The decimal precision for amount of options * strike price (or price)
    uint256 internal constant AMOUNT_PRICE_TO_USDC_DECIMALS =
        (1e18 * 1e8) / 1e6;

    struct Addresses {
        // USDC token (1e6 precision)
        address usd;
        // Underlying token
        address underlying;
        // Asset Swapper
        address assetSwapper;
        // Price Oracle
        address priceOracle;
        // Volatility Oracle
        address volatilityOracle;
        // Option Pricing
        address optionPricing;
        // Fee Distributor
        address feeDistributor;
    }

    struct EpochData {
        // Start time
        uint256 startTime;
        // Expiry time
        uint256 expiry;
        // Total USD deposits
        uint256 usdDeposits;
        // Active USD deposits (used for writing)
        uint256 activeUsdDeposits;
        // Settlement Price
        uint256 settlementPrice;
        // Percentage of total settlement executed
        uint256 settlementPercentage;
        // Amount of underlying assets purchased
        uint256 underlyingPurchased;
    }

    struct EpochCollectionsData {
        // Total premiums collected for USD deposits
        uint256 usdPremiums;
        // Total funding collected for USD deposits
        uint256 usdFunding;
        // Total amount of straddles sold
        uint256 totalSold;
        // Number of "live" straddles per epoch
        uint256 straddleCounter;
        // Final usd balance before withdraw
        uint256 finalUsdBalanceBeforeWithdaw;
    }

    struct WritePosition {
        // Epoch #
        uint256 epoch;
        // USD deposits
        uint256 usdDeposit;
        // Whether deposit should be rolled over to the next epoch
        bool rollover;
    }

    struct StraddlePosition {
        // Epoch #
        uint256 epoch;
        // Amount
        uint256 amount;
        // AP Strike
        uint256 apStrike;
        // Underlying purchased for this straddle
        uint256 underlyingPurchased;
    }

    event Bootstrap(uint256 epoch);

    event Deposit(
        uint256 epoch,
        uint256 amount,
        bool rollover,
        address user,
        address sender,
        uint256 tokenId
    );

    event Purchase(
        uint256 epoch,
        address user,
        uint256 straddleId,
        uint256 cost
    );

    event Settle(
        uint256 epoch,
        address indexed sender,
        address indexed owner,
        uint256 id,
        uint256 pnl
    );

    event Withdraw(
        uint256 epoch,
        address indexed sender,
        uint256 id,
        uint256 pnl
    );

    event ToggleRollover(uint256 id, bool rollover);

    event EpochExpired(address caller);

    event EpochPreExpired(address caller);

    event SetAddresses(Addresses addresses);

    event SetBlackoutPeriod(uint256 period);

    event SetApFunding(uint256 apFunding);

    event SetPnlSlippagePercent(uint256 pnlSlippagePercent);

    event SetFees(
        uint256 purchaseFeePercent,
        uint256 settlementFeePercent,
        uint256 delegationFeePercent,
        uint256 maxDelegationFee
    );

    event SetAssetSwapperAllowance(address token, uint256 value, bool increase);

    /*==== CONSTRUCTOR ====*/

    constructor(
        string memory _name,
        string memory _symbol,
        Addresses memory _addresses
    ) ERC721(_name, _symbol) {
        addresses = _addresses;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
    }

    /*==== USER METHODS ====*/

    /// @dev Deposit for next epoch
    /// @param amount Amount to deposit
    /// @param shouldRollover Should the deposit be rolled over
    /// @param user User address
    /// @return tokenId Write position token ID
    function deposit(
        uint256 amount,
        bool shouldRollover,
        address user
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        _isEligibleSender();
        require(amount > MIN_DEPOSIT_AMOUNT, "Invalid amount");

        uint256 nextEpoch = currentEpoch + 1;

        epochData[nextEpoch].usdDeposits += amount;
        epochCollectionsData[nextEpoch].finalUsdBalanceBeforeWithdaw += amount;

        tokenId = _mintPositionToken(user);

        writePositions[tokenId] = WritePosition({
            epoch: nextEpoch,
            usdDeposit: amount,
            rollover: shouldRollover
        });

        IERC20(addresses.usd).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Deposit(
            nextEpoch,
            amount,
            shouldRollover,
            user,
            msg.sender,
            tokenId
        );
    }

    /// @dev Rolls over a deposit to the next epoch. Anyone can call this for write positions with `rollover` enabled
    /// Call this prior to bootstrapping to a new epoch or it will roll over to epoch n + 2
    /// @param id Write position token ID
    /// @return tokenId Rolled over write position token ID
    function rollover(uint256 id)
        public
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        _isEligibleSender();
        WritePosition memory writePos = writePositions[id];

        require(writePos.rollover, "Rollover not authorized");
        require(writePos.epoch != 0, "Invalid write position");
        require(isEpochExpired[writePos.epoch], "Epoch has not expired");

        uint256 depositPlusPnl = calculateWritePositionPnl(id);

        address user = ownerOf(id);

        _burn(id);

        require(depositPlusPnl != 0, "Write position pnl is 0");

        uint256 delegationFee;

        // If the owner of the position is not the sender, collect rollover delegation fees
        if (user != msg.sender) {
            delegationFee =
                (depositPlusPnl * delegationFeePercent) /
                (PERCENT_PRECISION * 100);
            delegationFee = Math.min(delegationFee, maxDelegationFee);
        }

        depositPlusPnl -= delegationFee;

        emit Withdraw(writePos.epoch, user, id, depositPlusPnl);

        uint256 nextEpoch = currentEpoch + 1;

        epochData[nextEpoch].usdDeposits += depositPlusPnl;
        epochCollectionsData[nextEpoch]
            .finalUsdBalanceBeforeWithdaw += depositPlusPnl;

        tokenId = _mintPositionToken(user);

        writePositions[tokenId] = WritePosition({
            epoch: nextEpoch,
            usdDeposit: depositPlusPnl,
            rollover: true
        });

        IERC20(addresses.usd).safeTransfer(msg.sender, delegationFee);

        emit Deposit(nextEpoch, depositPlusPnl, true, user, user, tokenId);
    }

    /// @dev Rollover for multiple ids
    /// @param ids Write position token IDs
    /// @return tokenIds Rolled over write position token IDs
    function multirollover(uint256[] memory ids)
        external
        returns (uint256[] memory tokenIds)
    {
        uint256 idsLength = ids.length;
        tokenIds = new uint256[](idsLength);
        for (uint256 i; i < idsLength; ) {
            tokenIds[i] = rollover(ids[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Toggle rollover for a write position
    /// @param id Write position token ID
    function toggleRollover(uint256 id) external whenNotPaused nonReentrant {
        _isEligibleSender();
        require(ownerOf(id) == msg.sender, "Invalid owner");
        require(writePositions[id].epoch != 0, "Invalid position");
        writePositions[id].rollover = !writePositions[id].rollover;
        emit ToggleRollover(id, writePositions[id].rollover);
    }

    /// @dev Withdraw write positions after strikes are settled
    /// @param id ID of write position
    /// @return writePositionPnl of write position
    function withdraw(uint256 id)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 writePositionPnl)
    {
        _isEligibleSender();
        require(ownerOf(id) == msg.sender, "Invalid owner");

        WritePosition memory writePos = writePositions[id];

        require(writePos.epoch != 0, "Invalid write position");
        require(isEpochExpired[writePos.epoch], "Settlements not done");

        writePositionPnl = calculateWritePositionPnl(id);

        _burn(id);

        require(writePositionPnl != 0, "Write position pnl is 0");

        IERC20(addresses.usd).safeTransfer(msg.sender, writePositionPnl);

        emit Withdraw(writePos.epoch, msg.sender, id, writePositionPnl);
    }

    /// @dev Purchase a straddle
    /// @param amount Approx. amount of straddles to purchase (10 ** 18)
    /// @param swapperId Swapper ID of the swap method to use
    /// @param minAmountOut Min amount out for the underlying purchased
    /// @param user Address to purchase straddles for
    /// @return tokenId Straddle position token ID
    function purchase(
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId,
        address user
    )
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256 tokenId,
            uint256 protocolFee,
            uint256 straddleCost
        )
    {
        _isEligibleSender();
        require(currentEpoch > 0, "Invalid epoch");
        require(amount > MIN_PURCHASE_AMOUNT, "Invalid amount");
        require(
            block.timestamp <
                epochData[currentEpoch].expiry - blackoutPeriodBeforeExpiry,
            "Cannot purchase during blackout period"
        );

        uint256 currentPrice = getUnderlyingPrice();
        uint256 timeToExpiry = epochData[currentEpoch].expiry - block.timestamp;

        require(
            epochData[currentEpoch].usdDeposits -
                (epochData[currentEpoch].activeUsdDeposits /
                    AMOUNT_PRICE_TO_USDC_DECIMALS) >=
                (currentPrice * amount) / AMOUNT_PRICE_TO_USDC_DECIMALS,
            "Not enough AP liquidity available"
        );

        // Swap half of AP to underlying
        uint256 underlyingPurchased = _swapToUnderlying(
            ((currentPrice * amount) / 2) / AMOUNT_PRICE_TO_USDC_DECIMALS,
            minAmountOut,
            swapperId
        );
        epochCollectionsData[currentEpoch].finalUsdBalanceBeforeWithdaw -=
            ((currentPrice * amount) / 2) /
            AMOUNT_PRICE_TO_USDC_DECIMALS;

        uint256 swapPrice = (currentPrice * amount) / (underlyingPurchased * 2);

        epochData[currentEpoch].underlyingPurchased += underlyingPurchased;

        // Deposits
        epochData[currentEpoch].activeUsdDeposits +=
            swapPrice *
            (underlyingPurchased * 2);

        uint256 apPremium = calculatePremium(
            true,
            swapPrice,
            swapPrice,
            underlyingPurchased * 2,
            epochData[currentEpoch].expiry
        );

        uint256 apFunding = calculateApFunding(
            swapPrice,
            underlyingPurchased * 2,
            timeToExpiry
        );

        // Collections
        epochCollectionsData[currentEpoch].usdPremiums += apPremium;
        epochCollectionsData[currentEpoch].usdFunding += apFunding;
        epochCollectionsData[currentEpoch].totalSold += underlyingPurchased * 2;
        epochCollectionsData[currentEpoch].straddleCounter += 1;

        // Mint straddle position token
        tokenId = _mintPositionToken(user);
        straddlePositions[tokenId] = StraddlePosition({
            epoch: currentEpoch,
            amount: underlyingPurchased * 2,
            apStrike: swapPrice,
            underlyingPurchased: underlyingPurchased
        });

        protocolFee =
            (amount * currentPrice * purchaseFeePercent) /
            (PERCENT_PRECISION * AMOUNT_PRICE_TO_USDC_DECIMALS * 100);

        straddleCost = ((apPremium + apFunding) /
            AMOUNT_PRICE_TO_USDC_DECIMALS);

        IERC20(addresses.usd).safeTransferFrom(
            msg.sender,
            address(this),
            straddleCost + protocolFee
        );

        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );

        epochCollectionsData[currentEpoch]
            .finalUsdBalanceBeforeWithdaw += ((apPremium + apFunding) /
            AMOUNT_PRICE_TO_USDC_DECIMALS);

        emit Purchase(currentEpoch, user, tokenId, apPremium + apFunding);
    }

    /// @dev Settles a purchased option
    /// @param id ID of straddle position
    function settle(uint256 id)
        public
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _isEligibleSender();

        StraddlePosition memory sp = straddlePositions[id];
        require(sp.epoch != 0, "Invalid straddle position");
        require(isEpochPreExpired[sp.epoch], "Epoch has not pre-expired");

        uint256 buyerPnl = calculateStraddlePositionPnl(id);
        address owner = ownerOf(id);

        _burn(id);

        require(buyerPnl != 0, "buyerPnl cannot be 0");

        uint256 protocolFee = (buyerPnl * settlementFeePercent) /
            (PERCENT_PRECISION * 100);
        uint256 delegationFee;

        // If owner did not settle, collect settlement fees
        if (owner != msg.sender) {
            delegationFee =
                (buyerPnl * delegationFeePercent) /
                (PERCENT_PRECISION * 100);
            delegationFee = Math.min(delegationFee, maxDelegationFee);
        }

        buyerPnl -= (protocolFee + delegationFee);

        epochCollectionsData[sp.epoch].straddleCounter -= 1;
        epochCollectionsData[sp.epoch]
            .finalUsdBalanceBeforeWithdaw -= (buyerPnl +
            protocolFee +
            delegationFee);

        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );
        IERC20(addresses.usd).safeTransfer(owner, buyerPnl);
        IERC20(addresses.usd).safeTransfer(msg.sender, delegationFee);

        emit Settle(sp.epoch, msg.sender, owner, id, buyerPnl);

        return buyerPnl;
    }

    /// @dev Settle for multiple ids
    /// @param ids Straddle position token IDs
    /// @return pnls pnls
    function multisettle(uint256[] memory ids)
        external
        returns (uint256[] memory pnls)
    {
        uint256 idsLength = ids.length;
        pnls = new uint256[](idsLength);

        for (uint256 i; i < idsLength; ) {
            pnls[i] = settle(ids[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*==== INTERNAL METHODS ====*/

    /// @dev Internal function to mint a write position token
    /// @param to the address to mint the position to
    function _mintPositionToken(address to) private returns (uint256 tokenId) {
        tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /// @dev Internal function to swap USD to underlying tokens
    /// @param amount Amount of USD to swap
    /// @param minAmountOut The min amount out
    /// @param swapperId Swapper ID
    function _swapToUnderlying(
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) internal returns (uint256 underlyingPurchased) {
        underlyingPurchased = IAssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.usd,
            addresses.underlying,
            amount,
            minAmountOut,
            swapperId
        );
    }

    /// @dev Internal function to swap underlying tokens to USD
    /// @param amount Amount of underlying tokens to swap
    /// @param minAmountOut The min amount out
    /// @param swapperId Swapper ID
    function _swapFromUnderlying(
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) internal returns (uint256 usdObtained) {
        usdObtained = IAssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.underlying,
            addresses.usd,
            amount,
            minAmountOut,
            swapperId
        );
    }

    /*==== VIEWS ====*/

    /// @notice Returns the price of the underlying in USD in 1e8 precision
    function getUnderlyingPrice() public view returns (uint256) {
        return IPriceOracle(addresses.priceOracle).getUnderlyingPrice();
    }

    /// @notice Returns the volatility from the volatility oracle
    /// @param _strike Strike of the option
    function getVolatility(uint256 _strike) public view returns (uint256) {
        return
            IVolatilityOracle(addresses.volatilityOracle).getVolatility(
                _strike
            );
    }

    /// @notice Calculate premium for an option
    /// @param _isPut Is put option
    /// @param _price Price of the underlying
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options (1e18 precision)
    /// @param _expiry Expiry of the option
    /// @return premium in USD
    function calculatePremium(
        bool _isPut,
        uint256 _price,
        uint256 _strike,
        uint256 _amount,
        uint256 _expiry
    ) public view returns (uint256 premium) {
        premium = (IOptionPricing(addresses.optionPricing).getOptionPrice(
            _isPut,
            _expiry,
            _strike,
            _price,
            getVolatility(_strike)
        ) * _amount);
    }

    /// @notice Calculate premium for an option
    /// @param _price Price of the asset
    /// @param _amount Amount of options (1e18 precision)
    /// @param _timeToExpiry Time to expiry
    function calculateApFunding(
        uint256 _price,
        uint256 _amount,
        uint256 _timeToExpiry
    ) public view returns (uint256 funding) {
        funding =
            (((_price * apFundingPercent * _timeToExpiry * _amount) /
                (SECONDS_A_YEAR * PERCENT_PRECISION)) / 100) /
            2;
    }

    /// @notice Calculates the writer position pnl
    /// @param id the id of the write position
    /// @return writePositionPnl
    function calculateWritePositionPnl(uint256 id)
        public
        view
        returns (uint256 writePositionPnl)
    {
        WritePosition memory writePos = writePositions[id];
        require(writePos.epoch != 0, "Invalid write position");

        writePositionPnl =
            (writePos.usdDeposit *
                epochCollectionsData[writePos.epoch]
                    .finalUsdBalanceBeforeWithdaw) /
            epochData[writePos.epoch].usdDeposits;
    }

    /// @param id ID of straddle position
    /// @return buyerPnl positive pnl of buyer
    function calculateStraddlePositionPnl(uint256 id)
        public
        view
        returns (uint256 buyerPnl)
    {
        StraddlePosition memory sp = straddlePositions[id];

        require(sp.epoch != 0, "Invalid straddle position");

        uint256 settlementPrice = epochData[sp.epoch].settlementPrice;
        uint256 strikePrice = sp.apStrike;

        // straddle pnl = max(K - S, 0) + 0.5 * (S - K)
        // if K > S, get (K - S) - 0.5 * (K - S)
        if (strikePrice > settlementPrice) {
            buyerPnl = (strikePrice - settlementPrice) * sp.amount;
            buyerPnl -=
                (strikePrice - settlementPrice) *
                sp.underlyingPurchased;
        } else {
            // else get 0 + 0.5 * (S - K)
            buyerPnl +=
                (settlementPrice - strikePrice) *
                sp.underlyingPurchased;
        }

        buyerPnl /= AMOUNT_PRICE_TO_USDC_DECIMALS;
        buyerPnl -= (buyerPnl * pnlSlippagePercent) / (100 * PERCENT_PRECISION);
    }

    /// @notice Returns the tokenIds owned by a wallet (writePositions)
    /// @param owner wallet owner
    function writePositionsOfOwner(address owner)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 ownerTokenCount = balanceOf(owner);
        uint256 count;

        for (uint256 i; i < ownerTokenCount; ) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (writePositions[tokenId].epoch != 0) {
                ++count;
            }

            unchecked {
                ++i;
            }
        }

        tokenIds = new uint256[](count);
        uint256 start;
        uint256 idx;

        while (start < count) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, idx);
            if (writePositions[tokenId].epoch != 0) {
                tokenIds[start] = tokenId;
                ++start;
            }
            ++idx;
        }
    }

    /// @notice Returns the tokenIds owned by a wallet (straddlePositions)
    /// @param owner wallet owner
    function straddlePositionsOfOwner(address owner)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 ownerTokenCount = balanceOf(owner);
        uint256 count;

        for (uint256 i; i < ownerTokenCount; ) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (straddlePositions[tokenId].epoch != 0) {
                ++count;
            }

            unchecked {
                ++i;
            }
        }

        tokenIds = new uint256[](count);
        uint256 start;
        uint256 idx;

        while (start < count) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, idx);
            if (straddlePositions[tokenId].epoch != 0) {
                tokenIds[start] = tokenId;
                ++start;
            }
            ++idx;
        }
    }

    /*==== MANAGER METHODS ====*/

    /// @dev Bootstrap and start the next epoch for purchases
    /// @param expiry Expiry
    function bootstrap(uint256 expiry)
        external
        whenNotPaused
        onlyRole(MANAGER_ROLE)
        returns (bool)
    {
        uint256 nextEpoch = currentEpoch + 1;
        require(
            block.timestamp < expiry,
            "Expiry cannot be before current time"
        );
        require(
            currentEpoch == 0 || !isVaultReady[nextEpoch],
            "Cannot bootstrap when vault is ready"
        );
        if (currentEpoch > 0) {
            require(
                isEpochExpired[currentEpoch],
                "Cannot bootstrap before the current epoch was expired & settled"
            );
        }

        // Set expiry in epoch data
        epochData[nextEpoch].startTime = block.timestamp;
        epochData[nextEpoch].expiry = expiry;
        // Mark vault as ready for epoch
        isVaultReady[nextEpoch] = true;
        // Increase the current epoch
        currentEpoch = nextEpoch;

        emit Bootstrap(nextEpoch);

        return true;
    }

    /// @dev Swap a certain percentage of total purchased underlying
    /// @param percentage percentage of underlying to swap in 1e6
    /// @param minAmountOut the min amount out
    /// @param swapperId Swapper ID of the swap method to use with AssetSwapper
    function preExpireEpoch(
        uint256 percentage,
        uint256 minAmountOut,
        uint256 swapperId
    ) external whenNotPaused onlyRole(MANAGER_ROLE) returns (bool) {
        EpochData memory data = epochData[currentEpoch];
        require(percentage > 0, "Percentage cannot be 0");
        require(
            block.timestamp >= data.expiry,
            "Time is not past epoch expiry"
        );
        require(
            !isEpochPreExpired[currentEpoch],
            "Epoch was already pre-expired"
        );
        require(!isEpochExpired[currentEpoch], "Epoch was already expired");
        require(
            data.settlementPercentage + percentage <= (100 * PERCENT_PRECISION),
            "You cannot swap more than 100%"
        );

        // Swap all purchased underlying at current price
        uint256 underlyingToSwap = (data.underlyingPurchased * percentage) /
            (100 * PERCENT_PRECISION);

        uint256 normalizedSettlementPrice;

        if (underlyingToSwap > 0) {
            uint256 usdObtained = _swapFromUnderlying(
                underlyingToSwap,
                minAmountOut,
                swapperId
            );
            epochCollectionsData[currentEpoch]
                .finalUsdBalanceBeforeWithdaw += usdObtained;

            uint256 settlementPrice = (usdObtained *
                AMOUNT_PRICE_TO_USDC_DECIMALS) / underlyingToSwap;

            normalizedSettlementPrice =
                ((data.settlementPrice * data.settlementPercentage) +
                    (settlementPrice * percentage)) /
                (data.settlementPercentage + percentage);

            epochData[currentEpoch].settlementPercentage += percentage;
        } else {
            normalizedSettlementPrice = getUnderlyingPrice();

            epochData[currentEpoch].settlementPercentage =
                100 *
                PERCENT_PRECISION;
        }

        if (epochData[currentEpoch].settlementPrice == 0) {
            epochData[currentEpoch].settlementPrice = normalizedSettlementPrice;
        } else {
            epochData[currentEpoch].settlementPrice = Math.min(
                epochData[currentEpoch].settlementPrice,
                normalizedSettlementPrice
            );
        }

        if (
            epochData[currentEpoch].settlementPercentage >
            (99 * PERCENT_PRECISION)
        ) {
            isEpochPreExpired[currentEpoch] = true;
        }

        emit EpochPreExpired(msg.sender);

        return true;
    }

    /// @dev Expire epoch and set the settlement price
    function expireEpoch()
        external
        whenNotPaused
        onlyRole(MANAGER_ROLE)
        returns (bool expired)
    {
        require(
            block.timestamp >= epochData[currentEpoch].expiry,
            "Time is not past epoch expiry"
        );
        require(isEpochPreExpired[currentEpoch], "Epoch has not pre-expired");
        require(!isEpochExpired[currentEpoch], "Epoch was already expired");

        if (epochCollectionsData[currentEpoch].straddleCounter == 0) {
            isEpochExpired[currentEpoch] = true;
            expired = true;
        } else {
            revert("All settlements have not been processed");
        }

        emit EpochExpired(msg.sender);
    }

    /*==== ADMIN METHODS ====*/

    /// @notice Sets the addresses used in the contract
    /// @dev Can only be called by admin
    /// @param _addresses Addresses
    function setAddresses(Addresses memory _addresses)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        addresses = _addresses;
        emit SetAddresses(_addresses);
    }

    /// @notice Change blackout period before expiry
    /// @dev Can only be called by governance
    function setBlackoutPeriodBeforeExpiry(uint256 period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        require(period > 1 hours, "Blackout period must be more than 1 hour");
        blackoutPeriodBeforeExpiry = period;
        emit SetBlackoutPeriod(period);
        return true;
    }

    /// @notice Sets the apFunding
    /// @dev Can only be called by admin
    /// @param _apFundingPercent funding percentage number between 1% and 100%
    function setApFunding(uint256 _apFundingPercent)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_apFundingPercent > 0, "Funding rate must be greater than 0");
        apFundingPercent = _apFundingPercent;
        emit SetApFunding(_apFundingPercent);
    }

    /// @notice Sets the pnlSlippagePercent
    /// @dev Can only be called by admin
    /// @param _pnlSlippagePercent The pnl slippage percent
    function setPnlSlippagePercent(uint256 _pnlSlippagePercent)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_pnlSlippagePercent > 0, "Funding rate must be greater than 0");
        pnlSlippagePercent = _pnlSlippagePercent;
        emit SetPnlSlippagePercent(_pnlSlippagePercent);
    }

    /// @notice Sets the purchase/settlement fee percent
    /// @dev Can only be called by admin
    /// @param _purchaseFeePercent Purchase fee percent
    /// @param _settlementFeePercent Settlement fee percent
    /// @param _delegationFeePercent Delegation fee percent
    /// @param _maxDelegationFee Max delegation fee for settlements and rollovers
    function setFees(
        uint256 _purchaseFeePercent,
        uint256 _settlementFeePercent,
        uint256 _delegationFeePercent,
        uint256 _maxDelegationFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _purchaseFeePercent > 0 &&
                _settlementFeePercent > 0 &&
                _delegationFeePercent > 0 &&
                _maxDelegationFee > 0,
            "Values must be greater than 0"
        );
        purchaseFeePercent = _purchaseFeePercent;
        settlementFeePercent = _settlementFeePercent;
        delegationFeePercent = _delegationFeePercent;
        maxDelegationFee = _maxDelegationFee;
        emit SetFees(
            _purchaseFeePercent,
            _settlementFeePercent,
            _delegationFeePercent,
            _maxDelegationFee
        );
    }

    /// @notice Sets the allowance of the asset swapper
    /// @dev Can only be called by admin
    /// @param _token The token to set allowance for
    /// @param _value The amount of allowance
    /// @param _increase Whether to increase or decrease allowance
    function setAssetSwapperAllowance(
        address _token,
        uint256 _value,
        bool _increase
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_increase) {
            IERC20(_token).safeIncreaseAllowance(
                addresses.assetSwapper,
                _value
            );
        } else {
            IERC20(_token).safeDecreaseAllowance(
                addresses.assetSwapper,
                _value
            );
        }

        emit SetAssetSwapperAllowance(_token, _value, _increase);
    }

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by admin
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by admin
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(address _contract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(address _contract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by admin
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(address[] calldata tokens, bool transferNative)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenPaused
    {
        if (transferNative) {
            payable(msg.sender).transfer(address(this).balance);
        }

        for (uint256 i; i < tokens.length; ) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

