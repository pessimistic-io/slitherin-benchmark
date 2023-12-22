// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import {AccessControl} from "./AccessControl.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategy} from "./IStrategy.sol";
import {IVault} from "./IVault.sol";
import {IwETH} from "./IwETH.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";

abstract contract JonesStrategyV3Base is IStrategy, AccessControl {
    using SafeERC20 for IERC20;

    address internal _vault;
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");
    address public constant wETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    IUniswapV2Router02 public constant sushiRouter =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address public immutable asset;
    bytes32 public immutable name;
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
        emit Borrow(_msgSender(), _amount, _vault, asset);
    }

    /**
     * @inheritdoc IStrategy
     */
    function repay() public virtual override onlyRole(KEEPER) {
        _repay();
    }

    /**
     * @inheritdoc IStrategy
     */
    function repayFunds(uint256 _amount)
        public
        virtual
        override
        onlyRole(KEEPER)
    {
        _repayFunds(_amount);
    }

    function _repay() internal virtual {
        _repayFunds(getUnused());
    }

    function _repayFunds(uint256 _amount) internal virtual {
        if (!isVaultSet) {
            revert VAULT_NOT_ATTACHED();
        }
        if (_amount == 0 || _amount > getUnused()) {
            revert INVALID_AMOUNT();
        }
        IVault(_vault).depositStrategyFunds(_amount);
        emit Repay(_msgSender(), _amount, _vault, asset);
    }

    function migrateFunds(
        address _to,
        address[] memory _tokens,
        bool _shouldTransferEth,
        bool
    ) public virtual override onlyRole(GOVERNOR) {
        _transferTokens(_to, _tokens, _shouldTransferEth);
        emit FundsMigrated(_to);
    }

    function _transferTokens(
        address _to,
        address[] memory _tokens,
        bool _shouldTransferEth
    ) internal virtual {
        // transfer tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            uint256 assetBalance = token.balanceOf(address(this));
            if (assetBalance > 0) {
                token.safeTransfer(_to, assetBalance);
            }
        }

        // migrate ETH balance
        uint256 balanceGwei = address(this).balance;
        if (balanceGwei > 0 && _shouldTransferEth) {
            payable(_to).transfer(balanceGwei);
        }
    }
}

