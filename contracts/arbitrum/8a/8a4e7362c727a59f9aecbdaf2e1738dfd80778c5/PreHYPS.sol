// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ERC20 } from "./ERC20.sol";
import { AccessControl } from "./AccessControl.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IPreHYPS } from "./IPreHYPS.sol";
import {     TransferNotAllowed,     SupplyIsFrozen,     SupplyIsNotFrozen,     InsufficientHYPSBalance,     InvalidHYPSAddress,     SwappingIsNotAllowed,     SwappingIsAlreadyEnabled,     TokenSupplyCapExceeded,     InsufficientPreHYPSBalance,     SoftCapExceedsHardCap } from "./Errors.sol";

contract PreHYPS is IPreHYPS, ERC20, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant HARD_CAP = 10_000_000e18;

    /// @dev The token supply soft cap.
    uint256 internal _softCap;

    /// @dev The HYPS token.
    IERC20 internal _hyps;

    /// @dev Frozen supply means all minting/burning is not possible.
    bool internal _supplyFrozen;

    /// @dev Reverts when the supply is frozen.
    modifier whenSupplyIsNotFrozen() {
        if (_supplyFrozen) revert SupplyIsFrozen();
        _;
    }

    /// @dev Reverts when the supply is not frozen.
    modifier whenSupplyIsFrozen() {
        if (!_supplyFrozen) revert SupplyIsNotFrozen();
        _;
    }

    /// @dev Reverts when the caller is not an admin.
    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    /// @dev Reverts when the caller is not a minter.
    modifier onlyMinter() {
        _checkRole(MINTER_ROLE);
        _;
    }

    constructor(uint256 initialSoftCap) ERC20("Preliminary Hypersea Drops", "preHYPS") {
        _setSoftCap(initialSoftCap);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IPreHYPS
    function swap() external {
        if (!swappingEnabled()) revert SwappingIsNotAllowed();

        // Exchange rate: 1 PreHYPS = 1 HYPS.
        uint256 amount = balanceOf(msg.sender);

        // Check: caller has positive PreHYPS balance.
        if (amount == 0) revert InsufficientPreHYPSBalance();

        // Effect: burn caller's PreHYPS balance.
        _burn(msg.sender, amount);

        emit Swapped(msg.sender, amount);

        // Interaction: transfer HYPS token to the caller.
        _hyps.safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc IPreHYPS
    function incrementSoftCapBy(uint256 amount) external onlyAdmin {
        _setSoftCap(_softCap + amount);
    }

    /// @inheritdoc IPreHYPS
    function freezeSupply() external onlyAdmin whenSupplyIsNotFrozen {
        _supplyFrozen = true;
        emit SupplyFrozen(totalSupply());
    }

    /// @inheritdoc IPreHYPS
    function enableSwapping(IERC20 hyps) external onlyAdmin whenSupplyIsFrozen {
        // Check: swapping is not enabled.
        if (swappingEnabled()) revert SwappingIsAlreadyEnabled();

        // Check: HYPS address.
        if (address(hyps) == address(0)) revert InvalidHYPSAddress();

        // Check: HYPS balance is sufficient to cover the distribution.
        if (hyps.balanceOf(address(this)) < totalSupply()) revert InsufficientHYPSBalance();

        // Effect: enable swapping.
        _hyps = hyps;

        emit SwappingEnabled();
    }

    /// @inheritdoc IPreHYPS
    function mintTo(address account, uint256 amount) external onlyMinter whenSupplyIsNotFrozen {
        _mint(account, amount);
    }

    /// @inheritdoc IPreHYPS
    function mintToMany(Mint[] calldata mintList) external onlyMinter whenSupplyIsNotFrozen {
        for (uint256 i = 0; i < mintList.length; i++) {
            _mint(mintList[i].account, mintList[i].amount);
        }
    }

    /// @inheritdoc IPreHYPS
    function burnFrom(address account, uint256 amount) external onlyAdmin whenSupplyIsNotFrozen {
        _burn(account, amount);
    }

    /// @inheritdoc IPreHYPS
    function burnFromMany(Burn[] calldata burnList) external onlyAdmin whenSupplyIsNotFrozen {
        for (uint256 i = 0; i < burnList.length; i++) {
            _burn(burnList[i].account, burnList[i].amount);
        }
    }

    /// @inheritdoc IPreHYPS
    function recoverERC20(address token, uint256 amount, address to) external onlyAdmin {
        if (token == address(_hyps) && IERC20(token).balanceOf(address(this)) - amount < totalSupply()) {
            revert InsufficientHYPSBalance();
        }

        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPreHYPS
    function supplyFrozen() external view returns (bool) {
        return _supplyFrozen;
    }

    /// @inheritdoc IPreHYPS
    function softCap() external view returns (uint256) {
        return _softCap;
    }

    /// @inheritdoc IPreHYPS
    function availableForMinting() external view returns (uint256) {
        return _softCap - totalSupply();
    }

    /// @inheritdoc IPreHYPS
    function swappingEnabled() public view returns (bool) {
        return address(_hyps) != address(0);
    }

    function _setSoftCap(uint256 amount) internal {
        if (amount > HARD_CAP) revert SoftCapExceedsHardCap();
        _softCap = amount;
        emit SoftCapSet(amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        bool isMinting = from == address(0);
        bool isBurning = to == address(0);

        if (!isMinting && !isBurning) revert TransferNotAllowed();
        if (isMinting && totalSupply() + amount > _softCap) revert TokenSupplyCapExceeded();
    }
}

