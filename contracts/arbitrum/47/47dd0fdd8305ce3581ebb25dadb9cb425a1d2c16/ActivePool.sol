// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./MathUpgradeable.sol";

import "./SafetyTransfer.sol";

import "./IActivePool.sol";
import "./ICollSurplusPool.sol";
import "./IDefaultPool.sol";
import "./IDeposit.sol";
import "./IStabilityPool.sol";
import "./ISmartVault.sol";

/*
 * The Active Pool holds the collaterals and debt amounts for all active vessels.
 *
 * When a vessel is liquidated, it's collateral and debt tokens are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IActivePool
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    string public constant NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public stabilityPoolAddress;
    address public vesselManagerAddress;
    address public vesselManagerOperationsAddress;

    ICollSurplusPool public collSurplusPool;
    IDefaultPool public defaultPool;

    mapping(address => uint256) internal assetsBalances;
    mapping(address => uint256) internal debtTokenBalances;
    mapping(address => address) public assetVault;

    // --- Modifiers ---

    modifier callerIsBorrowerOpsOrDefaultPool() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == address(defaultPool),
            "ActivePool: Caller is not an authorized Preon contract"
        );
        _;
    }

    modifier callerIsBorrowerOpsOrVesselMgr() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == vesselManagerAddress,
            "ActivePool: Caller is not an authorized Preon contract"
        );
        _;
    }

    modifier callerIsBorrowerOpsOrStabilityPoolOrVesselMgr() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == stabilityPoolAddress ||
                msg.sender == vesselManagerAddress,
            "ActivePool: Caller is not an authorized Preon contract"
        );
        _;
    }

    modifier callerIsBorrowerOpsOrStabilityPoolOrVesselMgrOrVesselMgrOps() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == stabilityPoolAddress ||
                msg.sender == vesselManagerAddress ||
                msg.sender == vesselManagerOperationsAddress,
            "ActivePool: Caller is not an authorized Preon contract"
        );
        _;
    }

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _collSurplusPoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _vesselManagerAddress,
        address _vesselManagerOperationsAddress
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        borrowerOperationsAddress = _borrowerOperationsAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        stabilityPoolAddress = _stabilityPoolAddress;
        vesselManagerAddress = _vesselManagerAddress;
        vesselManagerOperationsAddress = _vesselManagerOperationsAddress;
    }

    // --- Getters for public variables. Required by IPool interface ---

    function getAssetBalance(
        address _asset
    ) external view override returns (uint256) {
        return assetsBalances[_asset];
    }

    function getDebtTokenBalance(
        address _asset
    ) external view override returns (uint256) {
        return debtTokenBalances[_asset];
    }

    function balanceOf(address _asset) external view returns (uint256) {
        address _assetVault = assetVault[_asset];
        require(_assetVault != address(0), "ActivePool: Vault is not set");

        return
            IERC20Upgradeable(_asset).balanceOf(address(this)) +
            IERC20Upgradeable(_asset).balanceOf(_assetVault);
    }

    function increaseDebt(
        address _collateral,
        uint256 _amount
    ) external override callerIsBorrowerOpsOrVesselMgr {
        uint256 newDebt = debtTokenBalances[_collateral] + _amount;
        debtTokenBalances[_collateral] = newDebt;
        emit ActivePoolDebtUpdated(_collateral, newDebt);
    }

    function decreaseDebt(
        address _asset,
        uint256 _amount
    ) external override callerIsBorrowerOpsOrStabilityPoolOrVesselMgr {
        uint256 newDebt = debtTokenBalances[_asset] - _amount;
        debtTokenBalances[_asset] = newDebt;
        emit ActivePoolDebtUpdated(_asset, newDebt);
    }

    // --- Pool functionality ---

    function sendAsset(
        address _asset,
        address _account,
        uint256 _amount
    )
        external
        override
        nonReentrant
        callerIsBorrowerOpsOrStabilityPoolOrVesselMgrOrVesselMgrOps
    {
        _amount = _withdrawFromVault(_asset, _amount);

        uint256 safetyTransferAmount = SafetyTransfer.decimalsCorrection(
            _asset,
            _amount
        );
        if (safetyTransferAmount == 0) return;

        uint256 newBalance = assetsBalances[_asset] - _amount;
        assetsBalances[_asset] = newBalance;

        IERC20Upgradeable(_asset).safeTransfer(_account, safetyTransferAmount);

        if (isERC20DepositContract(_account)) {
            IDeposit(_account).receivedERC20(_asset, _amount);
        }

        _depositToVault(_asset);

        emit ActivePoolAssetBalanceUpdated(_asset, newBalance);
        emit AssetSent(_account, _asset, safetyTransferAmount);
    }

    function _withdrawFromVault(
        address _asset,
        uint256 _amount
    ) internal returns (uint256) {
        address _assetVault = assetVault[_asset];

        require(_assetVault != address(0), "ActivePool: Vault is not set");

        uint256 _balance = IERC20Upgradeable(_asset).balanceOf(address(this));

        if (_balance < _amount) {
            uint256 _share = ISmartVault(_assetVault).previewWithdraw(
                _amount - _balance
            );

            ISmartVault(_assetVault).withdraw(_share);
        }

        return
            MathUpgradeable.min(
                _amount,
                IERC20Upgradeable(_asset).balanceOf(address(this))
            );
    }

    function isERC20DepositContract(
        address _account
    ) private view returns (bool) {
        return (_account == address(defaultPool) ||
            _account == address(collSurplusPool) ||
            _account == stabilityPoolAddress);
    }

    function receivedERC20(
        address _asset,
        uint256 _amount
    ) external override callerIsBorrowerOpsOrDefaultPool {
        uint256 newBalance = assetsBalances[_asset] + _amount;
        assetsBalances[_asset] = newBalance;
        emit ActivePoolAssetBalanceUpdated(_asset, newBalance);

        _depositToVault(_asset);
    }

    function _depositToVault(address _asset) internal {
        address _assetVault = assetVault[_asset];
        require(_assetVault != address(0), "ActivePool: Vault is not set");

        uint256 balance = IERC20Upgradeable(_asset).balanceOf(address(this));

        if (balance == 0) return;

        IERC20Upgradeable(_asset).safeApprove(_assetVault, 0);
        IERC20Upgradeable(_asset).safeApprove(_assetVault, balance);

        ISmartVault(_assetVault).depositAndInvest(balance);

        emit CollateralDepositedIntoSmartVault(_asset, balance, _assetVault);
    }

    function setAssetVault(address _asset, address _vault) external onlyOwner {
        require(_asset != address(0), "ActivePool: Invalid asset address");
        require(_vault != address(0), "ActivePool: Invalid vault address");
        require(
            _asset == ISmartVault(_vault).underlying(),
            "ActivePool: Token mismatch"
        );

        address _oldVault = assetVault[_asset];

        if (_oldVault != address(0)) {
            uint256 _shareBalance = ISmartVault(_oldVault).totalSupply();
            if (_shareBalance != 0) {
                ISmartVault(_oldVault).withdraw(_shareBalance);
                IERC20Upgradeable(_asset).safeApprove(_oldVault, 0);
            }
        }

        assetVault[_asset] = _vault;

        _depositToVault(_asset);

        emit AssetVaultUpdated(_asset, _vault);
    }
}

