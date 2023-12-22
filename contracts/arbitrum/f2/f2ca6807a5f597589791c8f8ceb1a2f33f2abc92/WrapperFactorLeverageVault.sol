// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// inheritances
import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { FactorGauge } from "./FactorGauge.sol";
import { ERC721DS } from "./ERC721DS.sol";
import { ERC20Augmented } from "./ERC20Augmented.sol";
// libraries
import { SafeERC20 } from "./SafeERC20.sol";
// interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IFactorGaugeController } from "./IFactorGaugeController.sol";
import { IFactorLeverageDescriptor } from "./IFactorLeverageDescriptor.sol";
import { ILeverageStrategy } from "./ILeverageStrategy.sol";
import { ILeverageStrategyView } from "./ILeverageStrategyView.sol";
import { ILeverageStrategyReward } from "./ILeverageStrategyReward.sol";
import { IFactorLeverageVault as ILeverageVault } from "./IFactorLeverageVault.sol";

contract WrapperFactorLeverageVault is
    Initializable,
    ERC721DS,
    OwnableUpgradeable,
    ERC20Augmented,
    FactorGauge,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    mapping(uint256 => address) public stakedNFT;
    mapping(uint256 => uint256) public snapshotBalance;

    address public factorLeverageVaultAddress;
    address public allowedAsset;
    address public allowedDebt;

    error Unauthorized();
    error InvalidAssetOrDebt();
    error BalanceNotZero();
    error NotOwner();
    error NotSupportReward();

    event LeverageAdded(address positionStrategy, uint256 positionId, uint256 amount, uint256 debt);
    event LeverageRemoved(address positionStrategy, uint256 positionId, uint256 debt);
    event LeverageClosed(address positionStrategy, uint256 positionId, uint256 assetBalance, uint256 debtBalance);
    event Stake(uint256 positionId);
    event CreatePosition(uint256 positonId, address vault);
    event UnStake(uint256 positionId);
    event Withdraw(address positionStrategy, uint256 positionId, uint256 amount);
    event Repay(address positionStrategy, uint256 positionId, uint256 amount);
    event Supply(address positionStrategy, uint256 positionId, uint256 amount);

    struct InitParams {
        string _name;
        string _symbol;
        address _allowedAsset;
        address _allowedDebt;
        address _factorLeverageVaultAddress;
        address _veFctr;
        address _gaugeController;
    }

    function initialize(InitParams memory initParams) public initializer {
        __ERC20AUGMENTED_init(initParams._name, initParams._symbol);
        __ERC721_init(initParams._name, initParams._symbol);
        __FactorGauge_init(initParams._veFctr, initParams._gaugeController);
        __Ownable_init(msg.sender);

        allowedAsset = initParams._allowedAsset;
        allowedDebt = initParams._allowedDebt;
        factorLeverageVaultAddress = initParams._factorLeverageVaultAddress;
    }

    function transferFrom(address from, address to, uint256 id) public virtual override nonReentrant {
        ERC721DS.transferFrom(from, to, id);
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(id);
        ERC20Augmented._transfer(from, to, ILeverageStrategy(positionStrategy).debtBalance());
    }

    function stakePosition(uint256 positionId) external nonReentrant {
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        address asset = ILeverageStrategy(positionStrategy).asset();
        address debtToken = ILeverageStrategy(positionStrategy).debtToken();

        if (asset != allowedAsset || debtToken != allowedDebt) revert InvalidAssetOrDebt();
        if (
            !(ILeverageStrategy(positionStrategy).assetBalance() == 0 &&
                ILeverageStrategy(positionStrategy).debtBalance() == 0)
        ) revert BalanceNotZero();

        stakedNFT[positionId] = msg.sender;

        IERC721(factorLeverageVaultAddress).transferFrom(msg.sender, address(this), positionId);
        _mint(msg.sender, positionId);
        emit Stake(positionId);
    }

    function createPosition() external nonReentrant returns (uint256, address) {
        (uint256 position, address strategy) = ILeverageVault(factorLeverageVaultAddress).createPosition(
            allowedAsset,
            allowedDebt
        );
        snapshotBalance[position - 1] = 0;
        _mint(msg.sender, position - 1);
        stakedNFT[position - 1] = msg.sender;

        emit CreatePosition(position - 1, strategy);

        return (position - 1, strategy);
    }

    function unstakePosition(uint256 positionId) external nonReentrant {
        if (ownerOf(positionId) != msg.sender) revert NotOwner();
        if (stakedNFT[positionId] != msg.sender) revert Unauthorized();
        _burn(positionId);
        ERC20Augmented._burnAugmented(msg.sender, snapshotBalance[positionId]);
        stakedNFT[positionId] = address(0);
        snapshotBalance[positionId] = 0;
        IERC721(factorLeverageVaultAddress).transferFrom(address(this), msg.sender, positionId);
        emit UnStake(positionId);
    }

    function addLeverage(uint256 positionId, uint256 amount, uint256 debt, bytes calldata data) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        uint256 oldBalance = snapshotBalance[positionId];
        IERC20(ILeverageStrategy(positionStrategy).asset()).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(ILeverageStrategy(positionStrategy).asset()).approve(positionStrategy, amount);
        ILeverageStrategy(positionStrategy).addLeverage(amount, debt, data);
        uint256 newBalance = ILeverageStrategy(positionStrategy).debtBalance();
        ERC20Augmented._mintAugmented(msg.sender, newBalance - oldBalance);
        snapshotBalance[positionId] = newBalance;
        emit LeverageAdded(positionStrategy, positionId, amount, debt);
    }

    function supply(uint256 positionId, uint256 amount) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        IERC20(ILeverageStrategy(positionStrategy).asset()).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(ILeverageStrategy(positionStrategy).asset()).approve(positionStrategy, amount);
        ILeverageStrategy(positionStrategy).supply(amount);
        emit Supply(positionStrategy, positionId, amount);
    }

    function removeLeverage(uint256 positionId, uint256 amount, bytes calldata data) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        uint256 oldBalance = snapshotBalance[positionId];
        ILeverageStrategy(positionStrategy).removeLeverage(amount, data);
        uint256 newBalance = ILeverageStrategy(positionStrategy).debtBalance();
        ERC20Augmented._burnAugmented(msg.sender, oldBalance - newBalance);
        snapshotBalance[positionId] = newBalance;
        emit LeverageRemoved(positionStrategy, positionId, amount);
    }

    function closeLeverage(uint256 positionId, uint256 amount, bytes calldata data) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        uint256 oldBalance = snapshotBalance[positionId];
        ILeverageStrategy(positionStrategy).closeLeverage(amount, data);
        uint256 newBalance = ILeverageStrategy(positionStrategy).debtBalance();
        ERC20Augmented._burnAugmented(msg.sender, oldBalance - newBalance);
        uint256 closedAsset = ILeverageStrategy(positionStrategy).assetBalance();
        uint256 closedDebt = ILeverageStrategy(positionStrategy).debtBalance();
        snapshotBalance[positionId] = newBalance;
        emit LeverageClosed(positionStrategy, positionId, closedAsset, closedDebt);
    }

    function withdraw(uint256 positionId, uint256 amount) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        ILeverageStrategy(positionStrategy).withdraw(amount);
        IERC20(ILeverageStrategy(positionStrategy).asset()).safeTransfer(msg.sender, amount);
        emit Withdraw(positionStrategy, positionId, amount);
    }

    function repay(uint256 positionId, uint256 amount) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        IERC20(ILeverageStrategy(positionStrategy).debtToken()).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(ILeverageStrategy(positionStrategy).debtToken()).approve(positionStrategy, amount);
        ILeverageStrategy(positionStrategy).repay(amount);
        ERC20Augmented._burnAugmented(msg.sender, amount);
        snapshotBalance[positionId] -= amount;
        emit Repay(positionStrategy, positionId, amount);
    }

    function assetBalance(uint256 positionId) public view returns (uint256) {
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        return ILeverageStrategyView(positionStrategy).assetBalance();
    }

    function debtBalance(uint256 positionId) public view returns (uint256) {
        address positionStrategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);
        return ILeverageStrategyView(positionStrategy).debtBalance();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Augmented, FactorGauge) {
        FactorGauge._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Augmented, FactorGauge) {
        FactorGauge._afterTokenTransfer(from, to, amount);
    }

    function _stakedBalance(address user) internal view override returns (uint256 result) {
        return ERC20Augmented.balanceOfAugmented(user);
    }

    function _totalStaked() internal view override returns (uint256 result) {
        return ERC20Augmented.totalSupplyAugmented();
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return ILeverageVault(factorLeverageVaultAddress).tokenURI(id);
    }

    /**
     * @notice redeems the user's reward
     * @return amount of reward token redeemed, in the same order as `getRewardTokens()`
     */
    function redeemRewards(address user) external nonReentrant returns (uint256[] memory) {
        return _redeemRewards(user);
    }

    /**
     * @notice returns the user's unclaimed reward
     * @return amount of unclaimed Fctr reward
     */
    function pendingRewards(address user) external view returns (uint256) {
        return _pendingRewards(user);
    }

    /// @notice returns the list of reward tokens
    function getRewardTokens() external view returns (address[] memory) {
        return _getRewardTokens();
    }

    function claimRewards(uint256 positionId, address token) external nonReentrant {
        if (stakedNFT[positionId] != msg.sender) revert NotOwner();

        address strategy = ILeverageVault(factorLeverageVaultAddress).positions(positionId);

        try ILeverageStrategyReward(strategy).claimRewards() {
            // If successful, nothing more to do
        } catch {
            // If the call failed, it might be the other type of strategy
            // Now try calling `claimRewards(address token)`
            try ILeverageStrategyReward(strategy).claimRewards(token) {
                // If successful, nothing more to do
            } catch {
                revert NotSupportReward();
            }
        }
    }
}

