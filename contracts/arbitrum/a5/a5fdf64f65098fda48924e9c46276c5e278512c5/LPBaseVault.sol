// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {ERC4626Initializable, IERC20} from "./ERC4626Initializable.sol";
import {OperableInitializable} from "./OperableInitializable.sol";
import {ILPVault} from "./ILPVault.sol";
import {IRouter} from "./IRouter.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";

contract LPBaseVault is ILPVault, ERC4626Initializable, OperableInitializable {
    using FixedPointMathLib for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // Compound Strategy Contract
    ICompoundStrategy public compoundStrategy;

    // Vault Underlying Asset; LP
    IERC20 public underlying;

    // Vault Type: BULL || BEAR || CRAB
    IRouter.OptionStrategy public vaultType;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initializeVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        IRouter.OptionStrategy _vaultType
    ) external initializer {
        if (_asset == address(0)) {
            revert ZeroAddress();
        }
        underlying = IERC20(_asset);
        vaultType = _vaultType;

        __ERC20_init(_name, _symbol);
        __ERC4626_init(underlying);
        __Governable_init(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                            OVERRIDE ERC4626 STANDARD                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev See {IERC4626-deposit}.
     */
    function deposit(uint256 assets, address receiver) public override onlyOperator returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");
        uint256 shares = previewDeposit(assets);
        _mint(receiver, shares);
        return shares;
    }

    /**
     * @notice Mints Vault shares to receiver.
     * @param _shares The amount of shares to mint.
     * @param _receiver The address to receive the minted assets.
     * @return shares minted
     */
    function mint(uint256 _shares, address _receiver)
        public
        override(ERC4626Initializable, ILPVault)
        onlyOperator
        returns (uint256)
    {
        _mint(_receiver, _shares);
        return _shares;
    }

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override onlyOperator returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override
        onlyOperator
        returns (uint256)
    {
        return super.redeem(_shares, _receiver, _owner);
    }

    /**
     * @notice Burn Vault shares of account address.
     * @param _account Shares owner to be burned.
     * @param _shares Amount of shares to be burned.
     */
    function burn(address _account, uint256 _shares) public onlyOperator {
        _burn(_account, _shares);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */

    function totalAssets() public view virtual override(ERC4626Initializable, ILPVault) returns (uint256) {
        return compoundStrategy.vaultAssets(vaultType);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */

    function previewDeposit(uint256 _assets) public view override(ERC4626Initializable, ILPVault) returns (uint256) {
        return super.previewDeposit(_assets);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */

    function previewRedeem(uint256 _shares) public view override(ERC4626Initializable, ILPVault) returns (uint256) {
        return super.previewRedeem(_shares);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Sets the strategy contract for this contract.
     * @param _compoundStrategy The new strategy contract address.
     * @dev This function can only be called by the contract governor. Reverts if `_strategy` address is 0.
     */
    function setStrategies(address _compoundStrategy) external virtual onlyGovernor {
        if (_compoundStrategy == address(0)) {
            revert ZeroAddress();
        }
        compoundStrategy = ICompoundStrategy(_compoundStrategy);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  ERRORS                                    */
    /* -------------------------------------------------------------------------- */

    error ZeroAddress();
}

