// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import {AccessControl} from "./AccessControl.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategy} from "./IStrategy.sol";
import {IVault} from "./IVault.sol";

abstract contract JonesStrategyV3Base is IStrategy, AccessControl {
    using SafeERC20 for IERC20;

    address internal _vault;
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");
    address public immutable asset;
    bytes32 public immutable name;
    uint256 public totalDeposited;
    bool public isVaultSet;

    /**
     * @dev Sets the values for {name} and {asset}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        bytes32 _name,
        address _asset,
        address _governor
    ) {
        if (_asset == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        if (_governor == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        name = _name;
        asset = _asset;

        _grantRole(GOVERNOR, _governor);
        _grantRole(KEEPER, _governor);
    }

    // ============================= View functions ================================

    /**
     * @inheritdoc IStrategy
     */
    function getVault() public view virtual returns (address) {
        if (!isVaultSet) {
            revert VAULT_NOT_ATTACHED();
        }
        return address(_vault);
    }

    /**
     * @inheritdoc IStrategy
     */
    function getUnused() public view virtual override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    // ============================= Mutative functions ================================

    function grantKeeperRole(address _to) public onlyRole(GOVERNOR) {
        if (_to == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }
        _grantRole(KEEPER, _to);
    }

    function revokeKeeperRole(address _from) public onlyRole(GOVERNOR) {
        _revokeRole(KEEPER, _from);
    }

    /**
     * @inheritdoc IStrategy
     */
    function setVault(address _newVault) public virtual onlyRole(GOVERNOR) {
        if (isVaultSet) {
            revert VAULT_ALREADY_ATTACHED();
        }

        if (_newVault == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        _vault = _newVault;
        IERC20(asset).safeApprove(_vault, type(uint256).max);
        isVaultSet = true;
        emit VaultSet(_msgSender(), _vault);
    }

    /**
     * @inheritdoc IStrategy
     */
    function detach() public virtual override onlyRole(GOVERNOR) {
        if (!isVaultSet) {
            revert VAULT_NOT_ATTACHED();
        }
        _repay();
        if (getUnused() > 0) {
            revert STRATEGY_STILL_HAS_ASSET_BALANCE();
        }
        address prevVault = _vault;
        IERC20(asset).safeApprove(_vault, 0);
        _vault = address(0);
        isVaultSet = false;
        emit VaultDetached(msg.sender, prevVault);
    }

    /**
     * @inheritdoc IStrategy
     */
    function borrow(uint256 _amount) public virtual override onlyRole(KEEPER) {
        if (!isVaultSet) {
            revert VAULT_NOT_ATTACHED();
        }
        if (_amount == 0) {
            revert BORROW_AMOUNT_ZERO();
        }
        IVault(_vault).pull(_amount);
        totalDeposited += _amount;
        emit Borrow(_msgSender(), _amount, _vault, asset);
    }

    /**
     * @inheritdoc IStrategy
     */
    function repay() public virtual override onlyRole(KEEPER) {
        _repay();
    }

    function _repay() internal {
        if (!isVaultSet) {
            revert VAULT_NOT_ATTACHED();
        }
        uint256 unused = getUnused();
        if (unused > 0) {
            IVault(_vault).depositStrategyFunds(unused);
        }
        if (totalDeposited >= unused) {
            totalDeposited -= unused;
        } else {
            totalDeposited = 0;
        }
        emit Repay(_msgSender(), unused, _vault, asset);
    }
}

