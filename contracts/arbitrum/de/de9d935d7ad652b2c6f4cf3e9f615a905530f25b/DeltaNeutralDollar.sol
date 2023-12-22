/* solhint-disable no-inline-assembly */
pragma solidity ^0.8.19;

import { IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SignedMathUpgradeable } from "./SignedMathUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { SafeCastUpgradeable } from "./SafeCastUpgradeable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

import { IVault, IERC20 } from "./IVault.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";

import { IPool } from "./IPool.sol";
import { IAaveOracle } from "./IAaveOracle.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "./IPoolDataProvider.sol";
import { DataTypes } from "./DataTypes.sol";

import { IConnext } from "./IConnext.sol";

// we use solady for safe ERC20 functions because of dependency hell and casting requirement of SafeERC20 in OpenZeppelin; solady has zero deps.
import { SafeTransferLib } from "./SafeTransferLib.sol";

import { ISwapHelper } from "./ISwapHelper.sol";

uint256 constant AAVE_INTEREST_RATE_MODE_VARIABLE = 2;

uint8 constant FLASH_LOAN_MODE_CLOSE_POSITION = 3;
uint8 constant FLASH_LOAN_MODE_REBALANCE_SUPPLY_AND_BORROW = 4;
uint8 constant FLASH_LOAN_MODE_REBALANCE_REPAY_THEN_WITHDRAW = 5;

uint8 constant FLAGS_POSITION_CLOSED   = 1 << 0;
uint8 constant FLAGS_DEPOSIT_PAUSED    = 1 << 1;
uint8 constant FLAGS_WITHDRAW_PAUSED   = 1 << 2;
uint8 constant FLAGS_WITHDRAW_X_PAUSED = 1 << 3;

uint256 constant EXTRACT_LTV_FROM_POOL_CONFIGURATION_DATA_MASK = (1 << 16) - 1;

string constant ERROR_OPERATION_DISABLED_BY_FLAGS = "DND-01";
string constant ERROR_ONLY_FLASHLOAN_LENDER = "DND-02";
string constant ERROR_INCORRECT_FLASHLOAN_TOKEN_RECEIVED = "DND-03";
string constant ERROR_UNKNOWN_FLASHLOAN_MODE = "DND-04";
string constant ERROR_INCORRECT_DEPOSIT_OR_WITHDRAWAL_AMOUNT = "DND-05";
string constant ERROR_CONTRACT_NOT_READY_FOR_WITHDRAWAL = "DND-06";
string constant ERROR_POSITION_CLOSED = "DND-07";
string constant ERROR_POSITION_UNCHANGED = "DND-08";
string constant ERROR_IMPOSSIBLE_MODE = "DND-09";
string constant ERROR_ONLY_ALLOWED_TOKEN = "DND-10";
string constant ERROR_ONLY_ALLOWED_DESTINATION_DOMAIN = "DND-11";

/// @title Delta-neutral dollar vault

