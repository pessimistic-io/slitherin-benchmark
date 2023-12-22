//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Libraries
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {OwnableRoles} from "./OwnableRoles.sol";

// Libraries
import {StructuredLinkedList} from "./StructuredLinkedList.sol";
import {Counters} from "./Counters.sol";

// Contracts
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {AtlanticPutsPoolState} from "./AtlanticPutsPoolState.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IDopexFeeStrategy} from "./IDopexFeeStrategy.sol";

// Enums
import {OptionsState, EpochState, Contracts, VaultConfig} from "./AtlanticPutsPoolEnums.sol";

// Structs
import {EpochData, MaxStrikesRange, Checkpoint, OptionsPurchase, DepositPosition, EpochRewards, MaxStrike} from "./AtlanticPutsPoolStructs.sol";

contract AtlanticPutsPool is
    AtlanticPutsPoolState,
    Pausable,
    ReentrancyGuard,
    OwnableRoles
{
    using StructuredLinkedList for StructuredLinkedList.List;

    uint256 internal constant ADMIN_ROLE = _ROLE_0;
    uint256 internal constant MANAGED_CONTRACT_ROLE = _ROLE_1;
    uint256 internal constant BOOSTRAPPER_ROLE = _ROLE_2;
    uint256 internal constant WHITELISTED_CONTRACT_ROLE = _ROLE_3;

    /**
     * @notice Structured linked list for max strikes
     * @dev    epoch => strike list
     */
    mapping(uint256 => StructuredLinkedList.List) private epochStrikesList;

    /// @dev Number of deicmals of deposit/premium token
    uint256 private immutable COLLATERAL_TOKEN_DECIMALS;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address collateralToken) {
        COLLATERAL_TOKEN_DECIMALS = IERC20(collateralToken).decimals();
        _setOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);
        _grantRoles(msg.sender, MANAGED_CONTRACT_ROLE);
        _grantRoles(msg.sender, BOOSTRAPPER_ROLE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        PUBLIC VIEWS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice                Get amount amount of underlying to
     *                        be unwinded against options.
     * @param  _optionStrike  Strike price of the option.
     * @param  _optionsAmount Amount of options to unwind.
     * @return unwindAmount
     */
    function getUnwindAmount(
        uint256 _optionStrike,
        uint256 _optionsAmount
    ) public view returns (uint256 unwindAmount) {
        if (_optionStrike < getUsdPrice()) {
            unwindAmount = (_optionsAmount * _optionStrike) / getUsdPrice();
        } else {
            unwindAmount = _optionsAmount;
        }
    }

    /**
     * @notice       Calculate Pnl for exercising options.
     * @param price  price of BaseToken.
     * @param strike strike price of the option.
     * @param amount amount of options.
     */
    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256) {
        if (price == 0) price = getUsdPrice();
        return strike > price ? (strikeMulAmount((strike - price), amount)) : 0;
    }

    /**
     * @notice                  Calculate funding fees based on days
     *                          left till expiry.
     * @param _collateralAccess Amount of collateral borrowed.
     * @param _entryTimestamp   Timestamp of entry of unlockCollatera().
     *                          which is used to calc. how much funding
     *                          is to be charged.
     * @return fees
     */
    function calculateFundingFees(
        uint256 _collateralAccess,
        uint256 _entryTimestamp
    ) public view returns (uint256 fees) {
        fees =
            ((_epochData[currentEpoch].expiryTime - _entryTimestamp) /
                vaultConfig[VaultConfig.FundingInterval]) *
            vaultConfig[VaultConfig.BaseFundingRate];

        fees =
            ((_collateralAccess * (FEE_BPS_PRECISION + fees)) /
                FEE_BPS_PRECISION) -
            _collateralAccess;
    }

    /**
     * @notice          Calculate Fees for purchase.
     * @param  strike   strike price of the BaseToken option.
     * @param  amount   amount of options being bought.
     * @return finalFee purchase fee in QuoteToken.
     */
    function calculatePurchaseFees(
        address account,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256 finalFee) {
        uint256 feeBps = IDopexFeeStrategy(addresses[Contracts.FeeStrategy])
            .getFeeBps(
                PURCHASE_FEES_KEY,
                account,
                vaultConfig[VaultConfig.UseDiscount] == 1 ? true : false
            );

        finalFee =
            (((amount * (FEE_BPS_PRECISION + feeBps)) / FEE_BPS_PRECISION) -
                amount) /
            10 ** (OPTION_TOKEN_DECIMALS - COLLATERAL_TOKEN_DECIMALS);

        if (getUsdPrice() < strike) {
            uint256 feeMultiplier = (strike * (10 ** STRIKE_DECIMALS)) /
                getUsdPrice();
            finalFee = (finalFee * feeMultiplier) / 10 ** STRIKE_DECIMALS;
        }
    }

    /**
     * @notice         Calculate premium for an option.
     * @param  _strike Strike price of the option.
     * @param  _amount Amount of options.
     * @return premium in QuoteToken.
     */
    function calculatePremium(
        uint256 _strike,
        uint256 _amount
    ) public view returns (uint256 premium) {
        uint256 currentPrice = getUsdPrice();
        premium = strikeMulAmount(
            IOptionPricing(addresses[Contracts.OptionPricing]).getOptionPrice(
                true,
                _epochData[currentEpoch].expiryTime,
                _strike,
                currentPrice,
                getVolatility(_strike)
            ),
            _amount
        );
    }

    /**
     * @notice       Returns the price of the BaseToken in USD.
     * @return price Price of the base token in 1e8 decimals.
     */
    function getUsdPrice() public view returns (uint256) {
        return
            IPriceOracle(addresses[Contracts.PriceOracle]).getPrice(
                addresses[Contracts.BaseToken],
                false,
                false,
                false
            ) / 10 ** (PRICE_ORACLE_DECIMALS - STRIKE_DECIMALS);
    }

    /**
     * @notice        Returns the volatility from the volatility oracle
     * @param _strike Strike of the option
     */
    function getVolatility(uint256 _strike) public view returns (uint256) {
        return
            (IVolatilityOracle(addresses[Contracts.VolatilityOracle])
                .getVolatility(_strike) *
                (FEE_BPS_PRECISION + vaultConfig[VaultConfig.IvBoost])) /
            FEE_BPS_PRECISION;
    }

    /**
     * @notice         Multiply strike and amount depending on strike
     *                 and options decimals.
     * @param  strike Option strike.
     * @param  amount Amount of options.
     * @return result  Product of strike and amount in collateral/quote
     *                 token decimals.
     */
    function strikeMulAmount(
        uint256 strike,
        uint256 amount
    ) public view returns (uint256 result) {
        uint256 divisor = (STRIKE_DECIMALS + OPTION_TOKEN_DECIMALS) -
            COLLATERAL_TOKEN_DECIMALS;
        return ((strike * amount) / 10 ** divisor);
    }

    /**
     * @notice         A view fn to check if the current epoch of the
     *                 pool is within the exercise window or not.
     * @return whether Whether the current epoch is within exercise
     *                 window of options.
     */
    function isWithinBlackoutWindow() public view returns (bool) {
        uint256 expiry = _epochData[currentEpoch].expiryTime;
        if (expiry == 0) return false;
        return
            block.timestamp >=
            (expiry - vaultConfig[VaultConfig.BlackoutWindow]);
    }

    /**
     * @notice            A view fn to get the state of the options.
     *                    Although by default it returns the state of
     *                    the option but if the epoch of the options
     *                    are expired it will return the state as
     *                    settled.
     * @param _purchaseId ID of the options purchase.
     * @return state      State of the options.
     */
    function getOptionsState(
        uint256 _purchaseId
    ) public view returns (OptionsState) {
        uint256 epoch = _optionsPositions[_purchaseId].epoch;
        if (block.timestamp >= _epochData[epoch].expiryTime) {
            return OptionsState.Settled;
        } else {
            return _optionsPositions[_purchaseId].state;
        }
    }

    /**
     * @param _depositId Epoch of atlantic pool to inquire
     * @return depositAmount Total deposits of user
     * @return premium       Total premiums earned
     * @return borrowFees    Total borrowFees fees earned
     * @return underlying    Total underlying earned on unwinds
     */
    function getWithdrawable(
        uint256 _depositId
    )
        public
        view
        returns (
            uint256 depositAmount,
            uint256 premium,
            uint256 borrowFees,
            uint256 underlying,
            uint256[] memory rewards
        )
    {
        DepositPosition memory userDeposit = _depositPositions[_depositId];
        rewards = new uint256[](
            epochMaxStrikeCheckpoints[userDeposit.epoch][userDeposit.strike]
                .rewardRates
                .length
        );

        rewards = epochMaxStrikeCheckpoints[userDeposit.epoch][
            userDeposit.strike
        ].rewardRates;

        _validate(userDeposit.depositor == msg.sender, 16);

        Checkpoint memory checkpoint = epochMaxStrikeCheckpoints[
            userDeposit.epoch
        ][userDeposit.strike].checkpoints[userDeposit.checkpoint];

        for (uint256 i; i < rewards.length; ) {
            rewards[i] =
                (((userDeposit.liquidity * checkpoint.activeCollateral) /
                    checkpoint.totalLiquidity) * rewards[i]) /
                10 ** COLLATERAL_TOKEN_DECIMALS;

            unchecked {
                ++i;
            }
        }

        borrowFees +=
            (userDeposit.liquidity * checkpoint.borrowFeesAccrued) /
            checkpoint.totalLiquidity;

        premium +=
            (userDeposit.liquidity * checkpoint.premiumAccrued) /
            checkpoint.totalLiquidity;

        underlying +=
            (userDeposit.liquidity * checkpoint.underlyingAccrued) /
            checkpoint.totalLiquidity;

        depositAmount +=
            (userDeposit.liquidity * checkpoint.liquidityBalance) /
            checkpoint.totalLiquidity;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL METHODS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice             Gracefully exercises an atlantic
     *                     sends collateral to integrated protocol,
     *                     underlying to writers.
     * @param unwindAmount Amount charged from caller (unwind amount + fees).
     * @param purchaseId   Options purchase id.
     */
    function unwind(
        uint256 purchaseId,
        uint256 unwindAmount
    ) external onlyRoles(MANAGED_CONTRACT_ROLE) {
        _whenNotPaused();

        _validate(_isVaultBootstrapped(currentEpoch), 7);

        OptionsPurchase memory _userOptionsPurchase = _optionsPositions[
            purchaseId
        ];

        _validate(_userOptionsPurchase.delegate == msg.sender, 9);
        _validate(_userOptionsPurchase.state == OptionsState.Unlocked, 10);

        uint256 expectedUnwindAmount = getUnwindAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        uint256 collateralAccess = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _unwind(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                ((
                    unwindAmount > expectedUnwindAmount
                        ? expectedUnwindAmount
                        : unwindAmount
                ) * _userOptionsPurchase.weights[i]) / WEIGHTS_MUL_DIV,
                (collateralAccess * _userOptionsPurchase.weights[i]) /
                    WEIGHTS_MUL_DIV,
                _userOptionsPurchase.checkpoints[i]
            );

            unchecked {
                ++i;
            }
        }

        // Transfer excess to user.
        if (unwindAmount > expectedUnwindAmount) {
            _safeTransfer(
                addresses[Contracts.BaseToken],
                _userOptionsPurchase.user,
                unwindAmount - expectedUnwindAmount
            );
        }

        _safeTransferFrom(
            addresses[Contracts.BaseToken],
            msg.sender,
            address(this),
            unwindAmount
        );

        delete _optionsPositions[purchaseId];
    }

    /**
     * @notice             Callable by managed contracts that wish
     *                     to relock collateral that was unlocked previously.
     * @param relockAmount Amount of collateral to relock.
     * @param purchaseId   User options purchase id.
     */
    function relockCollateral(
        uint256 purchaseId,
        uint256 relockAmount
    ) external onlyRoles(MANAGED_CONTRACT_ROLE) {
        _whenNotPaused();

        _validate(_isVaultBootstrapped(currentEpoch), 7);

        OptionsPurchase memory _userOptionsPurchase = _optionsPositions[
            purchaseId
        ];

        _validate(_userOptionsPurchase.delegate == msg.sender, 9);
        _validate(_userOptionsPurchase.state == OptionsState.Unlocked, 13);

        uint256 collateralAccess = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        uint256 fundingRefund = calculateFundingFees(
            collateralAccess,
            _userOptionsPurchase.unlockEntryTimestamp
        );

        /// @dev refund = funding charged previsouly - funding charged for borrowing
        fundingRefund =
            fundingRefund -
            (fundingRefund -
                calculateFundingFees(collateralAccess, block.timestamp));

        if (collateralAccess > relockAmount) {
            /**
             * Settle the option if fail to relock atleast collateral amount
             * to disallow reuse of options.
             * */
            _optionsPositions[purchaseId].state = OptionsState.Settled;
            delete fundingRefund;
        } else {
            _optionsPositions[purchaseId].state = OptionsState.Active;
        }

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _relockCollateral(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                (((
                    relockAmount > collateralAccess
                        ? collateralAccess
                        : relockAmount
                ) * _userOptionsPurchase.weights[i]) / WEIGHTS_MUL_DIV),
                ((fundingRefund * _userOptionsPurchase.weights[i]) /
                    WEIGHTS_MUL_DIV),
                _userOptionsPurchase.checkpoints[i]
            );

            unchecked {
                ++i;
            }
        }

        // Transfer to user any excess.
        if (collateralAccess < relockAmount) {
            _safeTransfer(
                addresses[Contracts.QuoteToken],
                _userOptionsPurchase.user,
                relockAmount - collateralAccess
            );
        }

        _safeTransferFrom(
            addresses[Contracts.QuoteToken],
            msg.sender,
            address(this),
            relockAmount
        );

        if (fundingRefund != 0) {
            _safeTransfer(
                addresses[Contracts.QuoteToken],
                _userOptionsPurchase.user,
                fundingRefund
            );
        }
    }

    /**
     * @notice                    Unlock collateral to borrow against AP option.
     *                            Only Callable by managed contracts.
     * @param  purchaseId         User options purchase ID
     * @param  to                 Collateral to transfer to
     * @return unlockedCollateral Amount of collateral unlocked plus fees
     */
    function unlockCollateral(
        uint256 purchaseId,
        address to
    )
        external
        nonReentrant
        onlyRoles(MANAGED_CONTRACT_ROLE)
        returns (uint256 unlockedCollateral)
    {
        _whenNotPaused();

        _validate(_isVaultBootstrapped(currentEpoch), 7);

        OptionsPurchase memory _userOptionsPurchase = _optionsPositions[
            purchaseId
        ];

        unlockedCollateral = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        _validate(_userOptionsPurchase.delegate == msg.sender, 9);
        // Cannot unlock collateral after expiry
        _validate(getOptionsState(purchaseId) == OptionsState.Active, 10);

        _userOptionsPurchase.state = OptionsState.Unlocked;
        _userOptionsPurchase.unlockEntryTimestamp = block.timestamp;

        uint256 borrowFees = calculateFundingFees(
            unlockedCollateral,
            block.timestamp
        );

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _unlockCollateral(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                (_userOptionsPurchase.weights[i] * unlockedCollateral) /
                    WEIGHTS_MUL_DIV,
                (_userOptionsPurchase.weights[i] * borrowFees) /
                    WEIGHTS_MUL_DIV,
                _userOptionsPurchase.checkpoints[i]
            );

            unchecked {
                ++i;
            }
        }

        _optionsPositions[purchaseId] = _userOptionsPurchase;

        /// @dev Transfer out collateral
        _safeTransfer(addresses[Contracts.QuoteToken], to, unlockedCollateral);

        _safeTransferFrom(
            addresses[Contracts.QuoteToken],
            msg.sender,
            address(this),
            borrowFees
        );
    }

    /**
     * @notice           Purchases puts for the current epoch
     * @param _strike    Strike index for current epoch
     * @param _amount    Amount of puts to purchase
     * @param _account   Address of the user options were purchased
     *                   on behalf of.
     * @param _delegate  Address of the delegate who will be in charge
     *                   of the options.
     * @return purchaseId
     */
    function purchase(
        uint256 _strike,
        uint256 _amount,
        address _delegate,
        address _account
    )
        external
        nonReentrant
        onlyRoles(MANAGED_CONTRACT_ROLE)
        returns (uint256 purchaseId)
    {
        _whenNotPaused();
        _validate(!isWithinBlackoutWindow(), 20);

        uint256 epoch = currentEpoch;

        _validate(_isVaultBootstrapped(epoch), 7);
        _validate(_account != address(0), 1);
        _validateParams(_strike, _amount, epoch, _delegate);

        // Calculate liquidity required
        uint256 collateralRequired = strikeMulAmount(_strike, _amount);

        // Should have adequate cumulative liquidity
        _validate(_epochData[epoch].totalLiquidity >= collateralRequired, 11);

        // Price/premium of option
        uint256 premium = calculatePremium(_strike, _amount);

        // Fees on top of premium for fee distributor
        uint256 fees = calculatePurchaseFees(_account, _strike, _amount);

        purchaseId = _newPurchasePosition(
            _account,
            _delegate,
            _strike,
            _amount,
            epoch
        );

        _squeezeMaxStrikes(
            epoch,
            _strike,
            collateralRequired,
            premium,
            purchaseId
        );

        _epochData[epoch].totalLiquidity -= collateralRequired;
        _epochData[epoch].totalActiveCollateral += collateralRequired;

        _safeTransferFrom(
            addresses[Contracts.QuoteToken],
            msg.sender,
            address(this),
            premium
        );

        _safeTransferFrom(
            addresses[Contracts.QuoteToken],
            msg.sender,
            addresses[Contracts.FeeDistributor],
            fees
        );

        emit NewPurchase(
            epoch,
            purchaseId,
            premium,
            fees,
            _account,
            msg.sender
        );
    }

    /**
     * @notice           Deposit liquidity into a max strike for
     *                   current epoch for selected strikes.
     * @param _maxStrike Exact price of strike in 1e8 decimals.
     * @param _liquidity Amount of liquidity to provide in quote token decimals/
     * @param _user      Address of the user to deposit for.
     */
    function deposit(
        uint256 _maxStrike,
        uint256 _liquidity,
        address _user
    ) external nonReentrant returns (uint256 depositId) {
        _isEligibleSender();
        _whenNotPaused();
        uint256 epoch = currentEpoch;
        _validate(_isVaultBootstrapped(epoch), 7);
        _validateParams(_maxStrike, _liquidity, epoch, _user);

        uint256 checkpoint = _updateCheckpoint(epoch, _maxStrike, _liquidity);

        depositId = _newDepositPosition(
            epoch,
            _liquidity,
            _maxStrike,
            checkpoint,
            _user
        );

        _epochData[epoch].totalLiquidity += _liquidity;

        _safeTransferFrom(
            addresses[Contracts.QuoteToken],
            msg.sender,
            address(this),
            _liquidity
        );

        // Emit event
        emit NewDeposit(epoch, _maxStrike, _liquidity, _user, msg.sender);
    }

    /**
     * @notice                        Withdraws balances for a strike from epoch
     *                                deposted in a epoch.
     * @param depositIds              Deposit Ids of the deposit positions.
     */
    function withdraw(
        uint256[] calldata depositIds,
        address receiver
    ) external nonReentrant {
        _whenNotPaused();

        uint256 epoch;
        uint256[] memory rewards;
        uint256 premium;
        uint256 userWithdrawableAmount;
        uint256 borrowFees;
        uint256 underlying;
        for (uint256 i; i < depositIds.length; ) {
            epoch = _depositPositions[depositIds[i]].epoch;

            _validate(_epochData[epoch].state == EpochState.Expired, 4);

            (
                userWithdrawableAmount,
                premium,
                borrowFees,
                underlying,
                rewards
            ) = getWithdrawable(depositIds[i]);

            delete _depositPositions[depositIds[i]];

            if (underlying != 0) {
                _safeTransfer(
                    addresses[Contracts.BaseToken],
                    receiver,
                    underlying
                );
            }

            if (premium + userWithdrawableAmount + borrowFees != 0) {
                _safeTransfer(
                    addresses[Contracts.QuoteToken],
                    receiver,
                    premium + userWithdrawableAmount + borrowFees
                );
            }

            for (uint256 j; j < rewards.length; ) {
                if (rewards[j] != 0) {
                    _safeTransfer(
                        _epochRewards[epoch].rewardTokens[j],
                        receiver,
                        rewards[j]
                    );
                }
                unchecked {
                    ++j;
                }
            }

            emit Withdraw(
                depositIds[i],
                receiver,
                userWithdrawableAmount,
                borrowFees,
                premium,
                underlying,
                rewards
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the current epoch as expired.
    function expireEpoch() external nonReentrant {
        uint256 epoch = currentEpoch;
        _validate(_epochData[epoch].state != EpochState.Expired, 17);
        uint256 epochExpiry = _epochData[epoch].expiryTime;
        _validate((block.timestamp >= epochExpiry), 18);
        _allocateRewardsForStrikes(epoch);
        _epochData[epoch].state = EpochState.Expired;
        emit EpochExpired(msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EXTERNAL VIEWS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice                 Get OptionsPurchase instance for a given positionId.
     * @param  _positionId     ID of the options purchase.
     * @return OptionsPurchase Options purchase data.
     */
    function getOptionsPurchase(
        uint256 _positionId
    ) external view returns (OptionsPurchase memory) {
        return _optionsPositions[_positionId];
    }

    /**
     * @notice                 Get OptionsPurchase instance for a given positionId.
     * @param  _positionId     ID of the options purchase.
     * @return DepositPosition Deposit position data.
     */
    function getDepositPosition(
        uint256 _positionId
    ) external view returns (DepositPosition memory) {
        return _depositPositions[_positionId];
    }

    /**
     * @notice              Get checkpoints of a maxstrike in a epoch.
     * @param  _epoch       Epoch of the pool.
     * @param  _maxStrike   Max strike to query for.
     * @return _checkpoints array of checkpoints of a max strike.
     */
    function getEpochCheckpoints(
        uint256 _epoch,
        uint256 _maxStrike
    ) external view returns (Checkpoint[] memory _checkpoints) {
        _checkpoints = new Checkpoint[](
            epochMaxStrikeCheckpointsLength[_epoch][_maxStrike]
        );

        for (
            uint256 i;
            i < epochMaxStrikeCheckpointsLength[_epoch][_maxStrike];

        ) {
            _checkpoints[i] = epochMaxStrikeCheckpoints[_epoch][_maxStrike]
                .checkpoints[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice            Fetches all max strikes written in a epoch.
     * @param  epoch      Epoch of the pool.
     * @return maxStrikes
     */
    function getEpochStrikes(
        uint256 epoch
    ) external view returns (uint256[] memory maxStrikes) {
        maxStrikes = new uint256[](epochStrikesList[epoch].sizeOf());

        uint256 nextNode = _epochData[epoch].maxStrikesRange.highest;
        uint256 iterator;
        while (nextNode != 0) {
            maxStrikes[iterator] = nextNode;
            iterator++;
            (, nextNode) = epochStrikesList[epoch].getNextNode(nextNode);
        }
    }

    /**
     * @notice Fetch the tick size set for the onGoing epoch.
     * @return tickSize
     */
    function getEpochTickSize(uint256 _epoch) external view returns (uint256) {
        return _epochData[_epoch].tickSize;
    }

    /**
     * @notice Fetch epoch data of an epoch.
     * @return DataOfTheEpoch.
     */
    function getEpochData(
        uint256 _epoch
    ) external view returns (EpochData memory) {
        return _epochData[_epoch];
    }

    /**
     * @notice Fetch rewards set for an epoch.
     * @return RewardsAllocated.
     */
    function getEpochRewards(
        uint256 _epoch
    ) external view returns (EpochRewards memory) {
        return _epochRewards[_epoch];
    }

    /**
     * @notice           Get MaxStrike type data.
     * @param _epoch     Epoch of the pool.
     * @param _maxStrike Max strike to query for.
     */
    function getEpochMaxStrikeData(
        uint256 _epoch,
        uint256 _maxStrike
    )
        external
        view
        returns (uint256 activeCollateral, uint256[] memory rewardRates)
    {
        activeCollateral = epochMaxStrikeCheckpoints[_epoch][_maxStrike]
            .activeCollateral;
        rewardRates = new uint256[](
            epochMaxStrikeCheckpoints[_epoch][_maxStrike].rewardRates.length
        );
        rewardRates = epochMaxStrikeCheckpoints[_epoch][_maxStrike].rewardRates;
    }

    /**
     * @notice Fetch checkpoint data of a max strike.
     * @return Checkpoint data.
     */
    function getEpochMaxStrikeCheckpoint(
        uint256 _epoch,
        uint256 _maxStrike,
        uint256 _checkpoint
    ) external view returns (Checkpoint memory) {
        return
            epochMaxStrikeCheckpoints[_epoch][_maxStrike].checkpoints[
                _checkpoint
            ];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL METHODS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice        Add max strike to strikesList (linked list).
     * @param _strike Strike to add to strikesList.
     * @param _epoch  Epoch of the pool.
     */
    function _addMaxStrike(uint256 _strike, uint256 _epoch) internal {
        uint256 highestMaxStrike = _epochData[_epoch].maxStrikesRange.highest;
        uint256 lowestMaxStrike = _epochData[_epoch].maxStrikesRange.lowest;

        if (_strike > highestMaxStrike) {
            _epochData[_epoch].maxStrikesRange.highest = _strike;
        }
        if (_strike < lowestMaxStrike || lowestMaxStrike == 0) {
            _epochData[_epoch].maxStrikesRange.lowest = _strike;
        }

        // Add new max strike after the next largest strike
        uint256 strikeToInsertAfter = _getSortedSpot(_strike, _epoch);

        if (strikeToInsertAfter == 0)
            epochStrikesList[_epoch].pushBack(_strike);
        else
            epochStrikesList[_epoch].insertBefore(strikeToInsertAfter, _strike);
    }

    /**
     * @notice                 Helper function for unlockCollateral().
     * @param epoch            epoch of the vault.
     * @param maxStrike        Max strike to unlock collateral from.
     * @param collateralAmount Amount of collateral to unlock.
     * @param checkpoint      Checkpoint of the max strike.
     */
    function _unlockCollateral(
        uint256 epoch,
        uint256 maxStrike,
        uint256 collateralAmount,
        uint256 borrowFees,
        uint256 checkpoint
    ) internal {
        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .unlockedCollateral += collateralAmount;

        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .borrowFeesAccrued += borrowFees;

        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .liquidityBalance -= collateralAmount;
        emit UnlockCollateral(epoch, collateralAmount, msg.sender);
    }

    /**
     * @notice                  Update checkpoint states and total unlocked
     *                          collateral for a max strike.
     * @param epoch            Epoch of the pool.
     * @param maxStrike        maxStrike to update states for.
     * @param collateralAmount Collateral token amount relocked.
     * @param borrowFeesRefund Borrow fees to be refunded.
     * @param checkpoint       Checkpoint pointer to update.
     *
     */
    function _relockCollateral(
        uint256 epoch,
        uint256 maxStrike,
        uint256 collateralAmount,
        uint256 borrowFeesRefund,
        uint256 checkpoint
    ) internal {
        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .liquidityBalance += collateralAmount;

        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .unlockedCollateral -= collateralAmount;

        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .borrowFeesAccrued -= borrowFeesRefund;
        emit RelockCollateral(epoch, maxStrike, collateralAmount, msg.sender);
    }

    /**
     *
     * @notice                  Update unwind related states for corr-
     *                          esponding max strikes.
     * @param epoch            Epoch of the options.
     * @param maxStrike        Max strike to update.
     * @param underlyingAmount Amount of underlying to unwind.
     * @param collateralAmount Equivalent collateral amount com-
     *                          pared to options unwinded.
     * @param checkpoint       Checkpoint to update.
     *
     */
    function _unwind(
        uint256 epoch,
        uint256 maxStrike,
        uint256 underlyingAmount,
        uint256 collateralAmount,
        uint256 checkpoint
    ) internal {
        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .underlyingAccrued += underlyingAmount;
        epochMaxStrikeCheckpoints[epoch][maxStrike]
            .checkpoints[checkpoint]
            .unlockedCollateral -= collateralAmount;
        emit Unwind(epoch, maxStrike, underlyingAmount, msg.sender);
    }

    /**
     * @notice           Creates a new checkpoint or update existing
     *                   checkpoint.
     * @param  epoch     Epoch of the pool.
     * @param  maxStrike Max strike deposited into.
     * @param  liquidity Amount of deposits / liquidity to add
     *                   to totalLiquidity, totalLiquidityBalance.
     * @return index     Returns the checkpoint number.
     */
    function _updateCheckpoint(
        uint256 epoch,
        uint256 maxStrike,
        uint256 liquidity
    ) internal returns (uint256 index) {
        index = epochMaxStrikeCheckpointsLength[epoch][maxStrike];

        // Add `maxStrike` if it doesn't exist
        if (epochMaxStrikeCheckpoints[epoch][maxStrike].maxStrike == 0) {
            _addMaxStrike(maxStrike, epoch);
            epochMaxStrikeCheckpoints[epoch][maxStrike].maxStrike = maxStrike;
        }

        if (index == 0) {
            epochMaxStrikeCheckpoints[epoch][maxStrike].checkpoints[index] = (
                Checkpoint(block.timestamp, 0, 0, 0, 0, liquidity, liquidity, 0)
            );
            unchecked {
                ++epochMaxStrikeCheckpointsLength[epoch][maxStrike];
            }
        } else {
            Checkpoint memory currentCheckpoint = epochMaxStrikeCheckpoints[
                epoch
            ][maxStrike].checkpoints[index - 1];

            /**
             * @dev Check if checkpoint interval was exceeded
             *      compared to previous checkpoint start time
             *      if yes then create a new checkpoint or
             *      else accumulate to previous checkpoint.
             */

            /** @dev If a checkpoint's options have active collateral,
             *       add liquidity to next checkpoint.
             */
            if (currentCheckpoint.activeCollateral != 0) {
                epochMaxStrikeCheckpoints[epoch][maxStrike]
                    .checkpoints[index]
                    .startTime = block.timestamp;
                epochMaxStrikeCheckpoints[epoch][maxStrike]
                    .checkpoints[index]
                    .totalLiquidity += liquidity;
                epochMaxStrikeCheckpoints[epoch][maxStrike]
                    .checkpoints[index]
                    .liquidityBalance += liquidity;
                epochMaxStrikeCheckpointsLength[epoch][maxStrike]++;
            } else {
                --index;
                currentCheckpoint.totalLiquidity += liquidity;
                currentCheckpoint.liquidityBalance += liquidity;

                epochMaxStrikeCheckpoints[epoch][maxStrike].checkpoints[
                        index
                    ] = currentCheckpoint;
            }
        }
    }

    /**
     * @notice            Create a deposit position instance and update ID counter.
     * @param _epoch      Epoch of the pool.
     * @param _liquidity  Amount of collateral token deposited.
     * @param _maxStrike     Max strike deposited into.
     * @param _checkpoint Checkpoint of the max strike deposited into.
     * @param _user       Address of the user to deposit for / is depositing.
     */
    function _newDepositPosition(
        uint256 _epoch,
        uint256 _liquidity,
        uint256 _maxStrike,
        uint256 _checkpoint,
        address _user
    ) internal returns (uint256 depositId) {
        depositId = depositPositionsCounter;

        ++depositPositionsCounter;

        _depositPositions[depositId].epoch = _epoch;
        _depositPositions[depositId].strike = _maxStrike;
        _depositPositions[depositId].liquidity = _liquidity;
        _depositPositions[depositId].checkpoint = _checkpoint;
        _depositPositions[depositId].depositor = _user;
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        SafeTransferLib.safeTransfer(_token, _to, _amount);
    }

    function _safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        SafeTransferLib.safeTransferFrom(_token, _from, _to, _amount);
    }

    /**
     * @notice             Create new purchase position positon.
     * @param  _user       Address of the user to create for.
     * @param  _delegate   Address of the delagate who will be
     *                     in charge of the options.
     * @param  _strike     Strike price of the option.
     * @param  _amount     Amount of options.
     * @param  _epoch      Epoch of the pool.
     * @return purchaseId  TokenID and positionID of the purchase position.
     */
    function _newPurchasePosition(
        address _user,
        address _delegate,
        uint256 _strike,
        uint256 _amount,
        uint256 _epoch
    ) internal returns (uint256 purchaseId) {
        purchaseId = purchasePositionsCounter;

        _optionsPositions[purchaseId].user = _user;
        _optionsPositions[purchaseId].delegate = _delegate;
        _optionsPositions[purchaseId].optionStrike = _strike;
        _optionsPositions[purchaseId].optionsAmount = _amount;
        _optionsPositions[purchaseId].epoch = _epoch;
        _optionsPositions[purchaseId].state = OptionsState.Active;

        unchecked {
            ++purchasePositionsCounter;
        }
    }

    /**
     * @notice                    Loop through max strike allocating
     *                            for liquidity for options.
     * @param  epoch              Epoch of the pool.
     * @param  putStrike          Strike to purchase.
     * @param  collateralRequired Amount of collateral to squeeze from
     *                            max strike.
     * @param  premium            Amount of premium to distribute.
     */
    function _squeezeMaxStrikes(
        uint256 epoch,
        uint256 putStrike,
        uint256 collateralRequired,
        uint256 premium,
        uint256 purchaseId
    ) internal {
        uint256 liquidityFromMaxStrikes;
        uint256 liquidityProvided;
        uint256 nextStrike = _epochData[epoch].maxStrikesRange.highest;
        uint256 _liquidityRequired;

        while (liquidityFromMaxStrikes != collateralRequired) {
            _liquidityRequired = collateralRequired - liquidityFromMaxStrikes;

            _validate(putStrike <= nextStrike, 12);

            liquidityProvided = _squeezeMaxStrikeCheckpoints(
                epoch,
                nextStrike,
                collateralRequired,
                _liquidityRequired,
                premium,
                purchaseId
            );

            epochMaxStrikeCheckpoints[epoch][nextStrike]
                .activeCollateral += liquidityProvided;

            liquidityFromMaxStrikes += liquidityProvided;

            (, nextStrike) = epochStrikesList[epoch].getNextNode(nextStrike);
        }
    }

    /**
     * @notice                         Squeezes out liquidity from checkpoints within
     *                                 each max strike/
     * @param epoch                    Epoch of the pool
     * @param maxStrike                Max strike to squeeze liquidity from
     * @param totalCollateralRequired  Total amount of liquidity required for the option
     *                                 purchase/
     * @param collateralRequired       As the loop _squeezeMaxStrikes() accumulates
     *                                 liquidity, this value deducts liquidity is
     *                                 accumulated.
     *                                 collateralRequired = totalCollateralRequired - liquidity
     *                                 accumulated till the max strike in the context of the loop
     * @param premium                  Premium to distribute among the checkpoints and maxstrike
     * @param purchaseId               Options purchase ID
     */
    function _squeezeMaxStrikeCheckpoints(
        uint256 epoch,
        uint256 maxStrike,
        uint256 totalCollateralRequired,
        uint256 collateralRequired,
        uint256 premium,
        uint256 purchaseId
    ) internal returns (uint256 liquidityProvided) {
        uint256 startIndex = epochMaxStrikeCheckpointStartIndex[epoch][
            maxStrike
        ];
        //check if previous checkpoint liquidity all consumed
        if (
            startIndex != 0 &&
            epochMaxStrikeCheckpoints[epoch][maxStrike]
                .checkpoints[startIndex - 1]
                .totalLiquidity >
            epochMaxStrikeCheckpoints[epoch][maxStrike]
                .checkpoints[startIndex - 1]
                .activeCollateral
        ) {
            --startIndex;
        }
        uint256 endIndex;
        // Unchecked since only max strikes with checkpoints != 0 will come to this point
        endIndex = epochMaxStrikeCheckpointsLength[epoch][maxStrike] - 1;
        uint256 liquidityProvidedFromCurrentMaxStrike;

        while (
            startIndex <= endIndex && liquidityProvided != collateralRequired
        ) {
            uint256 availableLiquidity = epochMaxStrikeCheckpoints[epoch][
                maxStrike
            ].checkpoints[startIndex].totalLiquidity -
                epochMaxStrikeCheckpoints[epoch][maxStrike]
                    .checkpoints[startIndex]
                    .activeCollateral;

            uint256 _requiredLiquidity = collateralRequired - liquidityProvided;

            /// @dev if checkpoint has more than required liquidity
            if (availableLiquidity >= _requiredLiquidity) {
                /// @dev Liquidity provided from current max strike at current index
                unchecked {
                    liquidityProvidedFromCurrentMaxStrike = _requiredLiquidity;
                    liquidityProvided += liquidityProvidedFromCurrentMaxStrike;

                    /// @dev Add to active collateral, later if activeCollateral == totalliquidity, then we stop
                    //  coming back to this checkpoint
                    epochMaxStrikeCheckpoints[epoch][maxStrike]
                        .checkpoints[startIndex]
                        .activeCollateral += _requiredLiquidity;

                    /// @dev Add to premium accured
                    epochMaxStrikeCheckpoints[epoch][maxStrike]
                        .checkpoints[startIndex]
                        .premiumAccrued +=
                        (liquidityProvidedFromCurrentMaxStrike * premium) /
                        totalCollateralRequired;
                }

                _updatePurchasePositionMaxStrikesLiquidity(
                    purchaseId,
                    maxStrike,
                    startIndex,
                    (liquidityProvidedFromCurrentMaxStrike * WEIGHTS_MUL_DIV) /
                        totalCollateralRequired
                );
            } else if (availableLiquidity != 0) {
                /// @dev if checkpoint has less than required liquidity
                liquidityProvidedFromCurrentMaxStrike = availableLiquidity;
                unchecked {
                    liquidityProvided += liquidityProvidedFromCurrentMaxStrike;

                    epochMaxStrikeCheckpoints[epoch][maxStrike]
                        .checkpoints[startIndex]
                        .activeCollateral += liquidityProvidedFromCurrentMaxStrike;

                    /// @dev Add to premium accured
                    epochMaxStrikeCheckpoints[epoch][maxStrike]
                        .checkpoints[startIndex]
                        .premiumAccrued +=
                        (liquidityProvidedFromCurrentMaxStrike * premium) /
                        totalCollateralRequired;
                }

                _updatePurchasePositionMaxStrikesLiquidity(
                    purchaseId,
                    maxStrike,
                    startIndex,
                    (liquidityProvidedFromCurrentMaxStrike * WEIGHTS_MUL_DIV) /
                        totalCollateralRequired
                );

                unchecked {
                    ++epochMaxStrikeCheckpointStartIndex[epoch][maxStrike];
                }
            }
            unchecked {
                ++startIndex;
            }
        }
    }

    /**
     * @notice      Allocate rewards for strikes based
     *              on active collateral present.
     * @param epoch Epoch of the pool
     */
    function _allocateRewardsForStrikes(uint256 epoch) internal {
        uint256 nextNode = _epochData[epoch].maxStrikesRange.highest;
        uint256 iterator;

        EpochRewards memory epochRewards = _epochRewards[epoch];
        uint256 activeCollateral;
        uint256 totalEpochActiveCollateral = _epochData[epoch]
            .totalActiveCollateral;
        while (nextNode != 0) {
            activeCollateral = epochMaxStrikeCheckpoints[epoch][nextNode]
                .activeCollateral;

            for (uint256 i; i < epochRewards.rewardTokens.length; ) {
                /**
                 * rewards allocated for a strike:
                 *               strike's active collateral
                 *    rewards *  --------------------------
                 *               total active collateral
                 *
                 * Reward rate per active collateral:
                 *
                 *      rewards allocated
                 *      ------------------
                 *   strike's active collateral
                 */

                if (activeCollateral != 0) {
                    epochMaxStrikeCheckpoints[epoch][nextNode].rewardRates.push(
                            (((activeCollateral * epochRewards.amounts[i]) /
                                totalEpochActiveCollateral) *
                                (10 ** COLLATERAL_TOKEN_DECIMALS)) /
                                activeCollateral
                        );
                }
                unchecked {
                    ++i;
                }
            }

            iterator++;
            (, nextNode) = epochStrikesList[epoch].getNextNode(nextNode);
        }
    }

    /**
     * @notice            Pushes new item into strikes, checkpoints and
     *                    weights in a single-go for a options purchase
     *                    instance.
     * @param _purchaseId Options purchase ID
     * @param _maxStrike  Maxstrike to push into strikes array of the
     *                    options purchase.
     * @param _checkpoint Checkpoint to push into checkpoints array of
     *                    the options purchase.
     * @param _weight     Weight (%) to push into weights array of the
     *                    options purchase in 1e18 decimals.
     */
    function _updatePurchasePositionMaxStrikesLiquidity(
        uint256 _purchaseId,
        uint256 _maxStrike,
        uint256 _checkpoint,
        uint256 _weight
    ) internal {
        _optionsPositions[_purchaseId].strikes.push(_maxStrike);
        _optionsPositions[_purchaseId].checkpoints.push(_checkpoint);
        _optionsPositions[_purchaseId].weights.push(_weight);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL VIEWS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Validate params for purchase and deposit.
     * @param _strike Strike price for the option.
     * @param _amount Amount of options or liquidity added.
     * @param _epoch  Epoch of the pool.
     * @param _user   User address provided.
     */

    function _validateParams(
        uint256 _strike,
        uint256 _amount,
        uint256 _epoch,
        address _user
    ) internal view {
        _validate(_user != address(0), 1);
        _validate(_amount != 0, 3);
        _validate(
            _strike != 0 && _strike % _epochData[_epoch].tickSize == 0,
            5
        );
    }

    /**
     * @notice              Revert-er function to revert with string error message.
     * @param trueCondition Similar to require, a condition that has to be false
     *                      to revert.
     * @param errorCode     Index in the errors[] that was set in error controller.
     */
    function _validate(bool trueCondition, uint256 errorCode) internal pure {
        if (!trueCondition) {
            revert AtlanticPutsPoolError(errorCode);
        }
    }

    /**
     * @notice       Checks if vault is not expired and bootstrapped.
     * @param  epoch Epoch of the pool.
     * @return isVaultBootstrapped
     */
    function _isVaultBootstrapped(uint256 epoch) internal view returns (bool) {
        return
            _epochData[epoch].state == EpochState.BootStrapped &&
            block.timestamp <= _epochData[epoch].expiryTime;
    }

    /**
     * @param  _value Value of max strike / node
     * @param  _epoch Epoch of the pool
     * @return tail   of the linked list
     */
    function _getSortedSpot(
        uint256 _value,
        uint256 _epoch
    ) private view returns (uint256) {
        if (epochStrikesList[_epoch].sizeOf() == 0) {
            return 0;
        }

        uint256 next;
        (, next) = epochStrikesList[_epoch].getAdjacent(0, true);
        // Switch to descending
        while (
            (next != 0) &&
            (
                (_value <
                    (
                        epochMaxStrikeCheckpoints[_epoch][next].maxStrike != 0
                            ? next
                            : 0
                    ))
            )
        ) {
            next = epochStrikesList[_epoch].list[next][true];
        }
        return next;
    }

    /**
     * @dev         checks for contract or eoa addresses
     * @param  addr the address to check
     * @return bool whether the passed address is a contract address
     */
    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size != 0;
    }

    /**
     * @notice Check for whitelisted contracts.
     */
    function _isEligibleSender() internal view {
        // the below condition checks whether the caller is a contract or not
        if (msg.sender != tx.origin) {
            _checkRoles(WHITELISTED_CONTRACT_ROLE);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN METHODS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice        Set  vault configurations.
     * @param _types   Configuration type.
     * @param _configs Configuration parameter.
     */
    function setVaultConfigs(
        VaultConfig[] calldata _types,
        uint256[] calldata _configs
    ) external onlyRoles(ADMIN_ROLE) {
        _validate(_types.length == _configs.length, 0);
        for (uint256 i; i < _types.length; ) {
            vaultConfig[_types[i]] = _configs[i];
            emit VaultConfigSet(_types[i], _configs[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice          Sets (adds) a list of addresses to the address list.
     * @dev             an only be called by the owner.
     * @param _types     Contract type to set from Contracs enum
     * @param _addresses  address of the contract.
     */
    function setAddresses(
        Contracts[] calldata _types,
        address[] calldata _addresses
    ) external onlyRoles(ADMIN_ROLE) {
        _validate(_types.length == _addresses.length, 0);
        for (uint256 i; i < _types.length; ) {
            _validate(_addresses[i] != address(0), 1);
            addresses[_types[i]] = _addresses[i];
            emit AddressSet(_types[i], _addresses[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Pauses the vault for emergency cases.
     * @dev    Can only be called by the owner.
     */
    function pause() external onlyRoles(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the vault
     * @dev    Can only be called by the owner
     */

    function unpause() external onlyRoles(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Transfers all funds to msg.sender
     * @dev Can only be called by DEFAULT_ADMIN_ROLE
     * @param tokens The list of erc20 tokens to withdraw
     * @param transferNative Whether should transfer the native currency
     */
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external onlyRoles(ADMIN_ROLE) returns (bool) {
        _whenPaused();
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        for (uint256 i; i < tokens.length; ) {
            _safeTransfer(
                tokens[i],
                msg.sender,
                IERC20(tokens[i]).balanceOf(address(this))
            );
            unchecked {
                ++i;
            }
        }

        emit EmergencyWithdraw(msg.sender);

        return true;
    }

    /**
     * @notice              Set rewards for an upcoming epoch.
     * @param _rewardTokens Addresses of the reward tokens.
     * @param _amounts      Amounts of tokens to reward.
     * @param _epoch        Upcoming epoch.
     */
    function setEpochRewards(
        address[] calldata _rewardTokens,
        uint256[] calldata _amounts,
        uint256 _epoch
    ) external onlyRoles(ADMIN_ROLE) {
        _validate(_rewardTokens.length == _amounts.length, 0);

        for (uint256 i; i < _rewardTokens.length; ) {
            _safeTransferFrom(
                _rewardTokens[i],
                msg.sender,
                address(this),
                _amounts[i]
            );

            _epochRewards[_epoch].rewardTokens.push(_rewardTokens[i]);
            _epochRewards[_epoch].amounts.push(_amounts[i]);
            
            emit EpochRewardsSet(_epoch, _amounts[i], _rewardTokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Bootstraps a new epoch, sets the strike based on offset% set. To be called after expiry
     *         of every epoch. Ensure strike offset is set before calling this function
     * @param  expiry   Expiry of the epoch to set.
     * @param  tickSize Spacing between max strikes.
     * @return success
     */
    function bootstrap(
        uint256 expiry,
        uint256 tickSize
    ) external nonReentrant onlyRoles(BOOSTRAPPER_ROLE) returns (bool) {
        _validate(expiry > block.timestamp, 2);
        _validate(tickSize != 0, 3);

        uint256 nextEpoch = currentEpoch + 1;

        EpochData memory _vaultState = _epochData[nextEpoch];

        // Prev epoch must be expired
        if (currentEpoch > 0)
            _validate(_epochData[nextEpoch - 1].state == EpochState.Expired, 4);

        _vaultState.startTime = block.timestamp;
        _vaultState.tickSize = tickSize;
        _vaultState.expiryTime = expiry;
        _vaultState.state = EpochState.BootStrapped;

        currentEpoch = nextEpoch;

        _epochData[nextEpoch] = _vaultState;

        emit Bootstrap(nextEpoch);

        return true;
    }
}

