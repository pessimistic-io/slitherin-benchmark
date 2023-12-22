// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { Multicall } from "./Multicall.sol";
import { IAbstractVault } from "./IAbstractVault.sol";
import { IVerificationRuler } from "./IVerificationRuler.sol";
import { IStorageAddresses } from "./IStorageAddresses.sol";
import { IShareLocker, ShareLocker } from "./ShareLocker.sol";
import { IBaseReward } from "./IBaseReward.sol";
import { IRewardTracker } from "./IRewardTracker.sol";

/* 
The AbstractVault is a liquidity deposit contract that inherits from the ERC20 contract. 
When users deposit liquidity, it generates vsToken 1:1 and pledges it to the supplyRewardPool to obtain rewards. 
When a CredityManager borrows, it also generates vsToken and pledges it to the borrowedRewardPool to obtain rewards. 
The vsToken pledged in the supplyRewardPool belongs to the user, while the vsToken pledged in the borrowedRewardPool belongs to the ShareLocker contract. 
After repayment, ShareLocker will automatically withdraw and burn them.
*/

abstract contract AbstractVault is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    Multicall,
    IAbstractVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address public override underlyingToken;
    address public override rewardPools;
    address public override verificationRuler;

    IRewardTracker public rewardTracker;

    address[] public creditManagers;

    mapping(address => address) public override creditManagersShareLocker;
    mapping(address => bool) public override creditManagersCanBorrow;
    mapping(address => bool) public override creditManagersCanRepay;

    modifier onlyCreditManagersCanBorrow(address _sender) {
        require(creditManagersCanBorrow[_sender], "AbstractVault: Caller is not the vault manager");

        _;
    }

    modifier onlyCreditManagersCanRepay(address _sender) {
        require(creditManagersCanRepay[_sender], "AbstractVault: Caller is not the vault manager");

        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _underlyingToken) external initializer {
        require(_underlyingToken != address(0), "AbstractVault: _underlyingToken cannot be 0x0");
        require(_underlyingToken.isContract(), "AbstractVault: _underlyingToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        __ERC20_init(
            string(abi.encodePacked(ERC20Upgradeable(_underlyingToken).name(), " vault shares")),
            string(abi.encodePacked("vs", ERC20Upgradeable(_underlyingToken).symbol()))
        );

        underlyingToken = _underlyingToken;
    }

    /// @notice used to initialize the contract
    function initializeV2(address _rewardPools) external reinitializer(2) {
        require(_rewardPools != address(0), "AbstractVault: _rewardPools cannot be 0x0");
        require(_rewardPools.isContract(), "AbstractVault: _rewardPools is not a contract");

        rewardPools = _rewardPools;
        verificationRuler = address(0);
    }

    /// @notice add liquidity
    /// @param _amountIn amount of underling token
    /// @return amount of liquidity
    function addLiquidity(uint256 _amountIn) external payable whenNotPaused returns (uint256) {
        require(_amountIn > 0, "AbstractVault: _amountIn cannot be 0");

        rewardTracker.execute();

        _amountIn = _addLiquidity(_amountIn);

        _mint(address(this), _amountIn);

        address rewardPool = supplyRewardPool();

        _approve(address(this), rewardPool, _amountIn);
        IBaseReward(rewardPool).stakeFor(msg.sender, _amountIn);

        emit AddLiquidity(msg.sender, _amountIn, block.timestamp);

        return _amountIn;
    }

    /** @dev this function is defined in a child contract */
    function _addLiquidity(uint256 _amountIn) internal virtual returns (uint256);

    /// @notice remove liquidity
    /// @param _amountOut amount of liquidity
    function removeLiquidity(uint256 _amountOut) external {
        require(_amountOut > 0, "AbstractVault: _amountOut cannot be 0");

        rewardTracker.execute();

        uint256 vsTokenBal = balanceOf(msg.sender);

        if (_amountOut > vsTokenBal) {
            address rewardPool = supplyRewardPool();

            IBaseReward(rewardPool).withdrawFor(msg.sender, _amountOut - vsTokenBal);
        }

        _burn(msg.sender, _amountOut);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _amountOut);

        emit RemoveLiquidity(msg.sender, _amountOut, block.timestamp);
    }

    /// @notice borrowed from vault
    /// @param _borrowedAmount amount been borrowed
    /// @return borrowed amount
    function borrow(uint256 _borrowedAmount) external override whenNotPaused onlyCreditManagersCanBorrow(msg.sender) returns (uint256) {
        if (verificationRuler != address(0)) {
            require(IVerificationRuler(verificationRuler).canBorrow(address(this), _borrowedAmount), "AbstractVault: Not allowed");
        }

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        address rewardPool = borrowedRewardPool(msg.sender);
        address shareLocker = creditManagersShareLocker[msg.sender];

        _mint(shareLocker, _borrowedAmount);
        _approve(shareLocker, rewardPool, _borrowedAmount);

        IShareLocker(shareLocker).stake(_borrowedAmount);

        emit Borrow(msg.sender, _borrowedAmount);

        return _borrowedAmount;
    }

    /// @notice repay vault
    /// @param _borrowedAmount repaid amount
    /// @param _repayAmountDuringLiquidation the actual amount that can be repaid when the user undergoes liquidation
    function repay(uint256 _borrowedAmount, uint256 _repayAmountDuringLiquidation, bool _liquidating) external override onlyCreditManagersCanRepay(msg.sender) {
        if (_liquidating) {
            if (_repayAmountDuringLiquidation > 0) {
                IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _repayAmountDuringLiquidation);
            }
        } else {
            IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);
        }

        address shareLocker = creditManagersShareLocker[msg.sender];

        IShareLocker(shareLocker).withdraw(_borrowedAmount);

        _burn(shareLocker, _borrowedAmount);

        emit Repay(msg.sender, _borrowedAmount, _repayAmountDuringLiquidation, _liquidating);
    }

    /// @notice set reward tracker
    /// @param _tracker tracker address
    function setRewardTracker(address _tracker) external onlyOwner {
        require(_tracker != address(0), "AbstractVault: _tracker cannot be 0x0");
        require(address(rewardTracker) == address(0), "AbstractVault: Cannot run this function twice");

        rewardTracker = IRewardTracker(_tracker);

        emit SetRewardTracker(_tracker);
    }

    /// @notice set up verification rule contracts, focusing on pool health
    /// @param _ruler if set to a null address, it is equivalent to turning off
    function setVerificationRuler(address _ruler) external onlyOwner {
        verificationRuler = _ruler;

        emit SetVerificationRuler(_ruler);
    }

    /// @notice return number of managers
    /// @return amount
    function creditManagersCount() external view returns (uint256) {
        return creditManagers.length;
    }

    /// @notice add credit manager
    function addCreditManager(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        require(_creditManager.isContract(), "AbstractVault: _creditManager is not a contract");

        require(!creditManagersCanBorrow[_creditManager], "AbstractVault: Not allowed");
        require(!creditManagersCanRepay[_creditManager], "AbstractVault: Not allowed");
        require(creditManagersShareLocker[_creditManager] == address(0), "AbstractVault: Not allowed");

        address rewardPool = borrowedRewardPool(msg.sender);
        require(rewardPool != address(0), "AbstractVault: borrowedRewardPool cannot be 0x0");

        address shareLocker = address(new ShareLocker(address(this), _creditManager, rewardPool));

        creditManagersCanBorrow[_creditManager] = true;
        creditManagersCanRepay[_creditManager] = true;
        creditManagersShareLocker[_creditManager] = shareLocker;

        creditManagers.push(_creditManager);

        emit AddCreditManager(_creditManager, shareLocker);
    }

    /// @notice toggle credit manager to borrow
    /// @param _creditManager credit manager address
    function toggleCreditManagerToBorrow(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        require(creditManagersShareLocker[_creditManager] != address(0), "AbstractVault: _creditManager has not been added yet");

        bool oldState = creditManagersCanBorrow[_creditManager];

        creditManagersCanBorrow[_creditManager] = !oldState;

        emit ToggleCreditManagerToBorrow(_creditManager, oldState);
    }

    /// @notice toggle credit manager to repay
    /// @param _creditManager credit manager address
    function toggleCreditManagersCanRepay(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        require(creditManagersShareLocker[_creditManager] != address(0), "AbstractVault: _creditManager has not been added yet");

        bool oldState = creditManagersCanRepay[_creditManager];

        creditManagersCanRepay[_creditManager] = !oldState;

        emit ToggleCreditManagersCanRepay(_creditManager, oldState);
    }

    /// @notice pause vault to add liquidity
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice unpause vault to add liquidity
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("AbstractVault: Not allowed");
    }

    ///@notice get supply reward pool
    function supplyRewardPool() public view override returns (address) {
        return IStorageAddresses(rewardPools).getAddress(address(this));
    }

    ///@notice get borrowed reward pool
    function borrowedRewardPool() public view override returns (address) {
        return IStorageAddresses(rewardPools).getAddress(msg.sender);
    }

    ///@notice get borrowed reward pool
    function borrowedRewardPool(address _creditManager) public view override returns (address) {
        return IStorageAddresses(rewardPools).getAddress(_creditManager);
    }
}

