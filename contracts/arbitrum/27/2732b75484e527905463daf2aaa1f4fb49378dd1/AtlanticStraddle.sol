//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

// Libraries
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
import {IPositionMinter} from "./IPositionMinter.sol";

// Atlantic straddles
// ==============
// - Accept stable deposits
// - Deposits can only happen for next epoch
// - Stables are always sold as ATM puts
// - Tokenize deposit as NFT
// - 3 day epochs, deposits auto-rollover unless deactivated
// - Withdrawal considers performance of pool since deposit
// - On purchase of Atlantic straddle, use 50% of AP collateral to purchase underlying asset
// - At expiry, settle by selling purchased underlying asset to return AP and AC collateral
contract AtlanticStraddle is
    ReentrancyGuard,
    AccessControl,
    Pausable,
    ContractWhitelist
{
    using SafeERC20 for IERC20;

    // Current epoch. 0-indexed
    uint256 public currentEpoch;

    // Managar Role
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // Contract addresses
    Addresses public addresses;

    // Total deposits for epoch
    mapping(uint256 => EpochData) public epochData;

    // Data for premium and funding collections for an epoch
    mapping(uint256 => EpochCollectionsData) public epochCollectionsData;

    // Is vault ready for the epoch i.e can purchases begin
    mapping(uint256 => bool) public isVaultReady;

    // Toggled to true after an epoch has been marked expired
    mapping(uint256 => bool) public isEpochExpired;

    // Write positions
    mapping(uint256 => WritePosition) public writePositions;

    // Straddle positions
    mapping(uint256 => StraddlePosition) public straddlePositions;

    // Percentage precision
    uint256 public constant percentagePrecision = 10**6;

    // Purchase fee percent
    uint256 public purchaseFeePercent = 1e5;

    // Settlement fee percent
    uint256 public settlementFeePercent = 1e5;

    // AP funding percent
    uint256 public apFundingPercent = 16 * percentagePrecision;

    // Purchase time limit variable to prevent last min buyouts
    uint256 public blackoutPeriodBeforeExpiry = 6 hours;

    // PnL slippage percent
    uint256 public pnlSlippagePercent = 2 * percentagePrecision;

    uint256 internal constant AMOUNT_PRICE_TO_USDC_DECIMALS =
        (1e18 * 1e8) / 1e6;

    struct Addresses {
        // Stablecoin token (1e6 precision)
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
        // Straddle Position Manager
        address straddlePositionMinter;
        // Write Position Manager
        address writePositionMinter;
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
        // Final usd balance of vault
        uint256 finalUsdBalance;
    }

    struct EpochCollectionsData {
        // Total premiums collected for USD deposits
        uint256 usdPremiums;
        // Total funding collected for USD deposits
        uint256 usdFunding;
        // Total amount of straddles sold
        uint256 totalSold;
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

    event Purchase(address user, uint256 straddleId, uint256 cost);

    event Settle(address indexed sender, uint256 id, uint256 pnl);

    event Withdraw(address indexed sender, uint256 id, int256 pnl);

    event ToggleRollover(uint256 id, bool rollover);

    event EpochExpired(address caller);

    event EpochPreExpired(address caller);

    event SetAddresses(Addresses addresses);

    event SetBlackoutPeriod(uint256 period);

    event SetApFunding(uint256 apFunding);

    event SetFeePercents(
        uint256 purchaseFeePercent,
        uint256 settlementFeePercent
    );

    /*==== CONSTRUCTOR ====*/

    constructor(Addresses memory _addresses) {
        addresses = _addresses;

        IERC20(addresses.usd).safeIncreaseAllowance(
            addresses.assetSwapper,
            type(uint256).max
        );
        IERC20(addresses.underlying).safeIncreaseAllowance(
            addresses.assetSwapper,
            type(uint256).max
        );

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
        require(amount > 0, "Cannot deposit 0 amount");
        uint256 nextEpoch = currentEpoch + 1;

        epochData[nextEpoch].usdDeposits += amount;

        tokenId = _mintWritePositionToken(user);

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

        int256 writePositionPnl = calculateWritePositionPnl(id);

        address user = IPositionMinter(addresses.writePositionMinter).ownerOf(
            id
        );

        IPositionMinter(addresses.writePositionMinter).burnToken(id);

        emit Withdraw(user, id, writePositionPnl);

        int256 depositPlusPnl = int256(writePositions[id].usdDeposit) +
            writePositionPnl;

        if (depositPlusPnl > 0) {
            uint256 nextEpoch = currentEpoch + 1;
            uint256 amount = uint256(depositPlusPnl);

            epochData[nextEpoch].usdDeposits += amount;

            tokenId = _mintWritePositionToken(user);
            writePositions[tokenId] = WritePosition({
                epoch: nextEpoch,
                usdDeposit: amount,
                rollover: true
            });

            emit Deposit(nextEpoch, amount, true, user, user, tokenId);
        }
    }

    /// @dev Rollover for multiple ids
    /// @param ids Write position token IDs
    /// @return tokenIds Rolled over write position token IDs
    function multirollover(uint256[] memory ids)
        external
        returns (uint256[] memory tokenIds)
    {
        tokenIds = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            tokenIds[i] = rollover(ids[i]);
        }
    }

    /// @dev Toggle rollover for a write position
    /// @param id Write position token ID
    function toggleRollover(uint256 id) external whenNotPaused nonReentrant {
        _isEligibleSender();
        require(
            IPositionMinter(addresses.writePositionMinter).ownerOf(id) ==
                msg.sender,
            "Invalid owner"
        );
        writePositions[id].rollover = !writePositions[id].rollover;
        emit ToggleRollover(id, writePositions[id].rollover);
    }

    /// @dev Withdraw write positions after strikes are settled
    /// @param id ID of write position
    /// @return pnl of write position
    function withdraw(uint256 id)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _isEligibleSender();
        require(
            IPositionMinter(addresses.writePositionMinter).ownerOf(id) ==
                msg.sender,
            "Invalid owner"
        );

        WritePosition memory writePos = writePositions[id];

        require(writePos.epoch != 0, "Invalid write position");
        require(isEpochExpired[writePos.epoch], "Epoch has not expired");

        int256 writePositionPnl = calculateWritePositionPnl(id);

        int256 depositPlusPnl = int256(writePositions[id].usdDeposit) +
            writePositionPnl;

        if (depositPlusPnl > 0) {
            IERC20(addresses.usd).safeTransfer(
                msg.sender,
                uint256(depositPlusPnl)
            );
        }

        IPositionMinter(addresses.writePositionMinter).burnToken(id);

        emit Withdraw(msg.sender, id, writePositionPnl);

        return uint256(depositPlusPnl);
    }

    /// @dev Purchase a straddle
    /// @param amount Approx. amount of straddles to purchase (10 ** 18)
    /// @param swapperId Swapper ID of the swap method to use
    /// @param user Address to purchase straddles for
    /// @return tokenId Straddle position token ID
    function purchase(
        uint256 amount,
        uint256 swapperId,
        address user
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        _isEligibleSender();
        require(currentEpoch > 0, "Invalid epoch");
        require(amount > 0, "Invalid amount");
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
            swapperId
        );

        uint256 swapPrice = (currentPrice * amount) / (underlyingPurchased * 2);

        epochData[currentEpoch].underlyingPurchased += underlyingPurchased;

        // Deposits
        epochData[currentEpoch].activeUsdDeposits +=
            swapPrice *
            (underlyingPurchased * 2);

        uint256 apPremium = calculatePremium(
            true,
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

        // Mint straddle position token
        tokenId = _mintStraddlePositionToken(user);
        straddlePositions[tokenId] = StraddlePosition({
            epoch: currentEpoch,
            amount: underlyingPurchased * 2,
            apStrike: swapPrice,
            underlyingPurchased: underlyingPurchased
        });

        IERC20(addresses.usd).safeTransferFrom(
            msg.sender,
            address(this),
            (apPremium + apFunding) / AMOUNT_PRICE_TO_USDC_DECIMALS
        );

        uint256 protocolFee = (apPremium * purchaseFeePercent) /
            (percentagePrecision * AMOUNT_PRICE_TO_USDC_DECIMALS * 1e2);

        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );

        emit Purchase(user, tokenId, apPremium + apFunding);
    }

    /// @dev Settles a purchased option
    /// @param id ID of straddle position
    /// @return pnl of straddle
    function settle(uint256 id)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _isEligibleSender();
        require(
            IPositionMinter(addresses.straddlePositionMinter).ownerOf(id) ==
                msg.sender,
            "Invalid owner"
        );
        require(straddlePositions[id].epoch != 0, "Invalid straddle position");
        require(
            isEpochExpired[straddlePositions[id].epoch],
            "Epoch has not expired"
        );

        uint256 pnl = calculateStraddlePositionPnl(id);

        IPositionMinter(addresses.straddlePositionMinter).burnToken(id);

        require(pnl != 0, "PnL cannot be 0");

        uint256 protocolFee = (pnl * settlementFeePercent) /
            (percentagePrecision * 1e2);

        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );
        IERC20(addresses.usd).safeTransfer(msg.sender, pnl - protocolFee);

        emit Settle(msg.sender, id, pnl);

        return uint256(pnl);
    }

    /*==== INTERNAL METHODS ====*/

    /// @dev Internal function to mint a straddle position token
    /// @param to the address to mint the position to
    function _mintStraddlePositionToken(address to)
        private
        returns (uint256 tokenId)
    {
        return IPositionMinter(addresses.straddlePositionMinter).mint(to);
    }

    /// @dev Internal function to mint a write position token
    /// @param to the address to mint the position to
    function _mintWritePositionToken(address to)
        private
        returns (uint256 tokenId)
    {
        return IPositionMinter(addresses.writePositionMinter).mint(to);
    }

    /// @dev Internal function to swap USD to underlying tokens
    /// @param amount Amount of USD to swap
    /// @param swapperId Swapper ID
    function _swapToUnderlying(uint256 amount, uint256 swapperId)
        internal
        returns (uint256 underlyingPurchased)
    {
        underlyingPurchased = IAssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.usd,
            addresses.underlying,
            amount,
            0,
            swapperId
        );
    }

    /// @dev Internal function to swap underlying tokens to USD
    /// @param amount Amount of underlying tokens to swap
    /// @param swapperId Swapper ID
    function _swapFromUnderlying(uint256 amount, uint256 swapperId)
        internal
        returns (uint256 usdObtained)
    {
        usdObtained = IAssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.underlying,
            addresses.usd,
            amount,
            0,
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
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options (1e18 precision)
    /// @param _expiry Expiry of the option
    /// @return premium in USD
    function calculatePremium(
        bool _isPut,
        uint256 _strike,
        uint256 _amount,
        uint256 _expiry
    ) public view returns (uint256 premium) {
        premium = (IOptionPricing(addresses.optionPricing).getOptionPrice(
            _isPut,
            _expiry,
            _strike,
            getUnderlyingPrice(),
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
                (365 days * percentagePrecision)) / 10**2) /
            2;
    }

    /// @notice Calculates the writer position pnl
    /// @param id the id of the write position
    /// @return writePositionPnl
    function calculateWritePositionPnl(uint256 id)
        public
        view
        returns (int256 writePositionPnl)
    {
        WritePosition memory writePos = writePositions[id];

        uint256 settlementPrice = epochData[writePos.epoch].settlementPrice;

        int256 loss = int256(epochData[writePos.epoch].activeUsdDeposits) -
            int256(
                epochCollectionsData[writePos.epoch].totalSold * settlementPrice
            );

        if (loss < 0) loss = 0;

        int256 totalEpochWriterPnl = int256(
            epochCollectionsData[writePos.epoch].usdPremiums +
                epochCollectionsData[writePos.epoch].usdFunding
        ) - loss;

        writePositionPnl = ((int256(writePos.usdDeposit) *
            totalEpochWriterPnl) /
            int256(epochData[writePos.epoch].usdDeposits) /
            10**20);
    }

    /// @param id ID of straddle position
    /// @return pnl
    function calculateStraddlePositionPnl(uint256 id)
        public
        view
        returns (uint256)
    {
        int256 pnl;

        StraddlePosition memory sp = straddlePositions[id];

        int256 settlementPrice = int256(
            epochData[straddlePositions[id].epoch].settlementPrice
        );

        // Calculate PnL for APs purchased
        if (settlementPrice < int256(sp.apStrike)) {
            pnl = (int256(sp.apStrike) - settlementPrice) * int256(sp.amount);
            // Adjust to usd precision which is 1e6
            pnl = pnl / 1e20;
        }

        // Calculate PnL for underlying purchased
        pnl =
            pnl +
            (((settlementPrice * int256(sp.underlyingPurchased)) -
                (int256(sp.apStrike) * int256(sp.underlyingPurchased))) / 1e20);

        pnl =
            pnl -
            ((pnl * int256(pnlSlippagePercent)) /
                (1e2 * int256(percentagePrecision)));

        return pnl < 0 ? uint256(-1 * pnl) : uint256(pnl);
    }

    /// @notice Returns the tokenIds owned by a wallet (writePositions)
    /// @param owner wallet owner
    function writePositionsOfOwner(address owner)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 ownerTokenCount = IPositionMinter(addresses.writePositionMinter)
            .balanceOf(owner);
        tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = IPositionMinter(addresses.writePositionMinter)
                .tokenOfOwnerByIndex(owner, i);
        }
    }

    /// @notice Returns the tokenIds owned by a wallet (straddlePositions)
    /// @param owner wallet owner
    function straddlePositionsOfOwner(address owner)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 ownerTokenCount = IPositionMinter(
            addresses.straddlePositionMinter
        ).balanceOf(owner);
        tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = IPositionMinter(addresses.straddlePositionMinter)
                .tokenOfOwnerByIndex(owner, i);
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
    /// @param swapperId Swapper ID of the swap method to use with AssetSwapper
    function preExpireEpoch(uint256 percentage, uint256 swapperId)
        external
        whenNotPaused
        onlyRole(MANAGER_ROLE)
        returns (bool)
    {
        require(percentage > 0, "Percentage cannot be 0");
        require(!isEpochExpired[currentEpoch], "Epoch was already expired");
        require(
            block.timestamp >= epochData[currentEpoch].expiry,
            "Time is not past epoch expiry"
        );
        require(
            epochData[currentEpoch].settlementPercentage + percentage <=
                (100 * percentagePrecision),
            "You cannot swap more than 100%"
        );

        // Swap all purchased underlying at current price
        uint256 underlyingToSwap = (epochData[currentEpoch]
            .underlyingPurchased * percentage) / (100 * percentagePrecision);

        if (underlyingToSwap > 0) {
            uint256 usdObtained = _swapFromUnderlying(
                underlyingToSwap,
                swapperId
            );
            uint256 settlementPrice = (usdObtained * 10**20) / underlyingToSwap;

            epochData[currentEpoch].settlementPrice =
                ((epochData[currentEpoch].settlementPrice *
                    epochData[currentEpoch].settlementPercentage) +
                    (settlementPrice * percentage)) /
                (epochData[currentEpoch].settlementPercentage + percentage);

            epochData[currentEpoch].settlementPercentage += percentage;
        } else {
            epochData[currentEpoch].settlementPrice = getUnderlyingPrice();

            epochData[currentEpoch].settlementPercentage =
                100 *
                percentagePrecision;
        }

        emit EpochPreExpired(msg.sender);

        return true;
    }

    /// @dev Expire epoch and set the settlement price
    function expireEpoch()
        external
        whenNotPaused
        onlyRole(MANAGER_ROLE)
        returns (bool)
    {
        require(!isEpochExpired[currentEpoch], "Epoch was already expired");
        require(
            block.timestamp >= epochData[currentEpoch].expiry,
            "Time is not past epoch expiry"
        );

        require(
            epochData[currentEpoch].settlementPercentage >
                (99 * percentagePrecision),
            "You need to swap underlying first"
        );

        isEpochExpired[currentEpoch] = true;

        emit EpochExpired(msg.sender);

        return true;
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
        require(apFundingPercent > 0, "Funding rate must be greater than 0");
        apFundingPercent = _apFundingPercent;
        emit SetApFunding(_apFundingPercent);
    }

    /// @notice Sets the purchase/settlement fee percent
    /// @dev Can only be called by admin
    /// @param _purchaseFeePercent Purchase fee percent
    /// @param _settlementFeePercent Settlement fee percent
    function setFeePercents(
        uint256 _purchaseFeePercent,
        uint256 _settlementFeePercent
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _purchaseFeePercent > 0 && _settlementFeePercent > 0,
            "Percents must be greater than 0"
        );
        purchaseFeePercent = _purchaseFeePercent;
        settlementFeePercent = _settlementFeePercent;
        emit SetFeePercents(_purchaseFeePercent, _settlementFeePercent);
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

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }
    }
}

