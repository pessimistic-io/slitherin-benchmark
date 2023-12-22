/* solhint-disable no-inline-assembly, no-console */
pragma solidity ^0.8.19;

import { IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SignedMathUpgradeable } from "./SignedMathUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { SafeCastUpgradeable } from "./SafeCastUpgradeable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { Initializable } from "./Initializable.sol";

import { IVault, IERC20 } from "./IVault.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";

import { IPool } from "./IPool.sol";
import { IAaveOracle } from "./IAaveOracle.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "./IPoolDataProvider.sol";
import { DataTypes } from "./DataTypes.sol";

import { ISwapHelper2 } from "./ISwapHelper2.sol";

// import "hardhat/console.sol";

uint256 constant INTEREST_RATE_MODE_VARIABLE = 2;

uint8 constant FLASH_LOAN_CLOSE_POSITION = 3;
uint8 constant FLASH_LOAN_PERFECT_SUPPLY_AND_BORROW = 4;
uint8 constant FLASH_LOAN_PERFECT_REPAY_THEN_WITHDRAW = 5;

uint8 constant FLAGS_POSITION_CLOSED = 1 << 0;
uint8 constant FLAGS_DEPOSIT_PAUSED  = 1 << 1;
uint8 constant FLAGS_WITHDRAW_PAUSED = 1 << 2;

