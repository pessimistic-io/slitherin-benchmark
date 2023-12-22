// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// inheritances
import { ILeverageStrategy } from "./ILeverageStrategy.sol";
import { IFlashLoanRecipient } from "./IFlashLoanRecipient.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

// libraries
import { SafeERC20 } from "./SafeERC20.sol";
import { OpenOceanAggregator } from "./OpenOceanAggregator.sol";
import { Math } from "./Math.sol";
import { SafeMath } from "./SafeMath.sol";

// interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IFlashLoans } from "./IFlashLoans.sol";
import { IPool } from "./IPool.sol";
import { IPoolAddressProvider } from "./IPoolAddressProvider.sol";
import { IFactorLeverageVault } from "./IFactorLeverageVault.sol";

contract AAVEV3LeverageStrategy is
    Initializable,
    ILeverageStrategy,
    IFlashLoanRecipient,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // =============================================================
    //                         Libraries
    // =============================================================

    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeMath for uint256;

    // =============================================================
    //                         Events
    // =============================================================

    event LeverageAdded(uint256 amount, uint256 debt);
    event LeverageRemoved(uint256 debt);
    event LeverageClosed(uint256 amount, uint256 debt);
    event AssetSwitched(address newAsset, uint256 balance);
    event DebtSwitched(address newDebt, uint256 balance);
    event Withdraw(uint256 amount);
    event Repay(uint256 amount);
    event Supply(uint256 amount);
    event Borrow(uint256 amount);
    event WithdrawTokenInCaseStuck(address tokenAddress, uint256 amount);
    event LeverageChargeFee(uint256 amount);

    // =============================================================
    //                         Errors
    // =============================================================

    error NOT_OWNER();
    error NOT_BALANCER();
    error NOT_SELF();
    error INVALID_ASSET();
    error INVALID_DEBT();
    error INVALID_TOKEN();
    error AMOUNT_TOO_MUCH();

    // =============================================================
    //                         Constants
    // =============================================================

    // aave
    address public constant provider = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;

    // balancer
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // =============================================================
    //                         Storages
    // =============================================================

    uint256 private _positionId;

    IERC721 private _vaultManager;

    IERC20 private _asset;

    IERC20 private _debtToken;

    IERC20 public _assetPool;

    IERC20 public _debtPool;

    uint8 private flMode; // 1 = addLeverage, 2 = removeLeverage, 3 = switch asset, 4 = switch debt, 5 = close leverage

    // =============================================================
    //                      Functions
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 __positionId,
        address _vaultManagerAddress,
        address _assetAddress,
        address _debtAddress,
        address _assetPoolAddress,
        address _debtPoolAddress
    ) public initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _positionId = __positionId;
        _vaultManager = IERC721(_vaultManagerAddress);
        _asset = IERC20(_assetAddress);
        _debtToken = IERC20(_debtAddress);
        _assetPool = IERC20(_assetPoolAddress);
        _debtPool = IERC20(_debtPoolAddress);
    }

    function vaultManager() public view returns (address) {
        return address(_vaultManager);
    }

    function positionId() public view returns (uint256) {
        return _positionId;
    }

    function asset() public view returns (address) {
        return address(_asset);
    }

    function debtToken() public view returns (address) {
        return address(_debtToken);
    }

    function assetPool() public view returns (address) {
        return address(_assetPool);
    }

    function debtPool() public view returns (address) {
        return address(_debtPool);
    }

    function assetBalance() public view returns (uint256) {
        // balance as collateral in Atoken AAVE
        return _assetPool.balanceOf(address(this));
    }

    function debtBalance() public view returns (uint256) {
        // debt in variable debt token AAVE
        return _debtPool.balanceOf(address(this));
    }

    function owner() public view returns (address) {
        return _vaultManager.ownerOf(_positionId);
    }

    function addLeverage(uint256 amount, uint256 debt, bytes calldata data) external onlyOwner {
        // process = flashloan the expected debt -> swap the expected debt to asset -> supply the asset -> borrow to repay the flashloan

        address poolAddress = IPoolAddressProvider(provider).getPool();
        if (amount > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

            // supply
            IERC20(asset()).approve(poolAddress, amount);
            IPool(poolAddress).supply(asset(), amount, address(this), 0);
        }

        if (debt > 0) {
            // execute flashloan
            bytes memory params = abi.encode(debt, poolAddress, data);
            address[] memory tokens = new address[](1);
            tokens[0] = debtToken();
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = debt;
            flMode = 1;
            IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
            flMode = 0;
        }

        emit LeverageAdded(amount, debt);
    }

    function _flAddLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, address poolAddress, bytes memory data) = abi.decode(params, (uint256, address, bytes));

        // swap debt to asset
        // the only solution to convert from memory to calldata
        uint256 outAmountDebt = this.swapBySelf(debtToken(), asset(), amount, data);

        // supply
        IERC20(asset()).approve(poolAddress, outAmountDebt);
        IPool(poolAddress).supply(asset(), outAmountDebt, address(this), 0);

        // borrow the equivalent amount using our new collateral
        IPool(poolAddress).borrow(debtToken(), amount + feeAmount, 2, 0, address(this));

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, amount + feeAmount);
    }

    function removeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw the asset -> swap the asset -> borrow to repay the flashloan

        address poolAddress = IPoolAddressProvider(provider).getPool();

        // execute flashloan
        bytes memory params = abi.encode(amount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 2;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        // transfer to owner
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransfer(owner(), balance);

        emit LeverageRemoved(amount);
    }

    function _flRemoveLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, address poolAddress, bytes memory data) = abi.decode(params, (uint256, address, bytes));

        uint256 flashLoanAmount = debtBalance(); // assuming the flashloan equal debt balance

        // repay
        IERC20(debtToken()).approve(poolAddress, flashLoanAmount);
        IPool(poolAddress).repay(debtToken(), flashLoanAmount, 2, address(this));

        // withdraw
        IPool(poolAddress).withdraw(asset(), amount, address(this));

        // swap asset to debt
        uint256 outAmount = this.swapBySelf(asset(), debtToken(), amount, data);

        // you can't swap asset more than debt value
        if (outAmount > flashLoanAmount) revert AMOUNT_TOO_MUCH();

        uint256 remainingFlashLoanAmount = flashLoanAmount - _debtToken.balanceOf(address(this));

        // borrow
        IPool(poolAddress).borrow(debtToken(), remainingFlashLoanAmount + feeAmount, 2, 0, address(this));

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, flashLoanAmount + feeAmount);
    }

    function switchAsset(address newAsset, uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to a new asset -> supply the new asset -> borrow to repay the flashloan

        // check if newAsset exist
        if (IFactorLeverageVault(vaultManager()).assets(newAsset) == address(0)) revert INVALID_ASSET();

        address poolAddress = IPoolAddressProvider(provider).getPool();

        // execute flashloan
        bytes memory params = abi.encode(newAsset, amount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 3;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;
    }

    function _flSwitchAsset(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (address newAsset, uint256 amount, address poolAddress, bytes memory data) = abi.decode(
            params,
            (address, uint256, address, bytes)
        );

        uint256 currentDebtBalance = debtBalance();

        // repay all debt
        IERC20(debtToken()).approve(poolAddress, currentDebtBalance);
        IPool(poolAddress).repay(debtToken(), currentDebtBalance, 2, address(this));

        // withdraw all
        IPool(poolAddress).withdraw(asset(), assetBalance(), address(this));

        // swap asset to new asset
        this.swapBySelf(asset(), newAsset, amount, data);

        // change asset and pool to new one
        _asset = IERC20(newAsset);
        _assetPool = IERC20(IFactorLeverageVault(vaultManager()).assets(newAsset));

        // supply the new asset
        IERC20(asset()).approve(poolAddress, IERC20(asset()).balanceOf(address(this)));
        IPool(poolAddress).supply(asset(), IERC20(asset()).balanceOf(address(this)), address(this), 0);

        // borrow
        IPool(poolAddress).borrow(debtToken(), currentDebtBalance + feeAmount, 2, 0, address(this));

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, debtBalance() + feeAmount);

        emit AssetSwitched(newAsset, assetBalance());
    }

    function switchDebt(address newDebtToken, uint256 newDebt, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> borrow a new debt -> swap the new debt to repay the flash loan

        // check if newDebtToken exist
        if (IFactorLeverageVault(vaultManager()).debts(newDebtToken) == address(0)) revert INVALID_DEBT();

        address poolAddress = IPoolAddressProvider(provider).getPool();

        // execute flashloan
        bytes memory params = abi.encode(newDebtToken, newDebt, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 4;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;
    }

    function _flSwitchDebt(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (address newDebtToken, uint256 newDebt, address poolAddress, bytes memory data) = abi.decode(
            params,
            (address, uint256, address, bytes)
        );

        uint256 flashLoanAmount = debtBalance(); // flashloan amount = debt balance
        address oldDebtToken = debtToken();

        // repay all debt
        IERC20(debtToken()).approve(poolAddress, debtBalance());
        IPool(poolAddress).repay(debtToken(), debtBalance(), 2, address(this));

        _debtToken = IERC20(newDebtToken);
        _debtPool = IERC20(IFactorLeverageVault(vaultManager()).debts(newDebtToken));

        // borrow
        IPool(poolAddress).borrow(debtToken(), newDebt + feeAmount, 2, 0, address(this));

        // swap new debt to flashloan
        this.swapBySelf(debtToken(), oldDebtToken, newDebt, data);

        // repay Flashloan
        IERC20(oldDebtToken).safeTransfer(balancerVault, flashLoanAmount + feeAmount);

        emit DebtSwitched(newDebtToken, assetBalance());
    }

    function closeLeverage(uint256 amount, bytes calldata data) external onlyOwner {
        // process = flashloan to repay all debt -> withdraw all asset -> swap the asset to repay the flash loan

        // notes: if amount > debt value then the all position become debtToken
        // for example, when ETH/USDC closes the leverage can be withdrawn as ETH or USDC
        address poolAddress = IPoolAddressProvider(provider).getPool();

        uint256 assetPosition = assetBalance();
        uint256 debtPosition = debtBalance();

        // execute flashloan
        bytes memory params = abi.encode(amount, poolAddress, data);
        address[] memory tokens = new address[](1);
        tokens[0] = debtToken();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debtBalance();

        flMode = 5;
        IFlashLoans(balancerVault).flashLoan(address(this), tokens, amounts, params);
        flMode = 0;

        // transfer asset and debt token to owner
        IERC20(asset()).safeTransfer(owner(), IERC20(asset()).balanceOf(address(this)));
        IERC20(debtToken()).safeTransfer(owner(), IERC20(debtToken()).balanceOf(address(this)));

        emit LeverageClosed(assetPosition, debtPosition);
    }

    function _flCloseLeverage(bytes calldata params, uint256 feeAmount) internal {
        // decode params
        (uint256 amount, address poolAddress, bytes memory data) = abi.decode(params, (uint256, address, bytes));

        uint256 flashLoanAmount = debtBalance(); // assuming the flashloan equal debt balance

        // repay
        IERC20(debtToken()).approve(poolAddress, debtBalance());
        IPool(poolAddress).repay(debtToken(), debtBalance(), 2, address(this));

        // withdraw
        IPool(poolAddress).withdraw(asset(), assetBalance(), address(this));

        // swap asset to debt
        this.swapBySelf(asset(), debtToken(), amount, data);

        // repay debt Flashloan
        IERC20(debtToken()).safeTransfer(balancerVault, flashLoanAmount + feeAmount);
    }

    function swapBySelf(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata data
    ) public returns (uint256) {
        if (msg.sender != address(this)) revert NOT_SELF();
        uint256 outAmount = OpenOceanAggregator.swap(tokenIn, tokenOut, amount, data);
        uint256 feeCharge = leverageFeeCharge(outAmount, tokenOut);
        return outAmount - feeCharge;
    }

    function leverageFeeCharge(uint256 amount, address token) internal returns (uint256) {
        uint256 leverageFee = IFactorLeverageVault(vaultManager()).leverageFee();
        uint256 feeScale = IFactorLeverageVault(vaultManager()).FEE_SCALE();
        address factorFeeRecipient = IFactorLeverageVault(vaultManager()).feeRecipient();
        uint256 depositFeeAmount = amount.mul(leverageFee).div(feeScale);

        IERC20(token).safeTransfer(factorFeeRecipient, depositFeeAmount);

        emit LeverageChargeFee(depositFeeAmount);

        return depositFeeAmount;
    }

    function supply(uint256 amount) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        // supply
        address poolAddress = IPoolAddressProvider(provider).getPool();
        IERC20(asset()).approve(poolAddress, amount);
        IPool(poolAddress).supply(asset(), amount, address(this), 0);

        emit Supply(amount);
    }

    function borrow(uint256 amount) external onlyOwner {
        address poolAddress = IPoolAddressProvider(provider).getPool();
        IERC20(debtToken()).approve(poolAddress, amount);
        IPool(poolAddress).borrow(debtToken(), amount, 2, 0, address(this));
        IERC20(debtToken()).safeTransfer(owner(), amount);

        emit Borrow(amount);
    }

    function repay(uint256 amount) external onlyOwner {
        IERC20(debtToken()).safeTransferFrom(msg.sender, address(this), amount);

        address poolAddress = IPoolAddressProvider(provider).getPool();

        IERC20(debtToken()).approve(poolAddress, amount);
        IPool(poolAddress).repay(debtToken(), amount, 2, address(this));

        emit Repay(amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        address poolAddress = IPoolAddressProvider(provider).getPool();
        _assetPool.approve(poolAddress, amount);
        IPool(poolAddress).withdraw(asset(), amount, address(this));

        IERC20(asset()).safeTransfer(owner(), amount);

        emit Withdraw(amount);
    }

    function withdrawTokenInCaseStuck(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == assetPool() || tokenAddress == debtPool()) revert INVALID_TOKEN();
        IERC20(tokenAddress).safeTransfer(owner(), amount);
        emit WithdrawTokenInCaseStuck(tokenAddress, amount);
    }

    function version() external pure returns (string memory) {
        return '0.1';
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes calldata params
    ) external override nonReentrant {
        if (msg.sender != balancerVault) revert NOT_BALANCER();
        uint256 feeAmount = 0;
        if (feeAmounts.length > 0) {
            feeAmount = feeAmounts[0];
        }
        if (flMode == 1) _flAddLeverage(params, feeAmount);
        if (flMode == 2) _flRemoveLeverage(params, feeAmount);
        if (flMode == 3) _flSwitchAsset(params, feeAmount);
        if (flMode == 4) _flSwitchDebt(params, feeAmount);
        if (flMode == 5) _flCloseLeverage(params, feeAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // check if the new implementation is registered
        if (IFactorLeverageVault(vaultManager()).isRegisteredUpgrade(_getImplementation(), newImplementation) == false)
            revert('INVALID_UPGRADE');
    }

    // =============================================================
    //                      modifiers
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != _vaultManager.ownerOf(_positionId)) revert NOT_OWNER();
        _;
    }
}

