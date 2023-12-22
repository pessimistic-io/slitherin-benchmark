//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;
/**                                                                                                 
          █████╗ ████████╗██╗      █████╗ ███╗   ██╗████████╗██╗ ██████╗
          ██╔══██╗╚══██╔══╝██║     ██╔══██╗████╗  ██║╚══██╔══╝██║██╔════╝
          ███████║   ██║   ██║     ███████║██╔██╗ ██║   ██║   ██║██║     
          ██╔══██║   ██║   ██║     ██╔══██║██║╚██╗██║   ██║   ██║██║     
          ██║  ██║   ██║   ███████╗██║  ██║██║ ╚████║   ██║   ██║╚██████╗
          ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝ ╚═════╝
                                                                        
          ██████╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗       
          ██╔═══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝       
          ██║   ██║██████╔╝   ██║   ██║██║   ██║██╔██╗ ██║███████╗       
          ██║   ██║██╔═══╝    ██║   ██║██║   ██║██║╚██╗██║╚════██║       
          ╚██████╔╝██║        ██║   ██║╚██████╔╝██║ ╚████║███████║       
          ╚═════╝ ╚═╝        ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝       
                                                               
*/

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {StructuredLinkedList} from "./StructuredLinkedList.sol";
import {AccessControl} from "./AccessControl.sol";
import {Pausable} from "./Pausable.sol";
import {StructuredLinkedList} from "./StructuredLinkedList.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IDopexFeeStrategy} from "./IDopexFeeStrategy.sol";

// Structs
import {VaultState, Addresses, OptionsPurchase, DepositPosition, Checkpoint} from "./AtlanticsStructs.sol";