contract DeltaNeutralDollar is IFlashLoanRecipient, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    struct Settings {
        address swapHelper;

        uint256 minAmountToChangePositionBase;

        uint256 minEthToDeposit;
        uint256 minAmountToWithdraw;

        uint8 additionalLtvDistancePercent; // in tens, so "10" == 1%
        uint8 positionSizePercent;
        uint8 flags;
        uint8 minRebalancePercent; // in tens, so "10" == 1%
    }

    Settings public settings;

    IPoolAddressesProvider private aaveAddressProvider;
    IVault private balancerVault;

    IERC20 public stableToken;
    IERC20 public ethToken;

    uint8 private _decimals;

    uint8 private stableTokenDecimals;
    uint8 private ethTokenDecimals;
    // 8 bits here

    event PositionChange(uint256 ethBalance, uint256 totalCollateralBase, uint256 totalDebtBase, int256 collateralChangeBase, int256 debtChangeBase);

    event Withdraw(uint256 amountBase, uint256 amountEth, uint256 amountStable);
    event Deposit(uint256 amountBase, uint256 amountEth);

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

        ethToken.approve(settings.swapHelper, type(uint256).max);
        stableToken.approve(settings.swapHelper, type(uint256).max);

        ethTokenDecimals = IERC20MetadataUpgradeable(address(ethToken)).decimals();
        stableTokenDecimals = IERC20MetadataUpgradeable(address(stableToken)).decimals();

        ethToken.approve(address(pool()), type(uint256).max);
        stableToken.approve(address(pool()), type(uint256).max);

        _transferOwnership(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function implementation() public view returns (address) {
        return _getImplementation();
    }

    modifier whenNotPaused(uint8 whatExactly) {
        require((settings.flags & whatExactly) != whatExactly, "FLAGS");
        _;
    }

    function closePosition() public whenNotPaused(FLAGS_POSITION_CLOSED) onlyOwner {
        settings.flags = settings.flags | FLAGS_POSITION_CLOSED;

        (, , address variableDebtTokenAddress) = poolDataProvider().getReserveTokensAddresses(address(ethToken));

        uint256 debtEth = IERC20(variableDebtTokenAddress).balanceOf(address(this));

        uint256 balanceEth = ethToken.balanceOf(address(this));

        if (balanceEth > debtEth) {
            // FIXME what if 0?
            debtRepay(type(uint256).max);

            // FIXME what if 0?
            collateralWithdraw(type(uint).max);
            ISwapHelper2(settings.swapHelper).swap(address(stableToken), address(ethToken), stableToken.balanceOf(address(this)), address(this));

        } else {
            uint256 flashLoanEth = debtEth - balanceEth;

            IERC20[] memory tokens = new IERC20[](1);
            tokens[0] = ethToken;

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = flashLoanEth;

            bytes memory userData = abi.encode(FLASH_LOAN_CLOSE_POSITION);
            balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
        }
    }

    function diff() public view returns (int256 collateralChangeBase, int256 debtChangeBase) {
        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool().getUserAccountData(address(this));
        return _diff(totalCollateralBase, totalDebtBase, ethPrice);
    }

    function _diff(uint256 totalCollateralBase, uint256 totalDebtBase, uint256 ethPrice) internal view returns (int256 collateralChangeBase, int256 debtChangeBase) {
        uint256 balanceBase = ethToBase(ethToken.balanceOf(address(this)), ethPrice);
        uint256 totalAssetsBase = totalCollateralBase - totalDebtBase + balanceBase;

        uint256 idealTotalCollateralBase = MathUpgradeable.mulDiv(totalAssetsBase, settings.positionSizePercent, 100);
        idealTotalCollateralBase = MathUpgradeable.mulDiv(idealTotalCollateralBase, 999, 1000);

        uint256 idealTotalDebtBase = MathUpgradeable.mulDiv(idealTotalCollateralBase, _ltv() - (settings.additionalLtvDistancePercent * 10), 10000);

        // positive means supply; negative: withdraw
        collateralChangeBase = diffBaseClamped(idealTotalCollateralBase, totalCollateralBase);

        if (
            collateralChangeBase != 0 &&
            idealTotalCollateralBase != 0 &&
            MathUpgradeable.mulDiv(SignedMathUpgradeable.abs(collateralChangeBase), 1000, idealTotalCollateralBase) < settings.minRebalancePercent
        ) {
            collateralChangeBase = 0;
        }

        // positive means borrow; negative: repay
        debtChangeBase = diffBaseClamped(idealTotalDebtBase, totalDebtBase);

        if (
            debtChangeBase != 0 &&
            idealTotalDebtBase != 0 &&
            MathUpgradeable.mulDiv(SignedMathUpgradeable.abs(debtChangeBase), 1000, idealTotalDebtBase) < settings.minRebalancePercent
        ) {
            debtChangeBase = 0;
        }
    }

    function perfect() public {
        _perfect(true);
    }

    function _perfect(bool shouldRevert) internal {
        if (settings.flags & FLAGS_POSITION_CLOSED == FLAGS_POSITION_CLOSED) {
            if (shouldRevert) {
                revert("CLOSED");
            }

            return;
        }

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));

        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool().getUserAccountData(address(this));
        (int256 collateralChangeBase, int256 debtChangeBase) = _diff(totalCollateralBase, totalDebtBase, ethPrice);

        if (collateralChangeBase == 0 && debtChangeBase == 0) {
            if (shouldRevert) {
                revert("unchanged");
            }

            return;
        }

        // FIXME maybe after it is actually changed?
        emit PositionChange(ethToken.balanceOf(address(this)), totalCollateralBase, totalDebtBase, collateralChangeBase, debtChangeBase);

        // FIXME explain all these cases
        if (collateralChangeBase > 0 && debtChangeBase > 0) {
            // console.log("==> Supply collateral then borrow debt");
            implementSupplyThenBorrow(SignedMathUpgradeable.abs(collateralChangeBase), SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase < 0) {
            // console.log("==> Repay debt then withdraw collateral");
            implementRepayThenWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase > 0 && debtChangeBase < 0) {
            // console.log("==> Repay debt then supply collateral"); // FIXME not found yet?

            implementRepay(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);
            implementSupply(SignedMathUpgradeable.abs(collateralChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase > 0) {
            // console.log("==> Borrow debt and withdraw collateral"); // FIXME then or and? // not found yet

            implementWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), oracle().getAssetPrice(address(stableToken)));
            implementBorrow(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase == 0 && debtChangeBase > 0) {
            // console.log("==> Just borrow debt");
            implementBorrow(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase == 0 && debtChangeBase < 0) {
            // console.log("==> Just repay debt");
            implementRepay(SignedMathUpgradeable.abs(debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase == 0) {
            // console.log("==> Just withdraw collateral"); // not found yet
            implementWithdraw(SignedMathUpgradeable.abs(collateralChangeBase), oracle().getAssetPrice(address(stableToken)));

        } else if (collateralChangeBase > 0 && debtChangeBase == 0) {
            // console.log("==> Just supply collateral"); // not found yet
            implementSupply(SignedMathUpgradeable.abs(collateralChangeBase), ethPrice);

        } else {
            revert("unreachable");
        }
    }

    function implementSupply(uint256 supplyCollateralBase, uint256 ethPrice) internal {
        uint256 collateralEth = baseToEth(supplyCollateralBase, ethPrice);
        uint256 collateralStable = ISwapHelper2(settings.swapHelper).swap(address(ethToken), address(stableToken), collateralEth, address(this));
        collateralSupply(collateralStable);
    }

    function implementBorrow(uint256 borrowDebtBase, uint256 ethPrice) internal {
        uint256 borrowEth = baseToEth(borrowDebtBase, ethPrice);
        debtBorrow(borrowEth);
    }

    function implementRepayThenWithdraw(uint256 withdrawCollateralBase, uint256 repayDebtBase, uint256 ethPrice) internal {
        uint256 repayDebtEth = baseToEth(repayDebtBase, ethPrice);

        uint256 myBalanceEth = ethToken.balanceOf(address(this));

        if (repayDebtEth < myBalanceEth) {
            implementRepay(repayDebtBase, ethPrice);
            implementWithdraw(withdrawCollateralBase, oracle().getAssetPrice(address(stableToken)));
            return;
        }

        uint256 flashLoanEth = repayDebtEth - myBalanceEth;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = ethToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanEth;

        bytes memory userData = abi.encode(FLASH_LOAN_PERFECT_REPAY_THEN_WITHDRAW, repayDebtEth, withdrawCollateralBase);
        balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
    }

    function implementSupplyThenBorrow(uint256 supplyCollateralBase, uint256 borrowDebtBase, uint256 ethPrice) internal {
        uint256 collateralEth = baseToEth(supplyCollateralBase, ethPrice) / 5;
        uint256 collateralStable = ISwapHelper2(settings.swapHelper).swap(address(ethToken), address(stableToken), collateralEth, address(this));

        uint256 flashLoanStable = collateralStable * 4;

        // uint256 usdcPosition =  baseToStable(collateralChangeBase, stablePrice); - usdcFlashLoan;
        uint256 positionStable = collateralStable * 5;

        uint256 borrowDebtEth = baseToEth(borrowDebtBase, ethPrice);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = stableToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanStable;

        bytes memory userData = abi.encode(FLASH_LOAN_PERFECT_SUPPLY_AND_BORROW, borrowDebtEth, positionStable);
        balancerVault.flashLoan(IFlashLoanRecipient(this), tokens, amounts, userData);
    }

    function implementRepay(uint256 repayDebtBase, uint256 ethPrice) internal {
        uint256 repayDebtEth = baseToEth(repayDebtBase, ethPrice);
        debtRepay(repayDebtEth);
    }

    function implementWithdraw(uint256 withdrawCollateralBase, uint256 stablePrice) internal {
        uint256 withdrawCollateralStable = baseToStable(withdrawCollateralBase, stablePrice);
        collateralWithdraw(withdrawCollateralStable);
        ISwapHelper2(settings.swapHelper).swap(address(stableToken), address(ethToken), withdrawCollateralStable, address(this));
    }

    function receiveFlashLoanPerfectSupplyAndBorrow(uint256 flashLoanStable, uint256 positionStable, uint256 borrowDebtEth) internal {
        collateralSupply(positionStable);

        debtBorrow(borrowDebtEth);

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 stablePrice = oracle().getAssetPrice(address(stableToken));

        uint256 ethToSwap = baseToEth(stableToBase(flashLoanStable, stablePrice), ethPrice);

        uint256 feeEth = ISwapHelper2(settings.swapHelper).calcSwapFee(address(ethToken), address(stableToken), ethToSwap);
        ethToSwap = ethToSwap + feeEth;

        ISwapHelper2(settings.swapHelper).swap(address(ethToken), address(stableToken), ethToSwap, address(this));

        require(stableToken.balanceOf(address(this)) > flashLoanStable, "NO FL STABLE");

        stableToken.transfer(address(balancerVault), flashLoanStable);

        uint256 dustStable = stableToken.balanceOf(address(this));
        if (dustStable > 0) {
            ISwapHelper2(settings.swapHelper).swap(address(stableToken), address(ethToken), dustStable, address(this));
        }
    }

    function receiveFlashLoanClosePosition(uint256 flashLoanEth) internal {
        debtRepay(type(uint256).max);

        collateralWithdraw(type(uint).max);

        ISwapHelper2(settings.swapHelper).swap(address(stableToken), address(ethToken), stableToken.balanceOf(address(this)), address(this));

        ethToken.transfer(address(balancerVault), flashLoanEth);
    }

    function receiveFlashLoanRepayThenWithdraw(uint256 flashLoanEth, uint256 repayDebtEth, uint256 withdrawCollateralBase) internal {
        debtRepay(repayDebtEth);

        uint256 withdrawCollateralStable = baseToStable(withdrawCollateralBase, oracle().getAssetPrice(address(stableToken)));
        collateralWithdraw(withdrawCollateralStable);

        ISwapHelper2(settings.swapHelper).swap(address(stableToken), address(ethToken), withdrawCollateralStable, address(this));

        ethToken.transfer(address(balancerVault), flashLoanEth);
    }

    function receiveFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, uint256[] memory feeAmounts, bytes memory userData) external  { // solhint-disable-line no-unused-vars
        require(msg.sender == address(balancerVault), "FL SENDER");

        (uint8 mode) = abi.decode(userData, (uint8));

        if (mode == FLASH_LOAN_PERFECT_SUPPLY_AND_BORROW) {
            (, uint256 borrowDebtEth, uint256 positionStable) = abi.decode(userData, (uint8, uint256, uint256));
            receiveFlashLoanPerfectSupplyAndBorrow(amounts[0], positionStable, borrowDebtEth);
            return;
        }

        if (mode == FLASH_LOAN_CLOSE_POSITION) {
            receiveFlashLoanClosePosition(amounts[0]);
            return;
        }

        if (mode == FLASH_LOAN_PERFECT_REPAY_THEN_WITHDRAW) {
            (, uint256 repayDebtEth, uint256 withdrawCollateralBase) = abi.decode(userData, (uint8, uint256, uint256));
            receiveFlashLoanRepayThenWithdraw(amounts[0], repayDebtEth, withdrawCollateralBase);
            return;
        }

        require(false, "UNKNOWN MODE");
    }

    function _collectTokens(address[] memory tokens, address to) internal {
        for (uint i=0; i<tokens.length; i++) {
            _collect(tokens[i], to);
        }
    }

    function _collect(address tokenAddress, address to) internal {
        if (tokenAddress == address(0)) {
            if (address(this).balance == 0) {
                return;
            }

            payable(to).transfer(address(this).balance);

            return;
        }

        uint256 _balance = ERC20Upgradeable(tokenAddress).balanceOf(address(this));
        if (_balance == 0) {
            return;
        }

        ERC20Upgradeable(tokenAddress).transfer(to, _balance);
    }

    function collectTokens(address[] memory tokens, address to) public onlyOwner {
        _collectTokens(tokens, to);
    }

    function deposit(uint256 amountEth) public whenNotPaused(FLAGS_DEPOSIT_PAUSED) whenNotPaused(FLAGS_POSITION_CLOSED) {
        require(amountEth > 0 && amountEth >= settings.minEthToDeposit, "AMOUNT");

        uint256 totalBalanceBaseBefore = totalBalance();

        ethToken.transferFrom(msg.sender, address(this), amountEth);
        _perfect(false);

        uint256 totalBalanceBaseAfter = totalBalance();

        if (totalSupply() == 0) {
            emit Deposit(totalBalanceBaseAfter, amountEth);
            _mint(msg.sender, totalBalanceBaseAfter);
            return;
        }

        uint256 totalBalanceAddedPercent = MathUpgradeable.mulDiv(totalBalanceBaseAfter, 10e18, totalBalanceBaseBefore) - 10e18;

        uint256 minted = MathUpgradeable.mulDiv(totalSupply(), totalBalanceAddedPercent, 10e18);
        emit Deposit(minted, amountEth);
        _mint(msg.sender, minted);
    }

    function withdraw(uint256 amount, bool shouldSwapToStable) public whenNotPaused(FLAGS_WITHDRAW_PAUSED) {
        require(amount > 0 && amount >= settings.minAmountToWithdraw, "AMOUNT");

        uint256 percent = MathUpgradeable.mulDiv(amount, 10e18, totalSupply());

        _burn(msg.sender, amount);

        uint256 amountBase = MathUpgradeable.mulDiv(totalBalance(), percent, 10e18);
        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 amountEth = baseToEth(amountBase, ethPrice);

        require(amountEth > 0, "ZERO");
        require(amountEth <= ethToken.balanceOf(address(this)), "NOT READY");

        uint256 amountStable = 0;

        if (shouldSwapToStable) {
            amountStable = ISwapHelper2(settings.swapHelper).swap(address(ethToken), address(stableToken), amountEth, msg.sender);
        } else {
            ethToken.transfer(msg.sender, amountEth);
        }

        emit Withdraw(amount, amountEth, amountStable);

        _perfect(false);
    }

    function totalBalance() public view returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , ,) = pool().getUserAccountData(address(this));
        uint256 netBase = totalCollateralBase - totalDebtBase;

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 ethBalanceBase = MathUpgradeable.mulDiv(ethToken.balanceOf(address(this)), ethPrice, 10 ** ethTokenDecimals);

        return ethBalanceBase + netBase;
    }

    function pool() public view returns (IPool) {
        return IPool(aaveAddressProvider.getPool());
    }

    function poolDataProvider() public view returns (IPoolDataProvider) {
        return IPoolDataProvider(aaveAddressProvider.getPoolDataProvider());
    }

    function oracle() public view returns (IAaveOracle) {
        return IAaveOracle(aaveAddressProvider.getPriceOracle());
    }

    function debtBorrow(uint256 amount) internal {
        pool().borrow(address(ethToken), amount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));
    }

    function debtRepay(uint256 amount) internal {
        pool().repay(address(ethToken), amount, INTEREST_RATE_MODE_VARIABLE, address(this));
    }

    function collateralSupply(uint256 amount) internal {
        pool().supply(address(stableToken), amount, address(this), 0);
        pool().setUserUseReserveAsCollateral(address(stableToken), true);
    }

    function collateralWithdraw(uint256 amount) internal {
        pool().withdraw(address(stableToken), amount, address(this));
    }

    function diffBaseClamped(uint256 a, uint256 b) internal view returns (int256) {
        int256 amountDiff = SafeCastUpgradeable.toInt256(a) - SafeCastUpgradeable.toInt256(b);
        return (SignedMathUpgradeable.abs(amountDiff) >= settings.minAmountToChangePositionBase) ? amountDiff : int256(0);
    }

    function baseToStable(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, 10 ** stableTokenDecimals, stablePrice);
    }

    function stableToBase(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, stablePrice, 10 ** stableTokenDecimals);
    }

    function baseToEth(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
        return MathUpgradeable.mulDiv(amount, 10 ** ethTokenDecimals, ethPrice);
    }

    function ethToBase(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
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

    function setSettings(Settings calldata _settings) public onlyOwner {
        if (_settings.swapHelper != settings.swapHelper) {
            ethToken.approve(settings.swapHelper, 0);
            stableToken.approve(settings.swapHelper, 0);

            ethToken.approve(_settings.swapHelper, type(uint256).max);
            stableToken.approve(_settings.swapHelper, type(uint256).max);
        }

        settings = _settings;
    }

    function _ltv() internal view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory poolConfiguration = pool().getConfiguration(address(stableToken));
        uint256 mask = (1 << 16) - 1;
        return poolConfiguration.data & mask;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