contract DeltaNeutralDollar is IFlashLoanRecipient, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @notice Settings are documented in the code
    struct Settings {
        /// @notice Address of the contract that implements asset swapping functionality.
        address swapHelper;

        /// @notice Address of the Connext bridge.
        address connext;

        /// @notice The minimum threshold of debt or collateral difference between the current position and the ideal calculated
        /// position that triggers an actual position change. Any changes below this threshold are disregarded.
        /// Note that this value is denominated in Aave's base currency.
        uint256 minAmountToChangePositionBase;

        /// @notice The minimum amount of Ethereum to deposit.
        uint256 minEthToDeposit;

        /// @notice The maximum amount of Ethereum to deposit.
        uint256 maxEthToDeposit;

        /// @notice The minimum amount of DND tokens to withdraw.
        uint256 minAmountToWithdraw;

        /// @notice The desirable distance to the LTV utilized when calculating position size.
        /// This is typically set to around 1%, i.e., if Aave's LTV is 80%, we aim to maintain our position at 79%.
        /// Note that this value needs to be multiplied by a factor of 100. For instance, "250" stands for 2.5%.
        uint8 additionalLtvDistancePercent;

        /// @notice The intended size of the position to maintain in Aave. It is usually set to 100.
        uint8 positionSizePercent;

        /// @notice Binary settings for the smart contract, as specified by the FLAGS_* constants.
        uint8 flags;

        /// @notice The minimum threshold of debt or collateral difference between the current position and the
        /// ideal calculated position that triggers an execution. Changes below this are disregarded.
        /// Note that this value is set as a percentage and needs to be multiplied by 10. Therefore, "10" equates to 1%.
        uint8 minRebalancePercent;
    }

    /// @notice Tokens allowed for deposit. Typically `ethToken` and WETH are set to true.
    mapping(address token => bool isAllowedToBeDeposited) public allowedDepositToken;

    /// @notice Tokens allowed for withdrawal. Typically `ethToken` and `stableToken` are set to true here.
    /// This mapping applies both to withdrawal on the same chain and crosschain.
    mapping(address token => bool isAllowedToBeWithdrawnIn) public allowedWithdrawToken;

    /// @notice Connext destination domains allowed for crosschain withdrawals.
    mapping(uint32 destinationDomain => bool isAllowedToBeWithdrawnTo) public allowedDestinationDomain;

    /// @notice actual contract settings
    Settings public settings;

    IPoolAddressesProvider private aaveAddressProvider;
    IVault private balancerVault;

    /// @notice Address of the stable token used as collateral in Aave by this contract.
    IERC20 public stableToken;

    /// @notice Address of the ETH ERC-20 token accepted by this contract. Usually it is a staked ETH.
    IERC20 public ethToken;

    uint8 private _decimals;

    uint8 private stableTokenDecimals;
    uint8 private ethTokenDecimals;
    // 8 bits left here

    /// @notice Event triggered post-execution of position change by deposit, withdrawal or direct execution of the `rebalance()` function.
    /// @param ethBalance Post-rebalance balance of `ethToken`
    /// @param totalCollateralBase Aggregate collateral in Aave's base currency
    /// @param totalDebtBase Aggregate debt in Aave's base currency
    /// @param collateralChangeBase Net collateral change post-rebalance.
    /// Negative value implies collateral withdrawal, positive value implies collateral deposit.
    /// @param debtChangeBase Net debt change post-rebalance.
    /// Negative value indicates debt repayment, positive value indicates additional borrowing.
    event PositionChange(uint256 ethBalance, uint256 totalCollateralBase, uint256 totalDebtBase, int256 collateralChangeBase, int256 debtChangeBase);

    /// @notice Emitted after a position has been closed
    /// @param finalEthBalance The final balance in `ethToken` after closing the position
    event PositionClose(uint256 finalEthBalance);

    /// @notice This event is emitted when a withdrawal takes place
    /// @param token The token in which the withdraw was executed
    /// @param amount The DND withdrawal amount requested by user
    /// @param amountBase The amount that has been withdrawn denoted in Aave's base currency. This is for reference only
    /// as no actual transfers of Aave base currency ever happens
    /// @param amountEth The actual amnount of `ethToken` that has been withdrawn from the position
    /// @param amountToken The quantity of `token` transferred to the user post the swap from `ethToken` to `token` in case they are not the same
    /// @param destinationDomain Connext destination domain. Set to '0' for same chain withdrawals
    event PositionWithdraw(address token, uint256 amount, uint256 amountBase, uint256 amountEth, uint256 amountToken, uint32 destinationDomain);

    /// @notice This event is emitted when a deposit takes place
    /// @param token The token which user deposited
    /// @param amount The amount of that token user deposited
    /// @param amountBase The amount that has been deposited denoted in Aave's base currency. This is for reference only
    /// as no actual transfers of Aave base currency ever happens
    /// @param amountEth The actual amnount of `ethToken` that has been deposited into the position
    event PositionDeposit(address token, uint256 amount, uint256 amountBase, uint256 amountEth);

    /// @notice Actual constructor of this upgradeable contract
    /// @param __decimals `decimals` for this contract's ERC20 properties. Should be equal to Aave base currency decimals, which is 8.
    /// @param symbol `symbol` for this contract's ERC20 properties. Typically it's DND.
    /// @param name `name` for this contract's ERC20 properties.
    /// @param _stableToken Address of the stable token used as collateral in Aave by this contract.
    /// @param _ethToken Address of the ETH ERC-20 token accepted by this contract. Usually it is a staked ETH.
    /// @param _balancerVault The contract address of the Balancer's Vault, necessary for executing flash loans.
    /// @param _aaveAddressProvider The address of the Aave's ADDRESS_PROVIDER.
    /// @param _settings Actual settings. See `Settings` structure in code.
    function initialize(
        uint8 __decimals,
        string memory symbol,
        string memory name,
        address _stableToken,
        address _ethToken,
        address _balancerVault,
        address _aaveAddressProvider,
        Settings calldata _settings
    )
        public
        initializer
    {
        __ERC20_init(name, symbol);
        __Ownable_init();

        _decimals = __decimals;

        aaveAddressProvider = IPoolAddressesProvider(_aaveAddressProvider);

        settings = _settings;

        balancerVault = IVault(_balancerVault);

        ethToken = IERC20(_ethToken);
        stableToken = IERC20(_stableToken);

        ethTokenDecimals = IERC20MetadataUpgradeable(_ethToken).decimals();
        stableTokenDecimals = IERC20MetadataUpgradeable(_stableToken).decimals();

        allowedDepositToken[_ethToken] = true;

        allowedWithdrawToken[_ethToken] = true;
        allowedWithdrawToken[_stableToken] = true;

        _transferOwnership(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Retrieves the contract's current implementation address
    /// @return The address of the active contract implementation
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    modifier whenFlagNotSet(uint8 whatExactly) {
        require((settings.flags & whatExactly) != whatExactly, ERROR_OPERATION_DISABLED_BY_FLAGS);
        _;
    }

    modifier onlyBalancerVault() {
        require(msg.sender == address(balancerVault), ERROR_ONLY_FLASHLOAN_LENDER);
        _;
    }

    modifier onlyAllowedDepositToken(address token) {
        require(allowedDepositToken[token] == true, ERROR_ONLY_ALLOWED_TOKEN);
        _;
    }

    modifier onlyAllowedWithdrawToken(address token) {
        require(allowedWithdrawToken[token] == true, ERROR_ONLY_ALLOWED_TOKEN);
        _;
    }

    modifier onlyAllowedDestinationDomain(uint32 destinationDomain) {
        require(allowedDestinationDomain[destinationDomain] == true, ERROR_ONLY_ALLOWED_DESTINATION_DOMAIN);
        _;
    }

    /// @notice Closes the entire position, repaying all debt, withdrawing all collateral from Aave and deactivating the contract.
    /// Only accessible by the contract owner when the position hasn't been already closed.
    function closePosition() public whenFlagNotSet(FLAGS_POSITION_CLOSED) onlyOwner {
        settings.flags = settings.flags | FLAGS_POSITION_CLOSED;

        (, , address variableDebtTokenAddress) = poolDataProvider().getReserveTokensAddresses(address(ethToken));

        uint256 debtEth = SafeTransferLib.balanceOf(variableDebtTokenAddress, address(this));
        uint256 balanceEth = SafeTransferLib.balanceOf(address(ethToken), address(this));

        if (balanceEth >= debtEth) { // even if debtEth and/or balanceEth == 0
            if (debtEth > 0) {
                debtRepay(type(uint256).max);
            }

            collateralWithdraw(type(uint).max);
            approveAndSwap(stableToken, ethToken, SafeTransferLib.balanceOf(address(stableToken), address(this)));

        } else {
            uint256 flashLoanEth = debtEth - balanceEth; // there is no underflow risk as it has been checked in the "if" above

            IERC20[] memory tokens = new IERC20[](1);
            tokens[0] = ethToken;

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = flashLoanEth;

            bytes memory userData = abi.encode(FLASH_LOAN_MODE_CLOSE_POSITION);
            balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
        }

        uint256 balanceAfter = SafeTransferLib.balanceOf(address(ethToken), address(this));

        // this weird trick is required to work around hardhat(?) bug emiting 0 in this event
        balanceAfter = balanceAfter + 1;

        emit PositionClose(balanceAfter - 1);
    }

    /// @notice Calculates the required changes in collateral and debt in Aave, given the current prices of `stableToken` and `ethToken`,
    /// total debt and collateral, and the amount of `ethToken` on balance.
    /// @return collateralChangeBase The amount by which the collateral should adjust.
    /// A negative value implies that collateral should be withdrawn; positive value indicates that more collateral is to be supplied.
    /// Note: amount is denoted in Aave base currency.
    /// @return debtChangeBase The amount by which the debt should adjust.
    /// A negative value indicates debt repayment should occur; positive value indicates that more debt should be borrowed.
    /// Note: amount is denoted in Aave base currency.
    /// @dev This is a public facing implementation, a read-only method to see if there's any change pending.
    function calculateRequiredPositionChange() public view returns (int256 collateralChangeBase, int256 debtChangeBase) {
        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool().getUserAccountData(address(this));
        return _calculateRequiredPositionChange(totalCollateralBase, totalDebtBase, ethPrice);
    }

    function _calculateRequiredPositionChange(uint256 totalCollateralBase, uint256 totalDebtBase, uint256 ethPrice)
        internal
        view
        returns (
            int256 collateralChangeBase,
            int256 debtChangeBase
        )
    {
        uint256 balanceBase = convertEthToBase(SafeTransferLib.balanceOf(address(ethToken), address(this)), ethPrice);
        uint256 totalAssetsBase = totalCollateralBase - totalDebtBase + balanceBase;

        uint256 idealTotalCollateralBase = MathUpgradeable.mulDiv(totalAssetsBase, settings.positionSizePercent, 100);
        idealTotalCollateralBase = MathUpgradeable.mulDiv(idealTotalCollateralBase, 999, 1000); // shave 0.1% to give room

        // positive means supply; negative: withdraw
        collateralChangeBase = diffBaseAtLeastMinAmountToChangePosition(idealTotalCollateralBase, totalCollateralBase);

        uint256 collateralChangePercent = MathUpgradeable.mulDiv(SignedMathUpgradeable.abs(collateralChangeBase), 1000, idealTotalCollateralBase);
        if (collateralChangePercent < settings.minRebalancePercent) {
            collateralChangeBase = 0;
        }

        uint256 idealLtv = ltv() - (settings.additionalLtvDistancePercent * 10);
        uint256 idealTotalDebtBase = MathUpgradeable.mulDiv(idealTotalCollateralBase, idealLtv, 10000);

        // positive means borrow; negative: repay
        debtChangeBase = diffBaseAtLeastMinAmountToChangePosition(idealTotalDebtBase, totalDebtBase);

        uint256 debtChangePercent = MathUpgradeable.mulDiv(SignedMathUpgradeable.abs(debtChangeBase), 1000, idealTotalDebtBase);
        if (debtChangePercent < settings.minRebalancePercent) {
            debtChangeBase = 0;
        }
    }

    /// @notice Do `calculateRequiredPositionChange()` and actually rebalance the position if changes are pending.
    /// This method reverts with `ERROR_POSITION_UNCHANGED` if the position stays the same or if the changes are too small
    /// and not worth executing.
    function rebalance() public {
        _rebalance(true);
    }

    function _rebalance(bool shouldRevert) internal {
        if (settings.flags & FLAGS_POSITION_CLOSED == FLAGS_POSITION_CLOSED) {
            if (shouldRevert) {
                revert(ERROR_POSITION_CLOSED);
            }

            return;
        }

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));

        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool().getUserAccountData(address(this));
        (int256 collateralChangeBase, int256 debtChangeBase) = _calculateRequiredPositionChange(totalCollateralBase, totalDebtBase, ethPrice);

        if (collateralChangeBase == 0 && debtChangeBase == 0) {
            if (shouldRevert) {
                revert(ERROR_POSITION_UNCHANGED);
            }

            return;
        }

        if (collateralChangeBase > 0 && debtChangeBase > 0) {
            // console.log("C00 ==> Supply collateral then borrow debt");
            implementSupplyThenBorrow(SignedMathUpgradeable.abs(collateralChangeBase), SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase < 0) {
            // console.log("C00 ==> Repay debt then withdraw collateral");
            implementRepayThenWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase > 0 && debtChangeBase < 0) {
            // console.log("C00 ==> Repay debt then supply collateral"); // not found yet
            implementRepay(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);
            implementSupply(SignedMathUpgradeable.abs(collateralChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase > 0) {
            // console.log("C00 ==> Borrow debt and withdraw collateral"); // not found yet
            implementWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), oracle().getAssetPrice(address(stableToken)));
            implementBorrow(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);


        // the below happens when minAmountToChangePositionBase has been triggered only on either debt or collateral

        } else if (collateralChangeBase == 0 && debtChangeBase > 0) {
            // console.log("C00 ==> Just borrow debt");
            implementBorrow(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase == 0 && debtChangeBase < 0) {
            // console.log("C00 ==> Just repay debt");
            implementRepay(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase == 0) {
            // console.log("C00 ==> Just withdraw collateral"); // not found yet
            implementWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), oracle().getAssetPrice(address(stableToken)));

        } else if (collateralChangeBase > 0 && debtChangeBase == 0) {
            // console.log("C00 ==> Just supply collateral"); // not found yet
            implementSupply(SignedMathUpgradeable.abs(collateralChangeBase), ethPrice);

        } else {
            revert(ERROR_IMPOSSIBLE_MODE);
        }

        (totalCollateralBase, totalDebtBase, , , , ) = pool().getUserAccountData(address(this));

        emit PositionChange(
            SafeTransferLib.balanceOf(address(ethToken), address(this)),
            totalCollateralBase,
            totalDebtBase,
            collateralChangeBase,
            debtChangeBase
        );
    }

    function implementSupply(uint256 supplyCollateralBase, uint256 ethPrice) internal {
        uint256 collateralEth = convertBaseToEth(supplyCollateralBase, ethPrice);
        uint256 collateralStable = approveAndSwap(ethToken, stableToken, collateralEth);
        collateralSupply(collateralStable);
    }

    function implementBorrow(uint256 borrowDebtBase, uint256 ethPrice) internal {
        uint256 borrowEth = convertBaseToEth(borrowDebtBase, ethPrice);
        debtBorrow(borrowEth);
    }

    function implementRepayThenWithdraw(uint256 withdrawCollateralBase, uint256 repayDebtBase, uint256 ethPrice) internal {
        uint256 repayDebtEth = convertBaseToEth(repayDebtBase, ethPrice);

        uint256 myBalanceEth = SafeTransferLib.balanceOf(address(ethToken), address(this));

        if (repayDebtEth <= myBalanceEth) {
            implementRepay(repayDebtBase, ethPrice);
            implementWithdraw(withdrawCollateralBase, oracle().getAssetPrice(address(stableToken)));
            return;
        }

        uint256 flashLoanEth = repayDebtEth - myBalanceEth;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = ethToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanEth;

        bytes memory userData = abi.encode(FLASH_LOAN_MODE_REBALANCE_REPAY_THEN_WITHDRAW, repayDebtEth, withdrawCollateralBase);
        balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
    }

    function implementSupplyThenBorrow(uint256 supplyCollateralBase, uint256 borrowDebtBase, uint256 ethPrice) internal {
        uint256 supplyCollateralEth = convertBaseToEth(supplyCollateralBase, ethPrice);

        uint256 collateralEth = supplyCollateralEth / 5;

        // this actually cannot happen, because base currency in aave is 8 decimals and ether is 18, so smallest
        // aave amount is divisable by 5. But we keep this sanity check anyway.
        assert(collateralEth > 0);

        uint256 collateralStable = approveAndSwap(ethToken, stableToken, collateralEth);
        assert(collateralStable > 0);

        uint256 flashLoanStable = collateralStable * 4;

        uint256 positionStable = collateralStable * 5;

        uint256 borrowDebtEth = convertBaseToEth(borrowDebtBase, ethPrice);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = stableToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanStable;

        bytes memory userData = abi.encode(FLASH_LOAN_MODE_REBALANCE_SUPPLY_AND_BORROW, borrowDebtEth, positionStable);
        balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
    }

    function implementRepay(uint256 repayDebtBase, uint256 ethPrice) internal {
        uint256 repayDebtEth = convertBaseToEth(repayDebtBase, ethPrice);
        debtRepay(repayDebtEth);
    }

    function implementWithdraw(uint256 withdrawCollateralBase, uint256 stablePrice) internal {
        uint256 withdrawCollateralStable = convertBaseToStable(withdrawCollateralBase, stablePrice);
        assert(withdrawCollateralStable > 0);
        collateralWithdraw(withdrawCollateralStable);
        approveAndSwap(stableToken, ethToken, withdrawCollateralStable);
    }

    function receiveFlashLoanRebalanceSupplyAndBorrow(uint256 flashLoanStable, uint256 positionStable, uint256 borrowDebtEth) internal {
        collateralSupply(positionStable);
        debtBorrow(borrowDebtEth);

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 stablePrice = oracle().getAssetPrice(address(stableToken));

        uint256 ethToSwap = convertBaseToEth(convertStableToBase(flashLoanStable, stablePrice), ethPrice);

        uint256 feeEth = ISwapHelper(settings.swapHelper).calcSwapFee(address(ethToken), address(stableToken), ethToSwap);
        ethToSwap = ethToSwap + feeEth;

        // at this point we assume we always have enough eth to cover swap fees
        approveAndSwap(ethToken, stableToken, ethToSwap);

        assert(SafeTransferLib.balanceOf(address(stableToken), address(this)) >= flashLoanStable);

        SafeTransferLib.safeTransfer(address(stableToken), address(balancerVault), flashLoanStable);

        uint256 dustStable = SafeTransferLib.balanceOf(address(stableToken), address(this));
        if (dustStable > 0) {
            approveAndSwap(stableToken, ethToken, dustStable);
        }
    }

    function receiveFlashLoanClosePosition(uint256 flashLoanEth) internal {
        // prior to that in closePosition() we have calculated that debt actually exists,
        // so it should NOT revert here with NO_DEBT_OF_SELECTED_TYPE
        debtRepay(type(uint256).max);

        collateralWithdraw(type(uint).max);

        approveAndSwap(stableToken, ethToken, SafeTransferLib.balanceOf(address(stableToken), address(this)));

        SafeTransferLib.safeTransfer(address(ethToken), address(balancerVault), flashLoanEth);
    }

    function receiveFlashLoanRepayThenWithdraw(uint256 flashLoanEth, uint256 repayDebtEth, uint256 withdrawCollateralBase) internal {
        debtRepay(repayDebtEth);

        uint256 withdrawCollateralStable = convertBaseToStable(withdrawCollateralBase, oracle().getAssetPrice(address(stableToken)));
        assert(withdrawCollateralStable > 0);

        collateralWithdraw(withdrawCollateralStable);

        approveAndSwap(stableToken, ethToken, withdrawCollateralStable);

        SafeTransferLib.safeTransfer(address(ethToken), address(balancerVault), flashLoanEth);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts, // solhint-disable-line no-unused-vars
        bytes memory userData
    )
        external
        onlyBalancerVault
    {
        (uint8 mode) = abi.decode(userData, (uint8));

        if (mode == FLASH_LOAN_MODE_REBALANCE_SUPPLY_AND_BORROW) {
            require(tokens.length == 1 && tokens[0] == stableToken, ERROR_INCORRECT_FLASHLOAN_TOKEN_RECEIVED);
            (, uint256 borrowDebtEth, uint256 positionStable) = abi.decode(userData, (uint8, uint256, uint256));
            receiveFlashLoanRebalanceSupplyAndBorrow(amounts[0], positionStable, borrowDebtEth);
            return;
        }

        if (mode == FLASH_LOAN_MODE_CLOSE_POSITION) {
            require(tokens.length == 1 && tokens[0] == ethToken, ERROR_INCORRECT_FLASHLOAN_TOKEN_RECEIVED);
            receiveFlashLoanClosePosition(amounts[0]);
            return;
        }

        if (mode == FLASH_LOAN_MODE_REBALANCE_REPAY_THEN_WITHDRAW) {
            require(tokens.length == 1 && tokens[0] == ethToken, ERROR_INCORRECT_FLASHLOAN_TOKEN_RECEIVED);
            (, uint256 repayDebtEth, uint256 withdrawCollateralBase) = abi.decode(userData, (uint8, uint256, uint256));
            receiveFlashLoanRepayThenWithdraw(amounts[0], repayDebtEth, withdrawCollateralBase);
            return;
        }

        require(false, ERROR_UNKNOWN_FLASHLOAN_MODE);
    }

    function _collect(address tokenAddress, address to) internal {
        if (tokenAddress == address(0)) {
            if (address(this).balance == 0) {
                return;
            }

            payable(to).transfer(address(this).balance);

            return;
        }

        SafeTransferLib.safeTransferAll(tokenAddress, to);
    }

    /// @notice Allows the contract owner to recover misplaced tokens.
    /// The function can only be invoked by the contract owner.
    /// @param tokens An array of token contract addresses from which tokens will be collected.
    /// @param to The recipient address where all retrieved tokens will be transferred.
    function collectTokens(address[] memory tokens, address to) public onlyOwner {
        for (uint256 i=0; i<tokens.length; i++) {
            _collect(tokens[i], to);
        }
    }

    /// @notice Deposit funds into vault
    /// @param token `token` to deposit. Must be one of the allowed ones or zero for native ETH deposits.
    /// @param amount amount of `token` to deposit
    function deposit(address token, uint256 amount)
        public
        whenFlagNotSet(FLAGS_DEPOSIT_PAUSED)
        whenFlagNotSet(FLAGS_POSITION_CLOSED)
        onlyAllowedDepositToken(token)
    {
        require(amount > 0, ERROR_INCORRECT_DEPOSIT_OR_WITHDRAWAL_AMOUNT);

        uint256 totalBalanceBaseBefore = totalBalanceBase();

        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        uint256 amountEth = amount;
        if (token != address(ethToken)) {
            amountEth = approveAndSwap(IERC20(token), ethToken, amount);
        }

        require(
            amountEth >= settings.minEthToDeposit && amountEth <= settings.maxEthToDeposit,
            ERROR_INCORRECT_DEPOSIT_OR_WITHDRAWAL_AMOUNT
        );

        _rebalance(false);

        uint256 totalBalanceBaseAfter = totalBalanceBase();

        if (totalSupply() == 0) {
            _mint(msg.sender, totalBalanceBaseAfter);
            emit PositionDeposit(token, amount, totalBalanceBaseAfter, amountEth);
            return;
        }

        uint256 totalBalanceAddedPercent = MathUpgradeable.mulDiv(totalBalanceBaseAfter, 10e18, totalBalanceBaseBefore) - 10e18;

        uint256 minted = MathUpgradeable.mulDiv(totalSupply(), totalBalanceAddedPercent, 10e18);
        assert(minted > 0);

        _mint(msg.sender, minted);

        emit PositionDeposit(token, amount, totalBalanceBaseAfter - totalBalanceBaseBefore, amountEth);
    }

    function _calculateEthWithdrawAmount(uint256 amount) internal view returns (uint256 amountEth, uint256 amountBase) {
        require(amount > 0 && amount >= settings.minAmountToWithdraw, ERROR_INCORRECT_DEPOSIT_OR_WITHDRAWAL_AMOUNT);
        require(amount <= balanceOf(msg.sender), ERROR_INCORRECT_DEPOSIT_OR_WITHDRAWAL_AMOUNT);

        uint256 percent = MathUpgradeable.mulDiv(amount, 10e18, totalSupply());
        assert(percent > 0);

        amountBase = MathUpgradeable.mulDiv(totalBalanceBase(), percent, 10e18);
        assert(amountBase > 0);

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        amountEth = convertBaseToEth(amountBase, ethPrice);
        assert(amountEth > 0);

        require(amountEth <= SafeTransferLib.balanceOf(address(ethToken), address(this)), ERROR_CONTRACT_NOT_READY_FOR_WITHDRAWAL);
    }

    /// @notice Withdraw from vault in `token`
    /// @param token The token address to withdraw in. Typically this should be `ethToken` or `stableToken`
    /// @param amount The amount of DND to withdraw
    function withdraw(address token, uint256 amount)
        public
        whenFlagNotSet(FLAGS_WITHDRAW_PAUSED)
        onlyAllowedWithdrawToken(token)
    {
        (uint256 amountEth, uint256 amountBase) = _calculateEthWithdrawAmount(amount);
        _burn(msg.sender, amount);

        uint256 amountToken;

        if (token == address(ethToken)) {
            SafeTransferLib.safeTransfer(address(ethToken), msg.sender, amountEth);

        } else {
            amountToken = approveAndSwap(ethToken, IERC20(token), amountEth);
            SafeTransferLib.safeTransfer(token, msg.sender, amountToken);
        }

        _rebalance(false);

        emit PositionWithdraw(token, amount, amountBase, amountEth, amountToken, 0);
    }

    /// @notice Withdraw from vault in `token` then bridge to another network via Connext
    /// @param token The token address to withdraw in. Typically this should be `stableToken`
    /// @param amount The amount of DND to withdraw
    /// @param destinationDomain Connext destination domain
    /// @param slippage Connext slippage allowed
    /// @param relayerFee Connext relayer fee
    function withdrawX(address token, uint256 amount, uint32 destinationDomain, uint256 slippage, uint256 relayerFee)
        public
        payable
        whenFlagNotSet(FLAGS_WITHDRAW_PAUSED)
        whenFlagNotSet(FLAGS_WITHDRAW_X_PAUSED)
        onlyAllowedDestinationDomain(destinationDomain)
        onlyAllowedWithdrawToken(token)
    {
        (uint256 amountEth, uint256 amountBase) = _calculateEthWithdrawAmount(amount);

        _burn(msg.sender, amount);

        uint256 amountToken = approveAndSwap(ethToken, IERC20(token), amountEth);

        _bridge(token, amountToken, destinationDomain, slippage, relayerFee);

        _rebalance(false);

        emit PositionWithdraw(token, amount, amountBase, amountEth, amountToken, destinationDomain);
    }

    function _bridge(address token, uint256 amount, uint32 destinationDomain, uint256 slippage, uint256 relayerFee) internal {
        possiblyApprove(IERC20(token), settings.connext, amount);

        bytes memory callData;
        IConnext(settings.connext).xcall{value: relayerFee}(
            destinationDomain,    // _destination: Domain ID of the destination chain
            msg.sender,           // _to: address of the target contract
            token,                // _asset: address of the token contract
            owner(),              // _delegate: address that can revert or forceLocal on destination
            amount,               // _amount: amount of tokens to transfer
            slippage,             // _slippage: max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData              // _callData: the encoded calldata to send
        );

        SafeTransferLib.safeApprove(token, settings.connext, 0);
    }

    /// @notice Returns the Total Value Locked (TVL) in the Vault
    /// @return The TVL represented in Aave's base currency
    function totalBalanceBase() public view returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , ,) = pool().getUserAccountData(address(this));
        uint256 netBase = totalCollateralBase - totalDebtBase;

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 ethBalanceBase = MathUpgradeable.mulDiv(SafeTransferLib.balanceOf(address(ethToken), address(this)), ethPrice, 10 ** ethTokenDecimals);

        return ethBalanceBase + netBase;
    }

    function debtBorrow(uint256 amount) internal {
        pool().borrow(address(ethToken), amount, AAVE_INTEREST_RATE_MODE_VARIABLE, 0, address(this));
    }

    function debtRepay(uint256 amount) internal {
        possiblyApprove(ethToken, address(pool()), amount);

        pool().repay(address(ethToken), amount, AAVE_INTEREST_RATE_MODE_VARIABLE, address(this));

        SafeTransferLib.safeApprove(address(ethToken), address(pool()), 0);
    }

    function collateralSupply(uint256 amount) internal {
        possiblyApprove(stableToken, address(pool()), amount);

        pool().supply(address(stableToken), amount, address(this), 0);
        pool().setUserUseReserveAsCollateral(address(stableToken), true);

        SafeTransferLib.safeApprove(address(stableToken), address(pool()), 0);
    }

    function collateralWithdraw(uint256 amount) internal {
        pool().withdraw(address(stableToken), amount, address(this));
    }

    function approveAndSwap(IERC20 from, IERC20 to, uint256 amount) internal returns (uint256 swappedAmount) {
        if (amount == 0) {
            return 0;
        }

        possiblyApprove(from, settings.swapHelper, amount);

        swappedAmount = ISwapHelper(settings.swapHelper).swap(address(from), address(to), amount, address(this));

        SafeTransferLib.safeApprove(address(from), settings.swapHelper, 0);
    }

    function possiblyApprove(IERC20 token, address spender, uint256 amount) internal {
        uint256 allowance = token.allowance(address(this), spender);

        if (allowance > 0) {
            SafeTransferLib.safeApprove(address(token), spender, 0);
        }

        if (amount == 0) {
            return;
        }

        SafeTransferLib.safeApprove(address(token), spender, amount);
    }

    function diffBaseAtLeastMinAmountToChangePosition(uint256 amountA, uint256 amountB) internal view returns (int256) {
        int256 amountBaseDiff = SafeCastUpgradeable.toInt256(amountA) - SafeCastUpgradeable.toInt256(amountB);
        return (SignedMathUpgradeable.abs(amountBaseDiff) >= settings.minAmountToChangePositionBase) ? amountBaseDiff : int256(0);
    }

    function convertBaseToStable(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, 10 ** stableTokenDecimals, stablePrice);
    }

    function convertStableToBase(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, stablePrice, 10 ** stableTokenDecimals);
    }

    function convertBaseToEth(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, 10 ** ethTokenDecimals, ethPrice);
    }

    function convertEthToBase(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, ethPrice, 10 ** ethTokenDecimals);
    }

    /*
    // those are not actually used, but kept in code for posterity

    function ethToStable(uint256 amount, uint256 ethPrice, uint256 stablePrice) internal view returns (uint256) {
        return amount * ethPrice / 10 ** (ethTokenDecimals - stableTokenDecimals) / stablePrice;
    }

    function stableToEth(uint256 amount, uint256 stablePrice, uint256 ethPrice) internal view returns (uint256) {
        return amount * stablePrice * 10 ** (ethTokenDecimals - stableTokenDecimals) / ethPrice;
    }
    */

    /// @notice Update contract's `settings`. Method is only available to owner.
    function setSettings(Settings calldata _settings)
        public
        onlyOwner
    {
        settings = _settings;
    }

    function setAllowedDepositToken(address token, bool isAllowed)
        public
        onlyOwner
    {
        if (isAllowed) {
            allowedDepositToken[token] = true;
            return;
        }

        delete allowedDepositToken[token];
    }

    function setAllowedWithdrawToken(address token, bool isAllowed)
        public
        onlyOwner
    {
        if (isAllowed) {
            allowedWithdrawToken[token] = true;
            return;
        }

        delete allowedWithdrawToken[token];
    }

    function setAllowedDestinationDomain(uint32 destinationDomain, bool isAllowed)
        public
        onlyOwner
    {
        if (isAllowed) {
            allowedDestinationDomain[destinationDomain] = true;
            return;
        }

        delete allowedDestinationDomain[destinationDomain];
    }

    function ltv() internal view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory poolConfiguration = pool().getConfiguration(address(stableToken));
        return poolConfiguration.data & EXTRACT_LTV_FROM_POOL_CONFIGURATION_DATA_MASK;
    }

    function pool() internal view returns (IPool) {
        return IPool(aaveAddressProvider.getPool());
    }

    function poolDataProvider() internal view returns (IPoolDataProvider) {
        return IPoolDataProvider(aaveAddressProvider.getPoolDataProvider());
    }

    function oracle() internal view returns (IAaveOracle) {
        return IAaveOracle(aaveAddressProvider.getPriceOracle());
    }

    /// @notice ERC20 method
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

