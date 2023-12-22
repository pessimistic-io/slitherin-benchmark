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
import { IShareLocker, ShareLocker } from "./ShareLocker.sol";
import { IBaseReward } from "./IBaseReward.sol";

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
    address public override supplyRewardPool;
    address public override borrowedRewardPool;

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

    function addLiquidity(uint256 _amountIn) external payable whenNotPaused returns (uint256) {
        require(_amountIn > 0, "AbstractVault: _amountIn cannot be 0");

        _amountIn = _addLiquidity(_amountIn);

        _mint(address(this), _amountIn);
        _approve(address(this), supplyRewardPool, _amountIn);

        IBaseReward(supplyRewardPool).stakeFor(msg.sender, _amountIn);

        emit AddLiquidity(msg.sender, _amountIn, block.timestamp);

        return _amountIn;
    }

    /** @dev this function is defined in a child contract */
    function _addLiquidity(uint256 _amountIn) internal virtual returns (uint256);

    function removeLiquidity(uint256 _amountOut) external {
        require(_amountOut > 0, "AbstractVault: _amountOut cannot be 0");

        uint256 vsTokenBal = balanceOf(msg.sender);

        if (vsTokenBal < _amountOut) {
            IBaseReward(supplyRewardPool).withdrawFor(msg.sender, _amountOut - vsTokenBal);

            require(_amountOut <= balanceOf(msg.sender), "AbstractVault: Insufficient amounts");
        }

        _burn(msg.sender, _amountOut);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _amountOut);

        emit RemoveLiquidity(msg.sender, _amountOut, block.timestamp);
    }

    function borrow(uint256 _borrowedAmount) external override onlyCreditManagersCanBorrow(msg.sender) returns (uint256) {
        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        _mint(shareLocker, _borrowedAmount);
        _approve(shareLocker, borrowedRewardPool, _borrowedAmount);

        IShareLocker(shareLocker).stake(_borrowedAmount);

        emit Borrow(msg.sender, _borrowedAmount);

        return _borrowedAmount;
    }

    function repay(uint256 _borrowedAmount) external override onlyCreditManagersCanRepay(msg.sender) {
        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        IShareLocker(shareLocker).withdraw(_borrowedAmount);

        _burn(shareLocker, _borrowedAmount);

        emit Repay(msg.sender, _borrowedAmount);
    }

    function setSupplyRewardPool(address _rewardPool) external onlyOwner {
        require(_rewardPool != address(0), "AbstractVault: _rewardPool cannot be 0x0");
        require(supplyRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        supplyRewardPool = _rewardPool;

        emit SetSupplyRewardPool(_rewardPool);
    }

    function setBorrowedRewardPool(address _rewardPool) external onlyOwner {
        require(_rewardPool != address(0), "AbstractVault: _rewardPool cannot be 0x0");
        require(borrowedRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        borrowedRewardPool = _rewardPool;

        emit SetBorrowedRewardPool(_rewardPool);
    }

    function creditManagersCount() external view returns (uint256) {
        return creditManagers.length;
    }

    function addCreditManager(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        require(_creditManager.isContract(), "AbstractVault: _creditManager is not a contract");

        require(!creditManagersCanBorrow[_creditManager], "AbstractVault: Not allowed");
        require(!creditManagersCanRepay[_creditManager], "AbstractVault: Not allowed");
        require(creditManagersShareLocker[_creditManager] == address(0), "AbstractVault: Not allowed");

        address shareLocker = address(new ShareLocker(address(this), _creditManager, borrowedRewardPool));

        creditManagersCanBorrow[_creditManager] = true;
        creditManagersCanRepay[_creditManager] = true;
        creditManagersShareLocker[_creditManager] = shareLocker;

        creditManagers.push(_creditManager);

        emit AddCreditManager(_creditManager, shareLocker);
    }

    function forbidCreditManagerToBorrow(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        creditManagersCanBorrow[_creditManager] = false;

        emit ForbidCreditManagerToBorrow(_creditManager);
    }

    function forbidCreditManagersCanRepay(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        creditManagersCanRepay[_creditManager] = false;

        emit ForbidCreditManagersCanRepay(_creditManager);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