contract AtlanticPutsPool is
    Pausable,
    ReentrancyGuard,
    AccessControl,
    ContractWhitelist
{
    using SafeERC20 for IERC20;
    using StructuredLinkedList for StructuredLinkedList.List;

    uint256 private constant PURCHASE_FEES_KEY = 0;
    uint256 private constant FUNDING_FEES_KEY = 1;
    uint256 private constant SETTLEMENT_FEES_KEY = 2;
    uint256 private constant FEE_BPS_PRECISION = 10000000;

    /// @dev Number of deicmals of deposit/premium token
    uint256 private immutable COLLATERAL_TOKEN_DECIMALS;

    /// @dev Options amounts precision
    uint256 private constant OPTION_TOKEN_DECIMALS = 18;

    /// @dev Number of decimals for max strikes
    uint256 private constant STRIKE_DECIMALS = 8;

    /// @dev Max strike weights divisor/multiplier
    uint256 private constant WEIGHTS_MUL_DIV = 1e18;

    /// @dev Manager role which handles bootstrapping
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Ongoing epoch of the pool
    uint256 public currentEpoch;

    /// @notice Counter for deposit IDs
    uint256 public depositIdCount = 1;

    /// @notice Counter for option purchase IDs
    uint256 public purchaseIdCount = 1;

    /// @notice Track deposit positions of users
    /// @dev ID => DepositPosition
    mapping(uint256 => DepositPosition) private userDepositPositions;

    /// @notice Track option purchases of users
    /// @dev ID => OptionsPurchase
    mapping(uint256 => OptionsPurchase) private userOptionsPurchases;

    /// @dev epoch => vaultState
    mapping(uint256 => VaultState) public epochVaultStates;

    /// @notice Addresses this contract uses
    Addresses public addresses;

    /**
     * @notice Mapping of max strikes to MaxStrike struct
     * @dev    epoch => strike/node => MaxStrike
     */
    mapping(uint256 => mapping(uint256 => bool)) private isValidStrike;

    /**
     * @notice Mapping to keep track of managed contracts
     * @dev    Contract address => is managed contract?
     */
    mapping(address => bool) public managedContracts;

    /**
     * @notice Total liquidity in a epoch
     * @dev    epoch => liquidity
     */
    mapping(uint256 => uint256) public totalEpochCummulativeLiquidity;

    /**
     * @notice Structured linked list for max strikes
     * @dev    epoch => strike list
     */
    mapping(uint256 => StructuredLinkedList.List) private epochStrikesList;

    /**
     * @notice Checkpoints for a max strike in a epoch
     * @dev    epoch => max strike => Checkpoint[]
     */
    mapping(uint256 => mapping(uint256 => mapping(uint256 => Checkpoint)))
        public epochMaxStrikeCheckpoints;

    mapping(uint256 => mapping(uint256 => uint256))
        public epochMaxStrikeCheckpointsLength;

    uint256 public expireDelayTolerance;

    /**
     *  @notice Start index of checkpoint (reference point to
     *           loop from on _squeeze())
     *  @dev    epoch => index
     */
    mapping(uint256 => mapping(uint256 => uint256))
        public epochMaxStrikeCheckpointStartIndex;

    mapping(uint256 => uint256[2]) public epochMaxStrikesRange;

    mapping(uint256 => uint256) public epochTickSize;

    mapping(address => bool) public whitelistedUsers;

    uint256 public expiryWindow = 1 hours;

    uint256 public fundingInterval;

    bool public isWhitelistUserMode = true;

    bool public useDiscountForFees = true;

    error AtlanticPutsPoolError(uint256 errorCode);

    /*==== EVENTS ====*/

    event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

    event EmergencyWithdraw(address sender);

    event Bootstrap(uint256 epoch);

    event NewDeposit(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        address user,
        address sender
    );

    event NewPurchase(
        uint256 epoch,
        uint256 purchaseId,
        uint256 premium,
        uint256 fee,
        address user,
        address sender
    );

    event NewWithdraw(
        uint256 epoch,
        uint256 strike,
        uint256 checkpoint,
        address user,
        uint256 withdrawableAmount,
        uint256 borrowFees,
        uint256 premium,
        uint256 underlying
    );

    event Unwind(uint256 epoch, uint256 strike, uint256 amount, address caller);

    event UnlockCollateral(
        uint256 epoch,
        uint256 totalCollateral,
        address caller
    );

    event NewSettle(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl
    );

    event RelockCollateral(
        uint256 epoch,
        uint256 strike,
        uint256 totalCollateral,
        address caller
    );

    event EpochExpired(address sender, uint256 settlementPrice);

    event FundingIntervalSet(uint256 _interval);

    event ManagedContractSet(address _managedContract, bool _setAs);

    event UseDiscountForFeesSet(bool _setAs);

    /*==== CONSTRUCTOR ====*/

    constructor(
        Addresses memory _addresses,
        uint256 _expiryDelayTolerance,
        uint256 _fundingInterval
    ) {
        COLLATERAL_TOKEN_DECIMALS = IERC20(_addresses.quoteToken).decimals();
        addresses = _addresses;
        expireDelayTolerance = _expiryDelayTolerance;
        fundingInterval = _fundingInterval;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
    }

    /// @notice Sets the current epoch as expired.
    function expireEpoch() external nonReentrant {
        _whenNotPaused();
        _isEligibleSender();
        _validate(!epochVaultStates[currentEpoch].isVaultExpired, 0);
        uint256 epochExpiry = epochVaultStates[currentEpoch].expiryTime;
        _validate((block.timestamp >= epochExpiry), 1);
        _validate(block.timestamp <= epochExpiry + expireDelayTolerance, 2);
        epochVaultStates[currentEpoch].settlementPrice = getUsdPrice();
        epochVaultStates[currentEpoch].isVaultExpired = true;

        emit EpochExpired(msg.sender, getUsdPrice());
    }

    /// @notice Sets the current epoch as expired. Only can be called by DEFAULT_ADMIN_ROLE.
    /// @param settlementPrice The settlement price
    function expireEpoch(
        uint256 settlementPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whenNotPaused();
        uint256 epoch = currentEpoch;
        _validate(!epochVaultStates[epoch].isVaultExpired, 0);
        _validate(
            (block.timestamp >
                epochVaultStates[epoch].expiryTime + expireDelayTolerance),
            3
        );
        epochVaultStates[epoch].settlementPrice = settlementPrice;
        epochVaultStates[epoch].isVaultExpired = true;

        emit EpochExpired(msg.sender, settlementPrice);
    }

    /*==== SETTER METHODS ====*/

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by the owner
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by the owner
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(
        address _contract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(
        address _contract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Updates the delay tolerance for the expiry epoch function
    /// @dev Can only be called by the owner
    function updateExpireDelayTolerance(
        uint256 _expireDelayTolerance
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        expireDelayTolerance = _expireDelayTolerance;
        emit ExpireDelayToleranceUpdate(_expireDelayTolerance);
    }

    /// @notice Sets (adds) a list of addresses to the address list
    /// @dev Can only be called by the owner
    /// @param _addresses addresses of contracts in the Addresses struct
    function setAddresses(
        Addresses calldata _addresses
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        addresses = _addresses;
    }

    /// @notice Add a managed contract
    /// @param _managedContract Address of the managed contract
    function setManagedContract(
        address _managedContract,
        bool _setAs
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        managedContracts[_managedContract] = _setAs;
        emit ManagedContractSet(_managedContract, _setAs);
    }

    /// @notice Set interval for funding charged.
    /// @param _interval Interval to set. Note: Max 1 day
    function setFundingInterval(
        uint256 _interval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validate(_interval <= 1 days, 24);
        fundingInterval = _interval;
        emit FundingIntervalSet(_interval);
    }

    // /*==== METHODS ====*/

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by DEFAULT_ADMIN_ROLE
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _whenPaused();
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        for (uint256 i; i < tokens.length; ) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }

        emit EmergencyWithdraw(msg.sender);

        return true;
    }

    /**
     * @notice Create a deposit position instance and update ID counter
     * @param _epoch      `Epoch of the pool
     * @param _liquidity  Amount of collateral token deposited
     * @param _maxStrike  Max strike deposited into
     * @param _checkpoint Checkpoint of the max strike deposited into
     * @param _user       Address of the user to deposit for / is depositing
     */
    function _newDepositPosition(
        uint256 _epoch,
        uint256 _liquidity,
        uint256 _maxStrike,
        uint256 _checkpoint,
        address _user
    ) internal returns (uint256 depositId) {
        depositId = depositIdCount;
        userDepositPositions[depositId] = DepositPosition(
            _epoch,
            _maxStrike,
            block.timestamp,
            _liquidity,
            _checkpoint,
            _user
        );
        unchecked {
            ++depositIdCount;
        }
    }

    /**
     * @notice Deposits USD into the ssov-p to mint puts in the next epoch for selected strikes
     * @param _maxStrike Exact price of strike in 1e8 decimals
     * @param _liquidity Amount of liquidity to provide in 1e6 decimals
     * @param _user      Address of the user to deposit for
     */
    function deposit(
        uint256 _maxStrike,
        uint256 _liquidity,
        address _user
    ) external nonReentrant whitelistCheck returns (uint256 depositId) {
        _isEligibleSender();
        _whenNotPaused();
        _validate(_maxStrike <= getUsdPrice(), 4);

        uint256 epoch = currentEpoch;

        _validate(_isVaultReady(epoch), 5);
        _validate(_liquidity > 0, 6);
        _validate(_isValidMaxStrike(_maxStrike, epoch), 7);

        uint256 checkpoint = _updateCheckpoint(epoch, _maxStrike, _liquidity);
        depositId = _newDepositPosition(
            epoch,
            _liquidity,
            _maxStrike,
            checkpoint,
            _user
        );

        _safeTransferFrom(
            addresses.quoteToken,
            msg.sender,
            address(this),
            _liquidity
        );

        totalEpochCummulativeLiquidity[epoch] += _liquidity;

        // Add `maxStrike` if it doesn't exist
        if (!isValidStrike[epoch][_maxStrike]) {
            _addMaxStrike(_maxStrike, epoch);
            isValidStrike[epoch][_maxStrike] = true;
        }

        // Emit event
        emit NewDeposit(epoch, _maxStrike, _liquidity, _user, msg.sender);
    }

    /**
     * @notice Purchases puts for the current epoch
     * @param _strike    Strike index for current epoch
     * @param _amount    Amount of puts to purchase
     * @param _receiver      Address to which options would belong to.
     * @param _account   Address of the user options were purchased
     *                   on behalf of.
     */
    function purchase(
        uint256 _strike,
        uint256 _amount,
        address _receiver,
        address _account
    ) external payable nonReentrant returns (uint256 purchaseId) {
        _whenNotPaused();
        _isManagedContract();
        _validate(_amount > 0, 8);

        uint256 epoch = currentEpoch;

        _validate(_isValidMaxStrike(_strike, epoch), 7);
        _validate(_isVaultReady(epoch), 5);
        _validate(_strike <= epochMaxStrikesRange[epoch][0], 9);

        // Calculate liquidity required
        uint256 collateralRequired = strikeMulAmount(_strike, _amount);

        // Should have adequate cumulative liquidity
        _validate(
            totalEpochCummulativeLiquidity[epoch] >= collateralRequired,
            10
        );

        // Price/premium of option
        uint256 premium = calculatePremium(_strike, _amount);

        // Fees on top of premium for fee distributor
        uint256 fees = calculatePurchaseFees(_account, _strike, _amount);

        purchaseId = _squeezeMaxStrikes(
            epoch,
            _strike,
            collateralRequired,
            _amount,
            premium,
            _receiver
        );

        totalEpochCummulativeLiquidity[epoch] -= collateralRequired;

        _safeTransferFrom(
            addresses.quoteToken,
            msg.sender,
            address(this),
            premium
        );
        _safeTransferFrom(
            addresses.quoteToken,
            msg.sender,
            addresses.feeDistributor,
            fees
        );

        emit NewPurchase(
            epoch,
            purchaseId,
            premium,
            fees,
            _receiver,
            msg.sender
        );
    }

    function _newPurchasePosition(
        address _user,
        uint256 _putStrike,
        uint256 _amount,
        uint256 _epoch
    ) internal returns (uint256 purchaseId) {
        purchaseId = purchaseIdCount;
        userOptionsPurchases[purchaseId].user = _user;
        userOptionsPurchases[purchaseId].optionStrike = _putStrike;
        userOptionsPurchases[purchaseId].optionsAmount = _amount;
        userOptionsPurchases[purchaseId].epoch = _epoch;
        unchecked {
            ++purchaseIdCount;
        }
    }

    /**
     * @notice Loop through max strike looking for liquidity
     * @param epoch              Epoch of the pool
     * @param putStrike          Strike to purchase
     * @param collateralRequired Amount of collateral to squeeze from max strike
     * @param amount             Amount of options to buy
     * @param premium            Amount of premium to distribute
     * @param user               Address of the user purchasing
     */
    function _squeezeMaxStrikes(
        uint256 epoch,
        uint256 putStrike,
        uint256 collateralRequired,
        uint256 amount,
        uint256 premium,
        address user
    ) internal returns (uint256 purchaseId) {
        uint256 liquidityFromMaxStrikes;
        uint256 liquidityProvided;
        uint256 nextStrike = epochMaxStrikesRange[epoch][0];
        uint256 _liquidityRequired;

        purchaseId = _newPurchasePosition(user, putStrike, amount, epoch);

        while (liquidityFromMaxStrikes != collateralRequired) {
            // Unchecked because liquidityProvided from _squeeze max strikes
            // will either be equal or less than collateral required
            unchecked {
                _liquidityRequired =
                    collateralRequired -
                    liquidityFromMaxStrikes;
            }

            _validate(putStrike <= nextStrike, 22);

            liquidityProvided = _squeezeMaxStrikeCheckpoints(
                epoch,
                nextStrike,
                collateralRequired,
                _liquidityRequired,
                premium,
                purchaseId
            );
            unchecked {
                liquidityFromMaxStrikes += liquidityProvided;
            }

            (, nextStrike) = epochStrikesList[epoch].getNextNode(nextStrike);
        }
    }

    /**
     * @notice Pushes new item into strikes, checkpoints and weights in a single-go.
     *         of a options purchase instance
     * @param _purchaseId Options purchase ID
     * @param _maxStrike  Maxstrike to push into strikes array of the options purchase
     * @param _checkpoint Checkpoint to push into checkpoints array of the options purchase
     * @param _weight     Weight (%) to push into weights array of the options purchase
     */
    function _updatePurchasePositionMaxStrikesLiquidity(
        uint256 _purchaseId,
        uint256 _maxStrike,
        uint256 _checkpoint,
        uint256 _weight
    ) internal {
        userOptionsPurchases[_purchaseId].strikes.push(_maxStrike);
        userOptionsPurchases[_purchaseId].checkpoints.push(_checkpoint);
        userOptionsPurchases[_purchaseId].weights.push(_weight);
    }

    /**
     * @notice Squeezes out liquidity from checkpoints within each max strike
     * @param epoch                    Epoch of the pool
     * @param maxStrike                Max strike to squeeze liquidity from
     * @param totalCollateralRequired  Total amount of liquidity required for the option purchase
     * @param collateralRequired       As the loop _squeezeMaxStrikes() accumulates liquidity, this value deducts
     *                                 liquidity is accumulated. collateralRequired = totalCollateralRequired - liquidity
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
            startIndex > 0 &&
            epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex - 1]
                .totalLiquidity >
            epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex - 1]
                .activeCollateral
        ) {
            unchecked {
                --startIndex;
            }
        }
        uint256 endIndex;
        // Unchecked since only max strikes with checkpoints > 0 will come to this point
        unchecked {
            endIndex = epochMaxStrikeCheckpointsLength[epoch][maxStrike] - 1;
        }
        uint256 liquidityProvidedFromCurrentMaxStrike;

        while (
            startIndex <= endIndex && liquidityProvided != collateralRequired
        ) {
            uint256 availableLiquidity = epochMaxStrikeCheckpoints[epoch][
                maxStrike
            ][startIndex].totalLiquidity -
                epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex]
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
                    epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex]
                        .activeCollateral += _requiredLiquidity;

                    /// @dev Add to premium accured
                    epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex]
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

                    epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex]
                        .activeCollateral += liquidityProvided;

                    /// @dev Add to premium accured
                    epochMaxStrikeCheckpoints[epoch][maxStrike][startIndex]
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
     * @notice Unlock collateral to borrow against AP option. Only Callable by managed contracts
     * @param  purchaseId        User options purchase ID
     * @param  to                Collateral to transfer to
     * @return unlockedCollateral Amount of collateral unlocked plus fees
     */
    function unlockCollateral(
        uint256 purchaseId,
        address to,
        address account
    ) external nonReentrant returns (uint256 unlockedCollateral) {
        _isEligibleSender();
        _whenNotPaused();

        _validate(_isVaultReady(currentEpoch), 5);

        OptionsPurchase memory _userOptionsPurchase = userOptionsPurchases[
            purchaseId
        ];

        unlockedCollateral = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        _validate(_userOptionsPurchase.user == msg.sender, 12);
        _validate(!_userOptionsPurchase.unlock, 16);

        _userOptionsPurchase.unlock = true;

        uint256 borrowFees = calculateFundingFees(account, unlockedCollateral);

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _unlockCollateral(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                /**
                 *     contribution% * collateral access
                 */
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

        userOptionsPurchases[purchaseId] = _userOptionsPurchase;

        /// @dev Transfer out collateral
        _safeTransfer(addresses.quoteToken, to, unlockedCollateral);
        _safeTransferFrom(
            addresses.quoteToken,
            msg.sender,
            address(this),
            borrowFees
        );
    }

    /**
     * @notice Helper function for unlockCollateral()
     * @param epoch            epoch of the vault
     * @param maxStrike        Max strike to unlock collateral from
     * @param collateralAmount Amount of collateral to unlock
     * @param _checkpoint      Checkpoint of the max strike.
     */
    function _unlockCollateral(
        uint256 epoch,
        uint256 maxStrike,
        uint256 collateralAmount,
        uint256 borrowFees,
        uint256 _checkpoint
    ) internal {
        unchecked {
            epochMaxStrikeCheckpoints[epoch][maxStrike][_checkpoint]
                .unlockedCollateral += collateralAmount;

            epochMaxStrikeCheckpoints[epoch][maxStrike][_checkpoint]
                .fundingFeesAccrued += borrowFees;
        }

        epochMaxStrikeCheckpoints[epoch][maxStrike][_checkpoint]
            .totalLiquidityBalance -= collateralAmount;

        emit UnlockCollateral(epoch, collateralAmount, msg.sender);
    }

    /**
     * @notice Callable by managed contracts that wish to relock collateral that was unlocked previously
     * @param purchaseId          User options purchase id
     * @param collateralToCollect Amount of collateral to repay in collateral token decimals
     */
    function relockCollateral(
        uint256 purchaseId
    ) external returns (uint256 collateralToCollect) {
        _isEligibleSender();
        _whenNotPaused();

        _validate(_isVaultReady(currentEpoch), 5);
        OptionsPurchase memory _userOptionsPurchase = userOptionsPurchases[
            purchaseId
        ];

        _validate(_userOptionsPurchase.user == msg.sender, 23);
        _validate(_userOptionsPurchase.unlock, 17);

        collateralToCollect = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _relockCollateral(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                ((collateralToCollect * _userOptionsPurchase.weights[i]) /
                    WEIGHTS_MUL_DIV),
                _userOptionsPurchase.checkpoints[i]
            );

            unchecked {
                ++i;
            }
        }

        delete userOptionsPurchases[purchaseId].unlock;

        _safeTransferFrom(
            addresses.quoteToken,
            msg.sender,
            address(this),
            collateralToCollect
        );
    }

    /**
     * @notice Update checkpoint states and total unlocked collateral for a max strike
     * @param epoch            Epoch of the pool
     * @param maxStrike        maxStrike to update states for
     * @param collateralAmount Collateral token amount relocked
     * @param checkpoint       Checkpoint pointer to update
     */
    function _relockCollateral(
        uint256 epoch,
        uint256 maxStrike,
        uint256 collateralAmount,
        uint256 checkpoint
    ) internal {
        // Unchecked since collateral relocked cannot be collateral unlocked
        unchecked {
            epochMaxStrikeCheckpoints[epoch][maxStrike][checkpoint]
                .totalLiquidityBalance += collateralAmount;
        }

        epochMaxStrikeCheckpoints[epoch][maxStrike][checkpoint]
            .unlockedCollateral -= collateralAmount;

        emit RelockCollateral(epoch, maxStrike, collateralAmount, msg.sender);
    }

    function getUnwindAmount(
        uint256 _optionsAmount,
        uint256 _optionStrike
    ) public view returns (uint256 unwindAmount) {
        if (_optionStrike < getUsdPrice()) {
            unwindAmount = (_optionsAmount * _optionStrike) / getUsdPrice();
        } else {
            unwindAmount = _optionsAmount;
        }
    }

    /**
     * @notice Settle options in expiry window
     * @param purchaseId ID of options purchase
     * @param receiver   Address of Pnl receiver
     * @param pnlToUser  Total PnL
     */
    function settle(
        uint256 purchaseId,
        address receiver
    ) external returns (uint256 pnlToUser) {
        _isEligibleSender();
        _whenNotPaused();
        _isManagedContract();

        uint256 epoch = currentEpoch;
        uint256 settlementPrice = epochVaultStates[epoch].settlementPrice;
        uint256 expiry = epochVaultStates[epoch].expiryTime;

        _validate(isWithinExerciseWindow(), 13);

        if (expiry >= block.timestamp) {
            settlementPrice = getUsdPrice();
        }

        OptionsPurchase memory _userOptionsPurchase = userOptionsPurchases[
            purchaseId
        ];
        _validate(_userOptionsPurchase.user == msg.sender, 12);

        uint256 pnl = calculatePnl(
            settlementPrice,
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );

        _validate(pnl > 0, 14);

        uint256 _pnl;

        IERC20 settlementToken = IERC20(addresses.quoteToken);

        uint256 unlockedCollateral = strikeMulAmount(
            _userOptionsPurchase.optionStrike,
            _userOptionsPurchase.optionsAmount
        );
        uint256 settlement = unlockedCollateral - pnl;

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            _pnl = (pnl * _userOptionsPurchase.weights[i]) / WEIGHTS_MUL_DIV;

            if (_userOptionsPurchase.unlock) {
                _relockCollateral(
                    _userOptionsPurchase.epoch,
                    _userOptionsPurchase.strikes[i],
                    (settlement * _userOptionsPurchase.weights[i]) /
                        WEIGHTS_MUL_DIV,
                    _userOptionsPurchase.checkpoints[i]
                );
            } else {
                epochMaxStrikeCheckpoints[epoch][
                    _userOptionsPurchase.strikes[i]
                ][_userOptionsPurchase.checkpoints[i]]
                    .totalLiquidityBalance -= _pnl;
                pnlToUser += _pnl;
            }
            unchecked {
                ++i;
            }
        }

        if (_userOptionsPurchase.unlock) {
            settlementToken.safeTransferFrom(
                msg.sender,
                address(this),
                settlement
            );
        } else {
            // Transfer PnL to user
            settlementToken.safeTransfer(receiver, pnlToUser);
        }

        delete userOptionsPurchases[purchaseId];

        // Emit event
        emit NewSettle(
            epoch,
            _userOptionsPurchase.optionStrike,
            msg.sender,
            _userOptionsPurchase.optionsAmount,
            pnl
        );
    }

    /**
     * @notice Calculate Pnl
     * @param price price of BaseToken
     * @param strike strike price of the option
     * @param amount amount of options
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
     * @notice Calculate funding fees based on days left till expiry.
     *
     * @param _collateralAccess Amount of collateral borrowed.
     * @return fees
     */
    function calculateFundingFees(
        address _account,
        uint256 _collateralAccess
    ) public view returns (uint256 fees) {
        uint256 feeBps = IDopexFeeStrategy(addresses.feeStrategy).getFeeBps(
            FUNDING_FEES_KEY,
            _account,
            useDiscountForFees
        );

        uint256 hoursLeftTillExpiry = ((epochVaultStates[currentEpoch]
            .expiryTime - block.timestamp) * 10000) / fundingInterval;

        uint256 finalBps = (feeBps * hoursLeftTillExpiry) / 10000;

        if (finalBps == 0) {
            finalBps = feeBps;
        }

        fees =
            ((_collateralAccess * (FEE_BPS_PRECISION + finalBps)) /
                FEE_BPS_PRECISION) -
            _collateralAccess;
    }

    /**
     * @notice Gracefully exercises an atlantic, sends collateral to integrated protocol,
     *         underlying to writer.
     *         to the option holder/protocol
     * @param  purchaseId   Options purchase id
     * @return unwindAmount Amount charged from caller (unwind amount + fees)
     */
    function unwind(
        uint256 purchaseId
    ) external returns (uint256 unwindAmount) {
        _whenNotPaused();
        _isEligibleSender();

        _validate(_isVaultReady(currentEpoch), 5);

        OptionsPurchase memory _userOptionsPurchase = userOptionsPurchases[
            purchaseId
        ];

        _validate(_userOptionsPurchase.user == msg.sender, 23);
        _validate(_userOptionsPurchase.unlock, 16);

        unwindAmount = getUnwindAmount(
            _userOptionsPurchase.optionsAmount,
            _userOptionsPurchase.optionStrike
        );

        for (uint256 i; i < _userOptionsPurchase.strikes.length; ) {
            // Unwind from maxStrike
            _unwind(
                _userOptionsPurchase.epoch,
                _userOptionsPurchase.strikes[i],
                ((unwindAmount) * _userOptionsPurchase.weights[i]) /
                    WEIGHTS_MUL_DIV,
                _userOptionsPurchase.checkpoints[i]
            );
            unchecked {
                ++i;
            }
        }
        _safeTransferFrom(
            addresses.baseToken,
            msg.sender,
            address(this),
            unwindAmount
        );
        delete userOptionsPurchases[purchaseId];
    }

    /// @dev Helper function to update states within max strikes
    function _unwind(
        uint256 _epoch,
        uint256 _maxStrike,
        uint256 _underlyingAmount,
        uint256 _checkpoint
    ) internal {
        unchecked {
            epochMaxStrikeCheckpoints[_epoch][_maxStrike][_checkpoint]
                .underlyingAccrued += _underlyingAmount;
        }
        emit Unwind(_epoch, _maxStrike, _underlyingAmount, msg.sender);
    }

    /**
     * @notice Withdraws balances for a strike from epoch deposted in to current epoch
     * @param depositId maxstrike to withdraw from
     */
    function withdraw(
        uint256 depositId
    )
        external
        nonReentrant
        returns (
            uint256 userWithdrawableAmount,
            uint256 premium,
            uint256 fundingFees,
            uint256 underlying
        )
    {
        _isEligibleSender();
        _whenNotPaused();

        (userWithdrawableAmount, premium, fundingFees, underlying) = _withdraw(
            depositId
        );

        _safeTransfer(
            addresses.quoteToken,
            msg.sender,
            premium + userWithdrawableAmount + fundingFees
        );
        _safeTransfer(addresses.baseToken, msg.sender, underlying);

        return (userWithdrawableAmount, premium, fundingFees, underlying);
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
    ) external nonReentrant onlyRole(MANAGER_ROLE) returns (bool) {
        uint256 nextEpoch = currentEpoch + 1;

        epochTickSize[nextEpoch] = tickSize;

        VaultState memory _vaultState = epochVaultStates[nextEpoch];

        _validate(expiry > block.timestamp, 19);

        if (currentEpoch > 0)
            _validate(epochVaultStates[nextEpoch - 1].isVaultExpired, 18);

        // Set the next epoch start time
        _vaultState.startTime = block.timestamp;

        _vaultState.expiryTime = expiry;

        _vaultState.isVaultReady = true;

        // Increase the current epoch
        currentEpoch = nextEpoch;

        epochVaultStates[nextEpoch] = _vaultState;

        emit Bootstrap(nextEpoch);

        return true;
    }

    /*==== VIEWS ====*/

    /// @notice Calculate Fees for settlement of options
    /// @param account Account to consider for fee discount.
    /// @param pnl     total pnl.
    /// @return fees
    function calculateSettlementFees(
        address account,
        uint256 pnl
    ) public view returns (uint256 fees) {
        fees = IDopexFeeStrategy(addresses.feeStrategy).getFeeBps(
            SETTLEMENT_FEES_KEY,
            account,
            useDiscountForFees
        );

        fees = ((pnl * (FEE_BPS_PRECISION + fees)) / FEE_BPS_PRECISION) - pnl;
    }

    /// @notice Calculate Fees for purchase
    /// @param strike strike price of the BaseToken option
    /// @param amount amount of options being bought
    /// @return finalFee purchase fee in QuoteToken
    function calculatePurchaseFees(
        address account,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256 finalFee) {
        uint256 feeBps = IDopexFeeStrategy(addresses.feeStrategy).getFeeBps(
            PURCHASE_FEES_KEY,
            account,
            useDiscountForFees
        );

        finalFee =
            (((amount * (FEE_BPS_PRECISION + feeBps)) / FEE_BPS_PRECISION) -
                amount) /
            10 ** (OPTION_TOKEN_DECIMALS - COLLATERAL_TOKEN_DECIMALS);

        if (getUsdPrice() < strike) {
            uint256 feeMultiplier = (((strike * 100) / (getUsdPrice())) - 100) +
                100;
            finalFee = (feeMultiplier * finalFee) / 100;
        }
    }

    /// @notice Calculate premium for an option
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options
    /// @return premium in QuoteToken
    function calculatePremium(
        uint256 _strike,
        uint256 _amount
    ) public view returns (uint256 premium) {
        uint256 currentPrice = getUsdPrice();
        premium = strikeMulAmount(
            IOptionPricing(addresses.optionPricing).getOptionPrice(
                true, // isPut
                epochVaultStates[currentEpoch].expiryTime,
                _strike,
                currentPrice,
                getVolatility(_strike)
            ),
            _amount
        );
    }

    /**
     * @notice Returns the price of the BaseToken in USD
     */
    function getUsdPrice() public view returns (uint256) {
        return
            IPriceOracle(addresses.priceOracle).getPrice(
                addresses.baseToken,
                false,
                false,
                false
            ) / 10 ** (30 - STRIKE_DECIMALS);
    }

    /// @notice Returns the volatility from the volatility oracle
    /// @param _strike Strike of the option
    function getVolatility(uint256 _strike) public view returns (uint256) {
        return
            IVolatilityOracle(addresses.volatilityOracle).getVolatility(
                _strike
            );
    }

    /**
     *   @notice Checks if caller is managed contract
     */
    function _isManagedContract() internal view {
        _validate(managedContracts[msg.sender], 20);
    }

    /**
     * @notice Revert-er function to revert with string error message
     * @param trueCondition Similar to require, a condition that has to be false
     *                      to revert
     * @param errorCode     Index in the errors[] that was set in error controller
     */
    function _validate(bool trueCondition, uint256 errorCode) internal pure {
        if (!trueCondition) {
            revert AtlanticPutsPoolError(errorCode);
        }
    }

    /**
     * @notice Checks if vault is not expired and bootstrapped
     * @param epoch Epoch of the pool
     */
    function _isVaultReady(uint256 epoch) internal view returns (bool) {
        return
            !epochVaultStates[epoch].isVaultExpired &&
            epochVaultStates[epoch].isVaultReady;
    }

    /**
     * @notice Check's if a maxstrike is valid by result of maxstrike % ticksize == 0
     * @param  maxStrike Max-strike amount
     * @param  epoch     Epoch of the pool
     * @return validity  if the max strike is valid
     */
    function _isValidMaxStrike(
        uint256 maxStrike,
        uint256 epoch
    ) private view returns (bool) {
        return maxStrike > 0 && maxStrike % epochTickSize[epoch] == 0;
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    /**
     * @notice Creates a new checkpoint or update existing one.
     *         current checkpoint
     * @param  epoch     Epoch of the pool
     * @param  maxStrike Max strike deposited into
     * @param  liquidity Amount of deposits / liquidity to add to totalLiquidity, totalLiquidityBalance
     * @return index     Returns the checkpoint number
     */
    function _updateCheckpoint(
        uint256 epoch,
        uint256 maxStrike,
        uint256 liquidity
    ) internal returns (uint256 index) {
        index = epochMaxStrikeCheckpointsLength[epoch][maxStrike];

        if (index == 0) {
            epochMaxStrikeCheckpoints[epoch][maxStrike][index] = (
                Checkpoint(block.timestamp, liquidity, liquidity, 0, 0, 0, 0, 0)
            );
            unchecked {
                ++epochMaxStrikeCheckpointsLength[epoch][maxStrike];
            }
        } else {
            Checkpoint memory currentCheckpoint = epochMaxStrikeCheckpoints[
                epoch
            ][maxStrike][index - 1];

            /**
      @dev Check if checkpoint interval was exceeded compared to previous checkpoint
           start time. if yes then create a new checkpoint or else accumulate to previous
           checkpoint
     */

            /** @dev If a checkpoints options have active collateral, add liquidity to next checkpoint
             */
            if (currentCheckpoint.activeCollateral > 0) {
                epochMaxStrikeCheckpoints[epoch][maxStrike][index]
                    .startTime = block.timestamp;
                epochMaxStrikeCheckpoints[epoch][maxStrike][index]
                    .totalLiquidity += liquidity;
                epochMaxStrikeCheckpoints[epoch][maxStrike][index]
                    .totalLiquidityBalance += liquidity;
                epochMaxStrikeCheckpointsLength[epoch][maxStrike]++;
            } else {
                unchecked {
                    --index;
                }

                currentCheckpoint.totalLiquidity += liquidity;
                currentCheckpoint.totalLiquidityBalance += liquidity;

                epochMaxStrikeCheckpoints[epoch][maxStrike][
                    index
                ] = currentCheckpoint;
            }
        }
    }

    /**
     * @param _depositId Epoch of atlantic pool to inquire
     * @return depositAmount Total deposits of user
     * @return premium       Total premiums earned
     * @return borrowFees    Total borrowFees fees earned
     * @return underlying    Total underlying earned on unwinds
     */
    function _withdraw(
        uint256 _depositId
    )
        private
        returns (
            uint256 depositAmount,
            uint256 premium,
            uint256 borrowFees,
            uint256 underlying
        )
    {
        DepositPosition memory _userDeposit = userDepositPositions[_depositId];

        _validate(_userDeposit.depositor == msg.sender, 23);
        _validate(epochVaultStates[_userDeposit.epoch].isVaultExpired, 1);

        Checkpoint memory _depositCheckpoint = epochMaxStrikeCheckpoints[
            _userDeposit.epoch
        ][_userDeposit.strike][_userDeposit.checkpoint];

        borrowFees +=
            (_userDeposit.liquidity * _depositCheckpoint.fundingFeesAccrued) /
            _depositCheckpoint.totalLiquidity;

        premium +=
            (_userDeposit.liquidity * _depositCheckpoint.premiumAccrued) /
            _depositCheckpoint.totalLiquidity;

        underlying +=
            (_userDeposit.liquidity * _depositCheckpoint.underlyingAccrued) /
            _depositCheckpoint.totalLiquidity;

        depositAmount +=
            (_userDeposit.liquidity *
                _depositCheckpoint.totalLiquidityBalance) /
            _depositCheckpoint.totalLiquidity;

        emit NewWithdraw(
            _userDeposit.epoch,
            _userDeposit.strike,
            _userDeposit.checkpoint,
            msg.sender,
            depositAmount,
            premium,
            borrowFees,
            underlying
        );

        delete userDepositPositions[_depositId];
    }

    /**
     * @notice Add max strike to strikesList (linked list)
     * @param _strike Strike to add to strikesList
     * @param _epoch  Epoch of the pool
     */
    function _addMaxStrike(uint256 _strike, uint256 _epoch) internal {
        uint256 highestMaxStrike = epochMaxStrikesRange[_epoch][0];
        uint256 lowestMaxStrike = epochMaxStrikesRange[_epoch][1];

        if (_strike > highestMaxStrike) {
            epochMaxStrikesRange[_epoch][0] = _strike;
        }
        if (_strike < lowestMaxStrike || lowestMaxStrike == 0) {
            epochMaxStrikesRange[_epoch][1] = _strike;
        }
        // Add new max strike after the next largest strike
        uint256 strikeToInsertAfter = _getSortedSpot(_strike, _epoch);

        if (strikeToInsertAfter == 0)
            epochStrikesList[_epoch].pushBack(_strike);
        else
            epochStrikesList[_epoch].insertBefore(strikeToInsertAfter, _strike);
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
            (next != 0) && ((_value < (isValidStrike[_epoch][next] ? next : 0)))
        ) {
            next = epochStrikesList[_epoch].list[next][true];
        }
        return next;
    }

    /**
     * @notice Multiply strike and amount depending on strike and options decimals
     * @param  _strike Option strike
     * @param  _amount Amount of options
     * @return result  Product of strike and amount in collateral/quote token decimals
     */
    function strikeMulAmount(
        uint256 _strike,
        uint256 _amount
    ) public view returns (uint256 result) {
        uint256 divisor = (STRIKE_DECIMALS + OPTION_TOKEN_DECIMALS) -
            COLLATERAL_TOKEN_DECIMALS;
        return ((_strike * _amount) / 10 ** divisor);
    }

    /**
     * @notice Get OptionsPurchase instance for a given tokenId
     * @param  _tokenId        ID of the options purchase
     * @return OptionsPurchase Options purchase data
     */
    function getOptionsPurchase(
        uint256 _tokenId
    ) external view returns (OptionsPurchase memory) {
        return userOptionsPurchases[_tokenId];
    }

    /**
     * @notice Get deposit position data for a given tokenId
     * @param  _tokenId        ID of the options purchase
     * @return DepositPosition Deposit position data
     */
    function getDepositPosition(
        uint256 _tokenId
    ) external view returns (DepositPosition memory) {
        return userDepositPositions[_tokenId];
    }

    /**
     * @notice Get checkpoints of a maxstrike in a epoch
     * @param  _epoch       Epoch of the pool
     * @param  _maxStrike   Max strike to query for
     * @return _checkpoints array of checkpoints of a max strike
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
            _checkpoints[i] = epochMaxStrikeCheckpoints[_epoch][_maxStrike][i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Fetches all max strikes written in a epoch
     * @param  epoch Epoch of the pool
     * @return maxStrikes
     */
    function getEpochStrikes(
        uint256 epoch
    ) external view returns (uint256[] memory maxStrikes) {
        maxStrikes = new uint256[](epochStrikesList[epoch].sizeOf());

        uint256 nextNode = epochMaxStrikesRange[epoch][0];
        uint256 iterator;
        while (nextNode != 0) {
            maxStrikes[iterator] = nextNode;
            iterator++;
            (, nextNode) = epochStrikesList[epoch].getNextNode(nextNode);
        }
    }

    function getCurrentEpochTickSize() external view returns (uint256) {
        return epochTickSize[currentEpoch];
    }

    function setUseDiscountForFees(
        bool _setAs
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        useDiscountForFees = _setAs;
        emit UseDiscountForFeesSet(_setAs);
        return true;
    }

    function whitelistUsers(
        address[] calldata _users,
        bool[] calldata _whitelist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < _users.length; ) {
            whitelistedUsers[_users[i]] = _whitelist[i];
            unchecked {
                ++i;
            }
        }
    }

    function setWhitelistUserMode(
        bool _mode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isWhitelistUserMode = _mode;
    }

    function isWithinExerciseWindow() public view returns (bool) {
        uint256 expiry = epochVaultStates[currentEpoch].expiryTime;
        return
            block.timestamp >= (expiry - expiryWindow) &&
            block.timestamp <= expiry;
    }

    modifier whitelistCheck() {
        if (isWhitelistUserMode) {
            _validate(whitelistedUsers[msg.sender], 403);
        }
        _;
    }
}

