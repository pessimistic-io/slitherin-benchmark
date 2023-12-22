//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

contract AssetReserver is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public asset;
    address public assetTokenManager;

    event WithdrawFromReserver(address sender, address token, uint256 amount);

    constructor(IERC20 _asset, address _assetTokenManger) {
        asset = _asset;
        assetTokenManager = _assetTokenManger;
    }

    modifier onlyAssetTokenManager() {
        require(msg.sender == assetTokenManager, "!assetTokenManager");
        _;
    }

    function withdrawFromReserver(
        address sender,
        uint256 amount
    ) external onlyAssetTokenManager whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(asset.balanceOf(address(this)) >= amount, "Not enough balance");
        asset.safeTransfer(sender, amount);
        emit WithdrawFromReserver(sender, address(this), amount);
    }

    function deposit(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }
}

