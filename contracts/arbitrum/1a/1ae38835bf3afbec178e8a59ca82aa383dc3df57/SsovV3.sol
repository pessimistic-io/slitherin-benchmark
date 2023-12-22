//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {Clones} from "./Clones.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721Burnable} from "./ERC721Burnable.sol";
import {AccessControl} from "./AccessControl.sol";
import {Counters} from "./Counters.sol";
import {SsovV3State} from "./SsovV3State.sol";
import {SsovV3OptionsToken} from "./SsovV3OptionsToken.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {Pausable} from "./Pausable.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IFeeStrategy} from "./IFeeStrategy.sol";
import {IStakingStrategy} from "./IStakingStrategy.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

/// @title SSOV V3 contract
/// @dev Option tokens are in erc20 18 decimals & Strikes are in 1e8 precision
contract SsovV3 is
    ReentrancyGuard,
    Pausable,
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    AccessControl,
    ContractWhitelist,
    SsovV3State
{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    /// @dev Token ID counter for write positions
    Counters.Counter private _tokenIdCounter;

    /*==== CONSTRUCTOR ====*/

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _underlyingSymbol,
        address _collateralToken,
        bool _isPut
    ) ERC721(_name, _symbol) {
        if (_collateralToken == address(0)) revert E1();

        underlyingSymbol = _underlyingSymbol;
        collateralToken = IERC20(_collateralToken);
        collateralPrecision = 10**collateralToken.decimals();
        isPut = _isPut;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
    }

    /*==== METHODS ====*/

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by the owner
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        _updateFinalEpochBalances();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by the owner
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

    /// @notice Updates the delay tolerance for the expiry epoch function
    /// @dev Can only be called by the owner
    function updateExpireDelayTolerance(uint256 _expireDelayTolerance)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        expireDelayTolerance = _expireDelayTolerance;
        emit ExpireDelayToleranceUpdate(_expireDelayTolerance);
    }

    /// @notice Updates the checkpoint interval time
    /// @dev Can only be called by the owner
    function updateCheckpointIntervalTime(uint256 _checkpointIntervalTime)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        checkpointIntervalTime = _checkpointIntervalTime;
        emit CheckpointIntervalTimeUpdate(_checkpointIntervalTime);
    }

    /// @notice Sets (adds) a list of addresses to the address list
    /// @dev Can only be called by the owner
    /// @param _addresses addresses of contracts in the Addresses struct
    function setAddresses(Addresses calldata _addresses)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        addresses = _addresses;
        emit AddressesSet(_addresses);
    }

    /// @notice Change the collateral token allowance to the StakingStrategy contract
    /// @dev Can only be called by the owner
    /// @param _increase bool
    /// @param _allowance uint256
    function changeAllowanceForStakingStrategy(
        bool _increase,
        uint256 _allowance
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_increase) {
            collateralToken.safeIncreaseAllowance(
                addresses.stakingStrategy,
                _allowance
            );
        } else {
            collateralToken.safeDecreaseAllowance(
                addresses.stakingStrategy,
                _allowance
            );
        }
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by the owner
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(address[] calldata tokens, bool transferNative)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _whenPaused();
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i = 0; i < tokens.length; i++) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        emit EmergencyWithdraw(msg.sender);
    }

    /// @dev Internal function to expire an epoch
    /// @param _settlementPrice the settlement price
    function _expire(uint256 _settlementPrice) private nonReentrant {
        _whenNotPaused();
        _epochNotExpired(currentEpoch);
        epochData[currentEpoch].settlementPrice = _settlementPrice;

        _updateFinalEpochBalances();

        epochData[currentEpoch].expired = true;

        emit EpochExpired(msg.sender, _settlementPrice);
    }

    /// @notice Sets the current epoch as expired
    function expire() external {
        _isEligibleSender();
        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        if (block.timestamp < epochExpiry) revert E4();
        if (block.timestamp > epochExpiry + expireDelayTolerance) revert E13();
        _expire(getUnderlyingPrice());
    }

    /// @notice Sets the current epoch as expired
    /// @dev Can only be called by the owner
    /// @param _settlementPrice The settlement price
    function expire(uint256 _settlementPrice)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _epochNotExpired(currentEpoch);
        _expire(_settlementPrice);
    }

    /// @dev Internal function to unstake collateral, gather yield and checkpoint each strike
    function _updateFinalEpochBalances() private {
        uint256[] memory strikes = getEpochStrikes(currentEpoch);

        uint256[] memory rewardTokenAmounts = IStakingStrategy(
            addresses.stakingStrategy
        ).unstake();

        for (uint256 i = 0; i < strikes.length; i++) {
            _updateRewards(strikes[i], rewardTokenAmounts, true);
        }
    }

    /// @notice Bootstraps a new epoch with new strikes
    /// @dev Can only be called by the owner
    /// @param strikes the strikes for the epoch
    /// @param expiry the expiry for the epoch
    /// @param expirySymbol the expiry symbol for the epoch
    function bootstrap(
        uint256[] memory strikes,
        uint256 expiry,
        string memory expirySymbol
    ) external nonReentrant onlyRole(MANAGER_ROLE) {
        _whenNotPaused();
        uint256 nextEpoch = currentEpoch + 1;
        if (block.timestamp > expiry) revert E2();
        if (currentEpoch > 0 && !epochData[currentEpoch].expired) revert E6();

        // Set the next epoch strikes
        epochData[nextEpoch].strikes = strikes;

        // Set the next epoch start time
        epochData[nextEpoch].startTime = block.timestamp;

        // Set the next epochs expiry
        epochData[nextEpoch].expiry = expiry;

        // Increase the current epoch
        currentEpoch = nextEpoch;

        uint256 rewardTokensLength = IStakingStrategy(addresses.stakingStrategy)
            .getRewardTokens()
            .length;

        uint256 strike;

        SsovV3OptionsToken _optionsToken;

        for (uint256 i = 0; i < strikes.length; i++) {
            strike = strikes[i];
            // Create options tokens representing the option for selected strike in epoch
            _optionsToken = SsovV3OptionsToken(
                Clones.clone(addresses.optionsTokenImplementation)
            );
            _optionsToken.initialize(
                address(this),
                isPut,
                strike,
                expiry,
                underlyingSymbol,
                collateralToken.symbol(),
                expirySymbol
            );
            epochStrikeData[nextEpoch][strike].strikeToken = address(
                _optionsToken
            );

            epochStrikeData[nextEpoch][strike]
                .rewardStoredForPremiums = new uint256[](rewardTokensLength);
            epochStrikeData[nextEpoch][strike]
                .rewardDistributionRatiosForPremiums = new uint256[](
                rewardTokensLength
            );
        }
        epochData[nextEpoch].totalRewardsCollected = new uint256[](
            rewardTokensLength
        );
        epochData[nextEpoch].rewardDistributionRatios = new uint256[](
            rewardTokensLength
        );
        epochData[nextEpoch].rewardTokensToDistribute = IStakingStrategy(
            addresses.stakingStrategy
        ).getRewardTokens();
        epochData[nextEpoch].collateralExchangeRate =
            (getUnderlyingPrice() * 1e8) /
            getCollateralPrice();

        emit Bootstrap(nextEpoch, strikes);
    }

    /// @dev Internal function to update the total collateral by adding the collateral from the last checkpoint if interval is completed
    /// @param _strike strike
    function _updateTotalCollateral(uint256 _strike) private {
        uint256 _epoch = currentEpoch;

        VaultCheckpoint memory _checkpoint = checkpoints[_epoch][_strike][
            checkpoints[_epoch][_strike].length - 1
        ];

        if (_checkpoint.startTime + checkpointIntervalTime < block.timestamp) {
            epochStrikeData[_epoch][_strike].totalCollateral += _checkpoint
                .totalCollateral;
            checkpoints[_epoch][_strike].push(
                VaultCheckpoint({
                    startTime: block.timestamp,
                    accruedPremium: 0,
                    activeCollateral: 0,
                    totalCollateral: 0
                })
            );
        }
    }

    /// @dev Internal function to checkpoint the vault for an epoch and strike
    /// @param strike strike
    /// @param collateralAdded collateral added
    function _vaultCheckpoint(uint256 strike, uint256 collateralAdded)
        private
        returns (uint256)
    {
        uint256 _epoch = currentEpoch;

        if (checkpoints[_epoch][strike].length == 0) {
            checkpoints[_epoch][strike].push(
                VaultCheckpoint({
                    startTime: block.timestamp,
                    accruedPremium: 0,
                    activeCollateral: 0,
                    totalCollateral: collateralAdded
                })
            );
            return (checkpoints[_epoch][strike].length - 1);
        }

        _updateTotalCollateral(strike);

        VaultCheckpoint memory _checkpoint = checkpoints[_epoch][strike][
            checkpoints[_epoch][strike].length - 1
        ];

        checkpoints[_epoch][strike][
            checkpoints[_epoch][strike].length - 1
        ] = VaultCheckpoint({
            startTime: _checkpoint.startTime,
            accruedPremium: _checkpoint.accruedPremium,
            activeCollateral: _checkpoint.activeCollateral,
            totalCollateral: _checkpoint.totalCollateral + collateralAdded
        });

        return (checkpoints[_epoch][strike].length - 1);
    }

    /// @dev Internal function to squeeze collateral from n checkpoints to fullfil a purchase
    /// @param _strike strike
    /// @param _requiredCollateral required collateral to fullfil purchase
    /// @param _premium premium awarded
    function _squeeze(
        uint256 _strike,
        uint256 _requiredCollateral,
        uint256 _premium
    ) private {
        VaultCheckpoint memory _checkpoint;

        uint256 _epoch = currentEpoch;
        uint256 _acquiredCollateral;
        uint256 _availableCollateral;
        uint256 _remainingRequiredCollateral;
        uint256 _premiumPerCollateral = (_premium * 1e18) / _requiredCollateral;
        uint256 _checkpointPointer = epochStrikeData[_epoch][_strike]
            .checkpointPointer;

        while (_acquiredCollateral < _requiredCollateral) {
            _checkpoint = checkpoints[_epoch][_strike][_checkpointPointer];

            _remainingRequiredCollateral =
                _requiredCollateral -
                _acquiredCollateral;

            _availableCollateral =
                _checkpoint.totalCollateral -
                _checkpoint.activeCollateral;

            if (_availableCollateral >= _remainingRequiredCollateral) {
                _acquiredCollateral += _remainingRequiredCollateral;
                checkpoints[_epoch][_strike][_checkpointPointer]
                    .activeCollateral += _remainingRequiredCollateral;
                checkpoints[_epoch][_strike][_checkpointPointer]
                    .accruedPremium +=
                    (_remainingRequiredCollateral * _premiumPerCollateral) /
                    1e18;
            } else {
                _acquiredCollateral += _availableCollateral;
                checkpoints[_epoch][_strike][_checkpointPointer]
                    .activeCollateral += _availableCollateral;
                checkpoints[_epoch][_strike][_checkpointPointer]
                    .accruedPremium +=
                    (_availableCollateral * _premiumPerCollateral) /
                    1e18;
                _checkpointPointer += 1;
            }
        }
    }

    /// @dev Internal function to mint a write position token
    /// @param to the address to mint the position to
    function _mintPositionToken(address to) private returns (uint256 tokenId) {
        tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /// @dev Calculates & updates the total rewards collected & the rewards distribution ratios
    /// @param strike the strike
    /// @param totalRewardsArray the totalRewardsArray
    /// @param isPurchase whether this was called on purchase
    function _updateRewards(
        uint256 strike,
        uint256[] memory totalRewardsArray,
        bool isPurchase
    ) private returns (uint256[] memory rewardsDistributionRatios) {
        rewardsDistributionRatios = new uint256[](totalRewardsArray.length);
        uint256 newRewardsCollected;

        for (uint256 i = 0; i < totalRewardsArray.length; i++) {
            // Calculate the new rewards accrued
            newRewardsCollected =
                totalRewardsArray[i] -
                epochData[currentEpoch].totalRewardsCollected[i];

            // Update the new total rewards accrued
            epochData[currentEpoch].totalRewardsCollected[
                i
            ] = totalRewardsArray[i];

            // Calculate the reward distribution ratios for the new rewards accrued
            if (epochData[currentEpoch].totalCollateralBalance == 0) {
                rewardsDistributionRatios[i] = 0;
            } else {
                rewardsDistributionRatios[i] =
                    (newRewardsCollected * 1e18) /
                    epochData[currentEpoch].totalCollateralBalance;
            }

            // Add it to the current reward distribution ratios
            epochData[currentEpoch].rewardDistributionRatios[
                    i
                ] += rewardsDistributionRatios[i];

            if (isPurchase) {
                // Add the new rewards accrued for the premiums staked until now
                epochStrikeData[currentEpoch][strike].rewardStoredForPremiums[
                        i
                    ] +=
                    ((epochData[currentEpoch].rewardDistributionRatios[i] -
                        epochStrikeData[currentEpoch][strike]
                            .rewardDistributionRatiosForPremiums[i]) *
                        epochStrikeData[currentEpoch][strike].totalPremiums) /
                    1e18;
                // Update the reward distribution ratios for the strike
                epochStrikeData[currentEpoch][strike]
                    .rewardDistributionRatiosForPremiums[i] = epochData[
                    currentEpoch
                ].rewardDistributionRatios[i];
            }

            rewardsDistributionRatios[i] = epochData[currentEpoch]
                .rewardDistributionRatios[i];
        }
    }

    /// @notice Deposit into the ssov to mint options in the next epoch for selected strikes
    /// @param strikeIndex Index of strike
    /// @param amount Amout of collateralToken to deposit
    /// @param to Address of to send the write position to
    /// @return tokenId token id of the deposit token
    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address to
    ) public nonReentrant returns (uint256 tokenId) {
        uint256 epoch = currentEpoch;

        _whenNotPaused();
        _isEligibleSender();
        _epochNotExpired(epoch);
        _amountNotZero(amount);

        // Must be a valid strike
        uint256 strike = epochData[epoch].strikes[strikeIndex];
        _strikeNotZero(strike);

        // Transfer collateralToken from msg.sender (maybe different from user param) to ssov
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        // Stake the collateral into the staking strategy and calculates rewards
        uint256[] memory rewardDistributionRatios = _updateRewards(
            strike,
            IStakingStrategy(addresses.stakingStrategy).stake(amount),
            false
        );

        // Checkpoint the vault
        uint256 checkpointIndex = _vaultCheckpoint(strike, amount);

        // Update the total collateral balance
        epochData[currentEpoch].totalCollateralBalance += amount;

        // Mint a write position token
        tokenId = _mintPositionToken(to);

        // Store the write position
        writePositions[tokenId] = WritePosition({
            epoch: epoch,
            strike: strike,
            collateralAmount: amount,
            checkpointIndex: checkpointIndex,
            rewardDistributionRatios: rewardDistributionRatios
        });

        emit Deposit(tokenId, to, msg.sender);
    }

    /// @notice Purchases options for the current epoch
    /// @param strikeIndex Strike index for current epoch
    /// @param amount Amount of options to purchase
    /// @param to address to send the purchased options to
    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address to
    ) external nonReentrant returns (uint256 premium, uint256 totalFee) {
        _whenNotPaused();
        _isEligibleSender();
        _amountNotZero(amount);

        uint256 epoch = currentEpoch;

        // Check if expiry time is beyond block.timestamp
        (, uint256 epochExpiry) = getEpochTimes(epoch);
        if (block.timestamp >= epochExpiry) revert E3();

        uint256 strike = epochData[epoch].strikes[strikeIndex];
        _strikeNotZero(strike);

        // Update the total collateral of a strike from an older checkpoint
        _updateTotalCollateral(strike);

        // Check if vault has enough collateral to write the options
        uint256 availableCollateral = epochStrikeData[epoch][strike]
            .totalCollateral - epochStrikeData[epoch][strike].activeCollateral;
        uint256 requiredCollateral = isPut
            ? ((amount * strike * collateralPrecision) / getCollateralPrice()) /
                1e18
            : (amount *
                epochData[epoch].collateralExchangeRate *
                collateralPrecision) / (1e26); /* 1e8 is the precision for the collateralExchangeRate, 1e18 is the precision of the options token */
        if (requiredCollateral > availableCollateral) revert E14();

        // Get total premium for all options being purchased
        premium = calculatePremium(strike, amount, epochExpiry);

        // Total fee charged
        totalFee = calculatePurchaseFees(strike, amount);

        _squeeze(strike, requiredCollateral, premium);

        // Transfer premium from msg.sender (need not be same as user)
        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            premium + totalFee
        );

        // Stake premium into the staking strategy and calculates rewards
        _updateRewards(
            strike,
            IStakingStrategy(addresses.stakingStrategy).stake(premium),
            true
        );

        // Update active collateral
        epochStrikeData[epoch][strike].activeCollateral += requiredCollateral;

        // Update total premiums
        epochStrikeData[epoch][strike].totalPremiums += premium;

        // Update the totalCollateralBalance
        epochData[epoch].totalCollateralBalance += premium;

        // Transfer fee to FeeDistributor
        collateralToken.safeTransfer(addresses.feeDistributor, totalFee);

        // Mint option tokens
        SsovV3OptionsToken(epochStrikeData[epoch][strike].strikeToken).mint(
            to,
            amount
        );

        emit Purchase(epoch, strike, amount, premium, totalFee, to, msg.sender);
    }

    /// @notice Settle calculates the PnL for the user and withdraws the PnL in the BaseToken to the user. Will also the burn the option tokens from the user.
    /// @param strikeIndex Strike index
    /// @param amount Amount of options
    /// @param to The address to transfer pnl too
    /// @return pnl
    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch,
        address to
    ) external nonReentrant returns (uint256 pnl) {
        _whenNotPaused();
        _isEligibleSender();
        _amountNotZero(amount);
        _epochExpired(epoch);

        uint256 strike = epochData[epoch].strikes[strikeIndex];

        SsovV3OptionsToken strikeToken = SsovV3OptionsToken(
            epochStrikeData[epoch][strike].strikeToken
        );

        if (strikeToken.balanceOf(msg.sender) < amount) {
            revert E11();
        }

        // Burn option tokens from user
        strikeToken.burnFrom(msg.sender, amount);

        // Get the settlement price for the epoch
        uint256 settlementPrice = epochData[epoch].settlementPrice;

        // Calculate pnl
        pnl = calculatePnl(settlementPrice, strike, amount);

        // Total fee charged
        uint256 totalFee = calculateSettlementFees(pnl);

        if (pnl <= 0) {
            revert E10();
        }

        // Transfer fee to FeeDistributor
        collateralToken.safeTransfer(addresses.feeDistributor, totalFee);

        // Transfer PnL
        collateralToken.safeTransfer(to, pnl - totalFee);

        emit Settle(
            epoch,
            strike,
            amount,
            pnl - totalFee,
            totalFee,
            to,
            msg.sender
        );
    }

    /// @notice Withdraw from the ssov via burning a write position token
    /// @param tokenId token id of the write position
    /// @param to address to transfer collateral and rewards
    function withdraw(uint256 tokenId, address to)
        external
        nonReentrant
        returns (
            uint256 collateralTokenWithdrawAmount,
            uint256[] memory rewardTokenWithdrawAmounts
        )
    {
        _whenNotPaused();
        _isEligibleSender();

        (
            uint256 epoch,
            uint256 strike,
            uint256 collateralAmount,
            uint256 checkpointIndex,
            uint256[] memory rewardDistributionRatios
        ) = writePosition(tokenId);

        _strikeNotZero(strike);
        _epochExpired(epoch);

        // Burn the write position token
        burn(tokenId);

        // Get the checkpoint
        VaultCheckpoint memory _checkpoint = checkpoints[epoch][strike][
            checkpointIndex
        ];

        // Rewards calculations
        rewardTokenWithdrawAmounts = new uint256[](
            epochData[epoch].rewardTokensToDistribute.length
        );

        uint256 accruedPremium = (_checkpoint.accruedPremium *
            collateralAmount) / _checkpoint.totalCollateral;

        uint256 optionsWritten = isPut
            ? (_checkpoint.activeCollateral * 1e8) / strike
            : _checkpoint.activeCollateral;

        // Get the settlement price for the epoch
        uint256 settlementPrice = epochData[epoch].settlementPrice;

        // Calculate the withdrawable collateral amount
        collateralTokenWithdrawAmount =
            ((_checkpoint.totalCollateral -
                calculatePnl(settlementPrice, strike, optionsWritten)) *
                collateralAmount) /
            _checkpoint.totalCollateral;

        // Add premiums
        collateralTokenWithdrawAmount += accruedPremium;

        // Calculate and transfer rewards
        for (uint256 i = 0; i < rewardTokenWithdrawAmounts.length; i++) {
            rewardTokenWithdrawAmounts[i] +=
                ((epochData[epoch].rewardDistributionRatios[i] -
                    rewardDistributionRatios[i]) * collateralAmount) /
                1e18;
            if (epochStrikeData[epoch][strike].totalPremiums > 0)
                rewardTokenWithdrawAmounts[i] +=
                    (accruedPremium *
                        epochStrikeData[epoch][strike].rewardStoredForPremiums[
                            i
                        ]) /
                    epochStrikeData[epoch][strike].totalPremiums;
            IERC20(epochData[epoch].rewardTokensToDistribute[i]).safeTransfer(
                to,
                rewardTokenWithdrawAmounts[i]
            );
        }

        // Transfer the collateralTokenWithdrawAmount
        collateralToken.safeTransfer(to, collateralTokenWithdrawAmount);

        emit Withdraw(
            tokenId,
            collateralTokenWithdrawAmount,
            rewardTokenWithdrawAmounts,
            to,
            msg.sender
        );
    }

    /*==== VIEWS ====*/

    /// @notice Returns the price of the underlying in USD in 1e8 precision
    function getUnderlyingPrice() public view returns (uint256) {
        return IPriceOracle(addresses.priceOracle).getUnderlyingPrice();
    }

    /// @notice Returns the price of the collateral token in 1e8 precision
    /// @dev This contract assumes that this price can never decrease in ratio of the underlying price
    function getCollateralPrice() public view returns (uint256) {
        return IPriceOracle(addresses.priceOracle).getCollateralPrice();
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
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options (1e18 precision)
    /// @param _expiry Expiry of the option
    /// @return premium in collateralToken in collateral precision
    function calculatePremium(
        uint256 _strike,
        uint256 _amount,
        uint256 _expiry
    ) public view returns (uint256 premium) {
        premium = (IOptionPricing(addresses.optionPricing).getOptionPrice(
            isPut,
            _expiry,
            _strike,
            getUnderlyingPrice(),
            getVolatility(_strike)
        ) * _amount);

        premium = (premium * collateralPrecision) / getCollateralPrice() / 1e18;
    }

    /// @notice Calculate Pnl
    /// @param price price of the underlying asset
    /// @param strike strike price of the option
    /// @param amount amount of options
    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256) {
        if (isPut)
            return
                strike > price
                    ? (((strike - price) * amount * collateralPrecision) /
                        getCollateralPrice()) / 1e18
                    : 0;
        return
            price > strike
                ? (((price - strike) * amount * collateralPrecision) /
                    getCollateralPrice()) / 1e18
                : 0;
    }

    /// @notice Calculate fees for purchase
    /// @param strike strike price of the BaseToken option
    /// @param amount amount of options being bought
    function calculatePurchaseFees(uint256 strike, uint256 amount)
        public
        view
        returns (uint256)
    {
        return ((IFeeStrategy(addresses.feeStrategy).calculatePurchaseFees(
            getUnderlyingPrice(),
            strike,
            amount
        ) * collateralPrecision) / getCollateralPrice());
    }

    /// @notice Calculate fees for settlement of options
    /// @param pnl total pnl
    function calculateSettlementFees(uint256 pnl)
        public
        view
        returns (uint256)
    {
        return IFeeStrategy(addresses.feeStrategy).calculateSettlementFees(pnl);
    }

    /// @notice Returns start and end times for an epoch
    /// @param epoch Target epoch
    function getEpochTimes(uint256 epoch)
        public
        view
        returns (uint256 start, uint256 end)
    {
        _epochGreaterThanZero(epoch);

        return (epochData[epoch].startTime, epochData[epoch].expiry);
    }

    /// @notice Returns the array of strikes in an epoch
    /// @param epoch the epoch for which the array of strikes need to be returned for
    function getEpochStrikes(uint256 epoch)
        public
        view
        returns (uint256[] memory)
    {
        _epochGreaterThanZero(epoch);

        return epochData[epoch].strikes;
    }

    /// @notice View a write position
    /// @param tokenId tokenId a parameter just like in doxygen (must be followed by parameter name)
    function writePosition(uint256 tokenId)
        public
        view
        returns (
            uint256 epoch,
            uint256 strike,
            uint256 collateralAmount,
            uint256 checkpointIndex,
            uint256[] memory rewardDistributionRatios
        )
    {
        WritePosition memory _writePosition = writePositions[tokenId];

        return (
            _writePosition.epoch,
            _writePosition.strike,
            _writePosition.collateralAmount,
            _writePosition.checkpointIndex,
            _writePosition.rewardDistributionRatios
        );
    }

    /// @notice Returns the data for an epoch
    /// @param epoch the epoch
    function getEpochData(uint256 epoch)
        external
        view
        returns (EpochData memory)
    {
        _epochGreaterThanZero(epoch);
        return epochData[epoch];
    }

    /// @notice Returns the checkpoints for an epoch and strike
    /// @param epoch the epoch
    /// @param strike the strike
    function getCheckpoints(uint256 epoch, uint256 strike)
        external
        view
        returns (VaultCheckpoint[] memory)
    {
        _epochGreaterThanZero(epoch);
        return checkpoints[epoch][strike];
    }

    /// @notice Returns the data for an epoch and strike
    /// @param epoch the epoch
    /// @param strike the strike
    function getEpochStrikeData(uint256 epoch, uint256 strike)
        external
        view
        returns (EpochStrikeData memory)
    {
        _epochGreaterThanZero(epoch);
        return epochStrikeData[epoch][strike];
    }

    /*==== PRIVATE FUCNTIONS FOR REVERTS ====*/

    /// @dev Internal function to check if the epoch passed is greater than 0. Revert if 0.
    /// @param _epoch the epoch
    function _epochGreaterThanZero(uint256 _epoch) private pure {
        if (_epoch <= 0) revert E9();
    }

    /// @dev Internal function to check if the epoch passed is not expired. Revert if expired.
    /// @param _epoch the epoch
    function _epochNotExpired(uint256 _epoch) private view {
        if (epochData[_epoch].expired) revert E3();
    }

    /// @dev Internal function to check if the epoch passed is expired. Revert if not expired.
    /// @param _epoch the epoch
    function _epochExpired(uint256 _epoch) private view {
        if (!epochData[_epoch].expired) revert E12();
    }

    /// @dev Internal function to check if the amount passed is not 0. Revert if 0.
    /// @param _amount the amount
    function _amountNotZero(uint256 _amount) private pure {
        if (_amount <= 0) revert E7();
    }

    /// @dev Internal function to check if the strike passed is not 0. Revert if 0.
    /// @param _strike the strike
    function _strikeNotZero(uint256 _strike) private pure {
        if (_strike <= 0) revert E8();
    }

    /*==== ERRORS ====*/

    /// @notice Address cannot be a zero address
    error E1();

    /// @notice Expiry passed must be after current block.timestamp
    error E2();

    /// @notice Epoch must not be expired
    error E3();

    /// @notice Cannot expire epoch before epoch's expiry
    error E4();

    // error E5(); This error is deprecated

    /// @notice Cannot bootstrap before current epoch's expiry
    error E6();

    /// @notice Amount must not be 0
    error E7();

    /// @notice Strike must not be 0
    error E8();

    /// @notice Epoch must be greater than 0
    error E9();

    /// @notice Pnl must be greater than 0
    error E10();

    /// @notice Option token balance is not enough
    error E11();

    /// @notice Epoch must be expired
    error E12();

    /// @notice Expire delay tolerance exceeded
    error E13();

    /// @notice Available collateral must be greater than or equal to required collateral
    error E14();

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        _whenNotPaused();
        super._beforeTokenTransfer(from, to, tokenId);
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

