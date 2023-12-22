/* solhint-disable no-inline-assembly, no-console */
pragma solidity ^0.8.19;

import { IERC20MetadataUpgradeable } from "./IERC20MetadataUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { IVault, IERC20 } from "./IVault.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";

import { IPool } from "./IPool.sol";
import { IAaveOracle } from "./IAaveOracle.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
import { IPoolDataProvider } from "./IPoolDataProvider.sol";
import { DataTypes} from "./DataTypes.sol";

import { ISwapHelper2 } from "./ISwapHelper2.sol";

// import "hardhat/console.sol";

uint256 constant INTEREST_RATE_MODE_VARIABLE = 2;

uint8 constant FLASH_LOAN_CLOSE_POSITION = 3;
uint8 constant FLASH_LOAN_PERFECT_SUPPLY_AND_BORROW = 4;
uint8 constant FLASH_LOAN_PERFECT_REPAY_THEN_WITHDRAW = 5;

uint8 constant FLAGS_POSITION_CLOSED = 1 << 0;
uint8 constant FLAGS_DEPOSIT_PAUSED  = 1 << 1;
uint8 constant FLAGS_WITHDRAW_PAUSED = 1 << 2;

contract DeltaNeutralHell is IFlashLoanRecipient, ERC20Upgradeable, OwnableUpgradeable {
    IPoolAddressesProvider private aaveAddressProvider;
    IVault private balancerVault;

    IERC20 public stableToken;
    IERC20 public ethToken;

    ISwapHelper2 public swapHelper;

    int256 public minAmountToChangePositionBase;

    uint8 public additionalLtvDistancePercent; // in tens, so "10" == 1%
    uint8 public positionSizePercent;
    uint8 public flags;
    uint8 private _decimals;

    uint8 private stableTokenDecimals;
    uint8 private ethTokenDecimals;
    // we still have 16 bits here

    event PositionChange(uint256 ethBalance, uint256 totalCollateralBase, uint256 totalDebtBase, int256 collateralChangeBase, int256 debtChangeBase);
    event Withdraw(uint256 amountBase, uint256 amountEth, uint256 amountStable);

    function initialize(
        uint8 __decimals,
        string memory symbol,
        string memory name,
        address _stableToken,
        address _ethToken,
        address _balancerVault,
        address _aaveAddressProvider,
        address _swapHelper,
        uint256 _minAmountToChangePositionBase,
        uint8 _additionalLtvDistancePercent,
        uint8 _positionSizePercent
    )
        public
        initializer
    {
        __ERC20_init(name, symbol);
        __Ownable_init();

        _decimals = __decimals;

        aaveAddressProvider = IPoolAddressesProvider(_aaveAddressProvider);

        swapHelper = ISwapHelper2(_swapHelper);
        balancerVault = IVault(_balancerVault);

        ethToken = IERC20(_ethToken);
        stableToken = IERC20(_stableToken);

        ethToken.approve(_swapHelper, type(uint256).max);
        stableToken.approve(_swapHelper, type(uint256).max);

        ethTokenDecimals = IERC20MetadataUpgradeable(address(ethToken)).decimals();
        stableTokenDecimals = IERC20MetadataUpgradeable(address(stableToken)).decimals();

        minAmountToChangePositionBase = int256(_minAmountToChangePositionBase);
        additionalLtvDistancePercent = _additionalLtvDistancePercent;
        positionSizePercent = _positionSizePercent;

        ethToken.approve(address(pool()), type(uint256).max);
        stableToken.approve(address(pool()), type(uint256).max);

        _transferOwnership(msg.sender);
    }

    modifier whenNotPaused(uint8 whatExactly) {
        require((flags & whatExactly) != whatExactly, "FLAGS");
        _;
    }

    function closePosition() public whenNotPaused(FLAGS_POSITION_CLOSED) onlyOwner {
        flags = flags | FLAGS_POSITION_CLOSED;

        (, , address variableDebtTokenAddress) = poolDataProvider().getReserveTokensAddresses(address(ethToken));

        uint256 debtEth = IERC20(variableDebtTokenAddress).balanceOf(address(this));

        uint256 balanceEth = ethToken.balanceOf(address(this));

        if (balanceEth > debtEth) {
            // FIXME what if 0?
            debtRepay(type(uint256).max);

            // FIXME what if 0?
            collateralWithdraw(type(uint).max);
            swapHelper.swap(address(stableToken), address(ethToken), stableToken.balanceOf(address(this)), address(this));

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

        uint256 idealTotalCollateralBase = totalAssetsBase * positionSizePercent / 100 * 999 / 1000;
        uint256 idealTotalDebtBase = idealTotalCollateralBase * (_ltv() - (additionalLtvDistancePercent * 10)) / 10000;

        // positive means supply; negative: withdraw
        collateralChangeBase = diffBaseClamped(idealTotalCollateralBase, totalCollateralBase);

        // positive means borrow; negative: repay
        debtChangeBase = diffBaseClamped(idealTotalDebtBase, totalDebtBase);
    }

    function perfect() public {
        _perfect(true);
    }

    function _perfect(bool shouldRevert) internal {
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
            implementSupplyThenBorrow(uint256(collateralChangeBase), uint256(debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase < 0) {
            // console.log("==> Repay debt then withdraw collateral");
            implementRepayThenWithdraw(uint256(-collateralChangeBase), uint256(-debtChangeBase), ethPrice);

        } else if (collateralChangeBase > 0 && debtChangeBase < 0) {
            // console.log("==> Repay debt then supply collateral"); // FIXME not found yet?

            implementRepay(uint256(-debtChangeBase), ethPrice);
            implementSupply(uint256(collateralChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase > 0) {
            // console.log("==> Borrow debt and withdraw collateral"); // FIXME then or and? // not found yet

            implementWithdraw(uint256(-collateralChangeBase), oracle().getAssetPrice(address(stableToken)));
            implementBorrow(uint256(debtChangeBase), ethPrice);

        } else if (collateralChangeBase == 0 && debtChangeBase > 0) {
            // console.log("==> Just borrow debt");
            implementBorrow(uint256(debtChangeBase), ethPrice);

        } else if (collateralChangeBase == 0 && debtChangeBase < 0) {
            // console.log("==> Just repay debt");
            implementRepay(uint256(-debtChangeBase), ethPrice);

        } else if (collateralChangeBase < 0 && debtChangeBase == 0) {
            // console.log("==> Just withdraw collateral"); // not found yet
            implementWithdraw(uint256(-collateralChangeBase), oracle().getAssetPrice(address(stableToken)));

        } else if (collateralChangeBase > 0 && debtChangeBase == 0) {
            // console.log("==> Just supply collateral"); // not found yet
            implementSupply(uint256(collateralChangeBase), ethPrice);

        } else {
            revert("unreachable");
        }
    }

    function implementSupply(uint256 supplyCollateralBase, uint256 ethPrice) internal {
        uint256 collateralEth = baseToEth(supplyCollateralBase, ethPrice);
        uint256 collateralStable = swapHelper.swap(address(ethToken), address(stableToken), collateralEth, address(this));
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
        uint256 collateralStable = swapHelper.swap(address(ethToken), address(stableToken), collateralEth, address(this));

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
        swapHelper.swap(address(stableToken), address(ethToken), withdrawCollateralStable, address(this));
    }

    function receiveFlashLoanPerfectSupplyAndBorrow(uint256 flashLoanStable, uint256 positionStable, uint256 borrowDebtEth) internal {
        collateralSupply(positionStable);

        debtBorrow(borrowDebtEth);

        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 stablePrice = oracle().getAssetPrice(address(stableToken));

        uint256 ethToSwap = baseToEth(stableToBase(flashLoanStable, stablePrice), ethPrice);

        uint256 feeEth = swapHelper.calcSwapFee(address(ethToken), address(stableToken), ethToSwap);
        ethToSwap = ethToSwap + feeEth;

        swapHelper.swap(address(ethToken), address(stableToken), ethToSwap, address(this));

        require(stableToken.balanceOf(address(this)) > flashLoanStable, "NO FL STABLE");

        stableToken.transfer(address(balancerVault), flashLoanStable);

        uint256 dustStable = stableToken.balanceOf(address(this));
        if (dustStable > 0) {
            swapHelper.swap(address(stableToken), address(ethToken), dustStable, address(this));
        }
    }

    function receiveFlashLoanClosePosition(uint256 flashLoanEth) internal {
        debtRepay(type(uint256).max);

        collateralWithdraw(type(uint).max);

        swapHelper.swap(address(stableToken), address(ethToken), stableToken.balanceOf(address(this)), address(this));

        ethToken.transfer(address(balancerVault), flashLoanEth);
    }

    function receiveFlashLoanRepayThenWithdraw(uint256 flashLoanEth, uint256 repayDebtEth, uint256 withdrawCollateralBase) internal {
        debtRepay(repayDebtEth);

        uint256 withdrawCollateralStable = baseToStable(withdrawCollateralBase, oracle().getAssetPrice(address(stableToken)));
        collateralWithdraw(withdrawCollateralStable);

        swapHelper.swap(address(stableToken), address(ethToken), withdrawCollateralStable, address(this));

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

    function collect(address token, uint256 amount) public onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    function depositEth(uint256 amountEth) public whenNotPaused(FLAGS_DEPOSIT_PAUSED) whenNotPaused(FLAGS_POSITION_CLOSED) {
        require(amountEth > 0, "AMOUNT");

        uint256 totalBalanceBaseBefore = totalBalance();

        ethToken.transferFrom(msg.sender, address(this), amountEth);
        _perfect(false);

        uint256 totalBalanceBaseAfter = totalBalance();

        if (totalSupply() == 0) {
            _mint(msg.sender, totalBalanceBaseAfter);
            return;
        }

        uint256 totalBalanceAddedPercent = (totalBalanceBaseAfter * 10e18 / totalBalanceBaseBefore) - 10e18;

        uint256 minted = totalSupply() * totalBalanceAddedPercent / 10e18;
        _mint(msg.sender, minted);
    }

    function withdraw(uint256 amount, bool shouldSwapToStable) public whenNotPaused(FLAGS_WITHDRAW_PAUSED) {
        require(amount > 0, "ZERO0");

        uint256 percent = amount * 10e18 / totalSupply();

        _burn(msg.sender, amount);

        uint256 amountBase = totalBalance() * percent / 10e18;
        uint256 ethPrice = oracle().getAssetPrice(address(ethToken));
        uint256 amountEth = baseToEth(amountBase, ethPrice);

        require(amountEth > 0, "ZERO1");
        require(amountEth <= ethToken.balanceOf(address(this)), "NOT READY");

        uint256 amountStable = 0;

        if (shouldSwapToStable) {
            amountStable = swapHelper.swap(address(ethToken), address(stableToken), amountEth, msg.sender);
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
        uint256 ethBalanceBase = ethToken.balanceOf(address(this)) * ethPrice / 10 ** ethTokenDecimals;

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
        int256 amountDiff = int256(a) - int256(b);
        return (amountDiff < -minAmountToChangePositionBase || amountDiff > minAmountToChangePositionBase) ? amountDiff : int256(0);
    }

    function baseToStable(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return amount * 10 ** stableTokenDecimals / stablePrice;
    }

    function stableToBase(uint256 amount, uint256 stablePrice) internal view returns (uint256) {
        return amount * stablePrice / 10 ** stableTokenDecimals;
    }

    function baseToEth(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
        return amount * 10 ** ethTokenDecimals / ethPrice;
    }

    function ethToBase(uint256 amount, uint256 ethPrice) internal view returns (uint256) {
        return amount * ethPrice / 10 ** ethTokenDecimals;
    }

    function ethToStable(uint256 amount, uint256 ethPrice, uint256 stablePrice) internal view returns (uint256) {
        return amount * ethPrice / 10 ** (ethTokenDecimals - stableTokenDecimals) / stablePrice;
    }

    function stableToEth(uint256 amount, uint256 stablePrice, uint256 ethPrice) internal view returns (uint256) {
        return amount * stablePrice * 10 ** (ethTokenDecimals - stableTokenDecimals) / ethPrice;
    }

    function setSettings(uint256 _minAmountToChangePositionBase, uint8 _additionalLtvDistancePercent, uint8 _positionSizePercent, address _swapHelper) public onlyOwner {
        minAmountToChangePositionBase = int256(_minAmountToChangePositionBase);
        additionalLtvDistancePercent = _additionalLtvDistancePercent;
        positionSizePercent = _positionSizePercent;
        swapHelper = ISwapHelper2(_swapHelper);
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

