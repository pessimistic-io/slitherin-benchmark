//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {AccessControl} from "./AccessControl.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {AssetSwapper} from "./AssetSwapper.sol";

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
contract AtlanticStraddle is ReentrancyGuard, AccessControl, Pausable {
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

    // AP funding percent
    uint256 public constant apFundingPercent = 16 * percentagePrecision;

    // Number of seconds in a year
    uint256 internal constant SECONDS_IN_A_YEAR = 365 days;

    // purchase time limit variable to prevent last min buyouts
    uint256 public blackoutPeriodBeforeExpiry = 6 hours;

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
        // Array of strikes for this epoch
        uint256[] strikes;
        // Maps straddles purchased for different strikes
        mapping(uint256 => uint256) purchased;
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
    }

    event Bootstrap(uint256 epoch);

    event NewDeposit(
        uint256 epoch,
        uint256 amount,
        bool rollover,
        address user,
        address sender,
        uint256 tokenId
    );

    event SetAddresses(Addresses addresses);

    event Purchase(address user, uint256 straddleId, uint256 cost);

    event Settle(address indexed sender, uint256 id, int256 pnl);

    event Withdraw(address indexed sender, uint256 id, int256 pnl);

    event ToggleRollover(uint256 id, bool rollover);

    event BlackoutPeriodSet(uint256 period);

    event EpochExpired(address caller);

    event EpochPreExpired(address caller);

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

    /// @notice Sets the addresses used in the contract
    /// @param _addresses Addresses
    function setAddresses(Addresses memory _addresses)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        addresses = _addresses;
        emit SetAddresses(_addresses);
    }

    /// @dev Bootstrap and start the next epoch for purchases
    /// @param expiry Expiry offset timestamp (added to current time)
    /// @return Whether epoch was bootstrapped
    function bootstrap(uint256 expiry)
        public
        whenNotPaused
        onlyRole(MANAGER_ROLE)
        returns (bool)
    {
        uint256 nextEpoch = currentEpoch + 1;
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
        epochData[nextEpoch].expiry = block.timestamp + expiry;
        // Mark vault as ready for epoch
        isVaultReady[nextEpoch] = true;
        // Increase the current epoch
        currentEpoch = nextEpoch;

        emit Bootstrap(nextEpoch);

        return true;
    }

    /// @dev Deposit for next epoch
    /// @param amount Amount to deposit
    /// @param shouldRollover Should the deposit be rolled over
    /// @param user User address
    /// @return tokenId Write position token ID
    function deposit(
        uint256 amount,
        bool shouldRollover,
        address user
    ) public whenNotPaused returns (uint256 tokenId) {
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

        emit NewDeposit(
            nextEpoch,
            amount,
            shouldRollover,
            user,
            msg.sender,
            tokenId
        );
    }

    function calcWritePositionPnl(WritePosition memory writePos)
        internal
        view
        returns (int256 writePositionPnl)
    {
        uint256 settlementPrice = epochData[writePos.epoch].settlementPrice;
        uint256 endingValue = (epochData[writePos.epoch].underlyingPurchased *
            settlementPrice) +
            (epochData[writePos.epoch].activeUsdDeposits / 2);

        int256 totalEpochWriterPnl = int256(endingValue) -
            int256(
                epochData[writePos.epoch].activeUsdDeposits +
                    epochCollectionsData[writePos.epoch].usdPremiums +
                    epochCollectionsData[writePos.epoch].usdFunding
            );

        writePositionPnl = ((int256(writePos.usdDeposit) *
            totalEpochWriterPnl) /
            int256(epochData[writePos.epoch].usdDeposits) /
            10**20);
    }

    function canWithdraw(WritePosition memory writePos)
        internal
        view
        returns (bool)
    {
        require(writePos.epoch != 0, "Invalid write position");
        require(isEpochExpired[writePos.epoch], "Epoch has not expired");
        return true;
    }

    /// @dev Rolls over a deposit to the next epoch. Anyone can call this for write positions with `rollover` enabled
    /// Call this prior to bootstrapping to a new epoch or it will roll over to epoch n + 2
    /// @param id Write position token ID
    /// @return tokenId Rolled over write position token ID
    function rollover(uint256 id)
        public
        whenNotPaused
        returns (uint256 tokenId)
    {
        WritePosition memory writePos = writePositions[id];

        require(writePos.rollover, "Rollover not authorized");
        require(canWithdraw(writePos), "Withdrawal conditions must be met");

        int256 writePositionPnl = calcWritePositionPnl(writePos);

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

            emit NewDeposit(nextEpoch, amount, true, user, user, tokenId);
        }
    }

    /// @dev Toggle rollover for a write position
    /// @param id Write position token ID
    /// @return Whether rollover was toggled
    function toggleRollover(uint256 id) public whenNotPaused returns (bool) {
        require(
            IPositionMinter(addresses.writePositionMinter).ownerOf(id) ==
                msg.sender,
            "Invalid owner"
        );
        writePositions[id].rollover = !writePositions[id].rollover;
        emit ToggleRollover(id, writePositions[id].rollover);
        return true;
    }

    /// @dev Internal function to mint a write position token
    /// @param to the address to mint the position to
    function _mintWritePositionToken(address to)
        private
        returns (uint256 tokenId)
    {
        return IPositionMinter(addresses.writePositionMinter).mint(to);
    }

    /// @dev Purchase a straddle
    /// @param amount Amount of straddles to purchase (10 ** 18)
    /// @param user Address to purchase straddles for
    /// @return tokenId Straddle position token ID
    function purchase(uint256 amount, address user)
        public
        whenNotPaused
        returns (uint256 tokenId)
    {
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

        uint256 apPremium = calculatePremium(
            true,
            currentPrice,
            amount,
            epochData[currentEpoch].expiry
        );

        uint256 apFunding = ((currentPrice *
            apFundingPercent *
            timeToExpiry *
            amount) / (SECONDS_IN_A_YEAR * percentagePrecision)) / 10**2;

        // Strike was not used before
        if (epochData[currentEpoch].purchased[currentPrice] == 0) {
            epochData[currentEpoch].strikes.push(currentPrice);
        }

        epochData[currentEpoch].purchased[currentPrice] += amount;

        // Deposits
        epochData[currentEpoch].activeUsdDeposits += currentPrice * amount;

        // Swap half of AP to underlying
        uint256 underlyingPurchased = _swapToUnderlying(
            ((currentPrice * amount) / 2) / AMOUNT_PRICE_TO_USDC_DECIMALS
        );
        epochData[currentEpoch].underlyingPurchased += underlyingPurchased;

        // Collections
        epochCollectionsData[currentEpoch].usdPremiums += apPremium;
        epochCollectionsData[currentEpoch].usdFunding += apFunding;
        epochCollectionsData[currentEpoch].totalSold += amount;

        // Mint straddle position token
        tokenId = _mintStraddlePositionToken(user);
        straddlePositions[tokenId] = StraddlePosition({
            epoch: currentEpoch,
            amount: amount,
            apStrike: currentPrice
        });

        IERC20(addresses.usd).safeTransferFrom(
            msg.sender,
            address(this),
            (apPremium + apFunding) / AMOUNT_PRICE_TO_USDC_DECIMALS
        );

        uint256 protocolFee = apPremium / AMOUNT_PRICE_TO_USDC_DECIMALS / 1_000;
        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );

        emit Purchase(user, tokenId, apPremium + apFunding);
    }

    /// @dev Internal function to swap USD to underlying tokens
    /// @param amount Amount of USD to swap
    function _swapToUnderlying(uint256 amount)
        internal
        returns (uint256 underlyingPurchased)
    {
        underlyingPurchased = AssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.usd,
            addresses.underlying,
            amount,
            0
        );
    }

    /// @dev Internal function to mint a straddle position token
    /// @param to the address to mint the position to
    function _mintStraddlePositionToken(address to)
        private
        returns (uint256 tokenId)
    {
        return IPositionMinter(addresses.straddlePositionMinter).mint(to);
    }

    /// @dev Expire epoch and set the settlement price
    /// @return Whether epoch was expired
    function expireEpoch()
        public
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

    /// @dev Swap a certain percentage of total purchased underlying
    /// @param percentage ie6
    /// @return Whether epoch was expired
    function preExpireEpoch(uint256 percentage)
        public
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
            uint256 usdObtained = _swapFromUnderlying(underlyingToSwap);
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

    /// @dev Internal function to swap underlying tokens to USD
    /// @param amount Amount of underlying tokens to swap
    function _swapFromUnderlying(uint256 amount)
        internal
        returns (uint256 usdObtained)
    {
        usdObtained = AssetSwapper(addresses.assetSwapper).swapAsset(
            addresses.underlying,
            addresses.usd,
            amount,
            0
        );
    }

    /// @dev Settles a purchased option
    /// @param id ID of straddle position
    /// @return pnl of straddle
    function settle(uint256 id) public whenNotPaused returns (uint256) {
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

        int256 pnl = getPnl(id);

        IPositionMinter(addresses.straddlePositionMinter).burnToken(id);

        require(pnl > 0, "Negative pnl");
        uint256 positivePnl = uint256(pnl);
        uint256 protocolFee = positivePnl / 1_000;

        IERC20(addresses.usd).safeTransfer(
            addresses.feeDistributor,
            protocolFee
        );
        IERC20(addresses.usd).safeTransfer(
            msg.sender,
            positivePnl - protocolFee
        );

        emit Settle(msg.sender, id, pnl);

        return uint256(pnl);
    }

    /// @dev Withdraw write positions after strikes are settled
    /// @param id ID of write position
    /// @return pnl of write position
    function withdraw(uint256 id) public whenNotPaused returns (uint256) {
        require(
            IPositionMinter(addresses.writePositionMinter).ownerOf(id) ==
                msg.sender,
            "Invalid owner"
        );
        WritePosition memory writePos = writePositions[id];

        require(canWithdraw(writePos), "Withdrawal conditions must be met");

        int256 writePositionPnl = calcWritePositionPnl(writePos);

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
        premium =
            (IOptionPricing(addresses.optionPricing).getOptionPrice(
                _isPut,
                _expiry,
                _strike,
                getUnderlyingPrice(),
                getVolatility(_strike)
            ) * _amount) /
            2;
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

    /// @param id ID of straddle position
    /// @return Returns straddle position pnl
    function getPnl(uint256 id) public view returns (int256) {
        int256 settlementPrice = int256(
            epochData[straddlePositions[id].epoch].settlementPrice
        );
        int256 apStrike = int256(straddlePositions[id].apStrike);
        int256 amount = int256(straddlePositions[id].amount);
        int256 positionValue = ((apStrike + settlementPrice) / 2) * amount;
        int256 pnl = ((positionValue - (settlementPrice * amount)) / 10**20);

        return pnl;
    }

    /// @notice Change blackout period before expiry
    /// @dev Can only be called by governance
    /// @return Whether it was successfully updated
    function updateBlackoutPeriodBeforeExpiry(uint256 period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        require(period > 1 hours, "Blackout period must be more than 1 hour");
        blackoutPeriodBeforeExpiry = period;
        emit BlackoutPeriodSet(period);
        return true;
    }

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by governance
    /// @return Whether it was successfully paused
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _pause();
        return true;
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by governance
    /// @return Whether it was successfully unpaused
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _unpause();
        return true;
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by governance
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    /// @return Whether emergency withdraw was successful
    function emergencyWithdraw(address[] calldata tokens, bool transferNative)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenPaused
        returns (bool)
    {
        if (transferNative) {
            payable(msg.sender).transfer(address(this).balance);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        return true;
    }
}

