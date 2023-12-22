// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {AddressUpgradeable} from "./AddressUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IERC20, IERC20Metadata, ERC20} from "./ERC20.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {BeefyWrapper} from "./BeefyWrapper.sol";
import {BeefyWrapperFactory} from "./BeefyWrapperFactory.sol";
import {BeefyVaultV7} from "./BeefyVaultV7.sol";
import {IDepository} from "./IDepository.sol";
import {IUXDController} from "./IUXDController.sol";
import {MathLib} from "./MathLib.sol";
import {IBeefyStrategyAdapter} from "./IBeefyStrategyAdapter.sol";
import {BeefyDepositoryStorage} from "./BeefyDepositoryStorage.sol";

/// @title BeefyDepository
/// @notice Manages interactions with Beefy Vault.
contract BeefyDepository is
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IDepository,
    BeefyDepositoryStorage
{
    using MathLib for uint256;
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20;
    using SafeERC20Upgradeable for ERC20;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error NoProfits(int256 pnl);
    error NotApproved(uint256 allowance, uint256 amount);
    error NotController(address caller);
    error NotContractAddress(address addr);
    error UnsupportedAsset(address asset);
    error RedeemableSoftCapHit(uint256 softcap, uint256 totalRedeemable);
    error TokenTransferFail(address token, address from, address to);

    ///////////////////////////////////////////////////////////////////
    ///                         Events
    ///////////////////////////////////////////////////////////////////
    event Deposited(
        address indexed caller,
        uint256 assets,
        uint256 redeemable,
        uint256 shares
    );
    event Withdrawn(
        address indexed caller,
        uint256 assets,
        uint256 redeemable,
        uint256 shares
    );
    event Redeemed(
        address indexed caller,
        uint256 assets,
        uint256 redeemable,
        uint256 shares
    );
    event RedeemableSoftCapUpdated(address indexed caller, uint256 newSoftCap);

    /// @notice Constructor
    /// @param _vault the address of the Beefy vault
    /// @param _wrapperFactory the address of the BeefyWrapperFactory contrat. It is used to instantiate new BeefyWrapper for existing beefy vaults.
    /// @param _controller the address of the UXDController
    function initialize(
        address _vault,
        address _wrapperFactory,
        address _asset,
        address _controller,
        address _adapter
    ) external virtual initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();

        if (!_vault.isContract()) {
            revert NotContractAddress(_vault);
        }
        if (!_wrapperFactory.isContract()) {
            revert NotContractAddress(_wrapperFactory);
        }
        if (!_controller.isContract()) {
            revert NotContractAddress(_controller);
        }
        // Creates a new beefyWrapper for the Desporitory beefy vault
        vaultWrapper = BeefyWrapper(
            BeefyWrapperFactory(_wrapperFactory).clone(_vault)
        );
        controller = IUXDController(_controller);
        assetToken = _asset;
        redeemable = address(controller.redeemable());
        adapter = IBeefyStrategyAdapter(_adapter);
        poolToken = vaultWrapper.asset();
    }

    /// @dev restirct access to controller
    modifier onlyController() {
        if (msg.sender != address(controller)) {
            revert NotController(msg.sender);
        }
        _;
    }

    /// @notice Sets the redeemable soft cap
    /// @dev Can only be called by owner
    /// @param softCap The new redeemable soft cap
    function setRedeemableSoftCap(uint256 softCap) external onlyOwner {
        redeemableSoftCap = softCap;
        emit RedeemableSoftCapUpdated(msg.sender, softCap);
    }

    /// @notice Deposits assets
    /// @param assetAmount The amount of assets to deposit in assetToken.decimals()
    /// @return redeemableAmount the corresponding amount of redeemable for asset deposited
    function deposit(address asset, uint256 assetAmount)
        external
        onlyController
        returns (uint256)
    {
        if (asset != assetToken) {
            revert UnsupportedAsset(asset);
        }
        netAssetDeposits += assetAmount;
        IERC20(assetToken).approve(
            address(adapter),
            assetAmount
        );
        
        // minAmountOut is enforced by the caller (controller)
        uint256 poolTokenAmount = adapter.addLiquidity(asset, assetAmount, 0);
        IERC20(poolToken).approve(address(vaultWrapper), poolTokenAmount);
        uint256 shares = vaultWrapper.deposit(poolTokenAmount, address(this));
        // uint256 shareValue = vaultWrapper.convertToAssets(shares);
        uint256 redeemableAmount = vaultWrapper.convertToAssets(shares);
        redeemableUnderManagement += redeemableAmount;
        _checkSoftCap();
        emit Deposited(msg.sender, assetAmount, redeemableAmount, shares);
        return redeemableAmount;
    }

    /// @notice Redeem a given amount.
    /// @param redeemableAmount The amount to redeem in redeemable.decimals()
    /// @return assetAmount The asset amount withdrawn by this redemption
    function redeem(address asset, uint256 redeemableAmount)
        external
        onlyController
        returns (uint256)
    {
        if (asset != assetToken) {
            revert UnsupportedAsset(asset);
        }
        uint256 assetAmount = _redeemableToAssets(redeemableAmount);
        redeemableUnderManagement -= redeemableAmount;
        netAssetDeposits -= assetAmount;
        uint256 lpTokenAmount = adapter.calculateLpTokenAmountOneCoin(asset, redeemableAmount);
        uint256 shares = vaultWrapper.withdraw(
            lpTokenAmount,
            address(this),
            address(this)
        );

        IERC20(poolToken).approve(address(adapter), shares);
 
        uint256 tokenAmount = adapter.removeLiquidityOneCoin(asset, shares, 0);
        IERC20Upgradeable(asset).safeTransfer(address(controller), tokenAmount);
        emit Withdrawn(msg.sender, tokenAmount, redeemableAmount, shares);
        return tokenAmount;
    }

    /// @dev returns assets deposited. IDepository required.
    function assetsDeposited() external view returns (uint256) {
        return netAssetDeposits;
    }

    /// @dev returns the shares currently owned by this depository
    function getDepositoryShares() external view returns (uint256) {
        return vaultWrapper.balanceOf(address(this));
    }

    /// @dev returns the assets currently owned by this depository.
    function getDepositoryAssets() public view returns (uint256) {
        return
            vaultWrapper.convertToAssets(vaultWrapper.balanceOf(address(this)));
    }

    /// @dev the difference between curent vault assets and amount deposited
    function getUnrealizedPnl() public view returns (int256) {
        return int256(getDepositoryAssets()) - int256(netAssetDeposits);
    }

    function supportedAssets() external view returns (address[] memory) {
        address[] memory assetList = new address[](1);
        assetList[0] = assetToken;
        return assetList;
    }

    /// @dev Withdraw profits. Ensure redeemable is still fully backed by asset balance after this is run.
    /// TODO: Remove this function. Code profit access and use in contracts
    function withdrawProfits(address receiver) external onlyOwner nonReentrant {
        int256 pnl = getUnrealizedPnl();
        if (pnl <= 0) {
            revert NoProfits(pnl);
        }
        uint256 profits = uint256(pnl);
        vaultWrapper.withdraw(profits, receiver, address(this));
        realizedPnl += profits;
    }

    function _assetsToRedeemable(uint256 assetAmount)
        private
        view
        returns (uint256)
    {
        return
            assetAmount.fromDecimalToDecimal(
                IERC20Metadata(assetToken).decimals(),
                IERC20Metadata(redeemable).decimals()
            );
    }

    function _redeemableToAssets(uint256 redeemableAmount)
        private
        view
        returns (uint256)
    {
        return
            redeemableAmount.fromDecimalToDecimal(
                IERC20Metadata(redeemable).decimals(),
                IERC20Metadata(assetToken).decimals()
            );
    }

    function _checkSoftCap() private view {
        if (redeemableUnderManagement > redeemableSoftCap) {
            revert RedeemableSoftCapHit(
                redeemableSoftCap,
                redeemableUnderManagement
            );
        }
    }

    /// @notice Transfers contract ownership to a new address
    /// @dev This can only be called by the current owner.
    /// @param newOwner The address of the new owner.
    function transferOwnership(address newOwner)
        public
        override(IDepository, OwnableUpgradeable)
        onlyOwner
    {
        super.transferOwnership(newOwner);
    }

    ///////////////////////////////////////////////////////////////////////
    ///                         Upgrades
    ///////////////////////////////////////////////////////////////////////

    /// @dev Returns the current version of this contract
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual returns (uint8) {
        return 3;
    }

    /// @dev called on upgrade. only owner can call upgrade function
    function _authorizeUpgrade(address)
        internal
        virtual
        override
        onlyOwner
    // solhint-disable-next-line no-empty-blocks
    {

    }
}

