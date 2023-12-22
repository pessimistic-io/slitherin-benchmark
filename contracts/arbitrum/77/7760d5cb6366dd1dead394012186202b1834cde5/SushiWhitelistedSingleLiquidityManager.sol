// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;

import { SushiBaseLiquidityManager } from "./SushiBaseLiquidityManager.sol";
import { IBareWhitelistRegistry } from "./IBareWhitelistRegistry.sol";
import { IBareVaultRegistry } from "./IBareVaultRegistry.sol";
import { SushiSinglePositionLiquidityManager } from "./SushiSinglePositionLiquidityManager.sol";

// SinglePositionLiquidityManager with whitelist-gated deposits
contract SushiWhitelistedSingleLiquidityManager is
    SushiSinglePositionLiquidityManager
{
    // Storage

    /// @dev the contract this vault will check for whitelisting permissions
    address public whitelistManager;

    // Public Functions

    /// @dev Initializes vault
    /// @param _vaultManager is the address which will manage the vault being created, pass orchestrator address if the vault is meant to be managed by the orchestrator
    /// @param _steer The steer multisig address, responsible for some governance functions.
    /// @param _params All other parameters this vault will use:
    ///                _params.whitelistManager is the address (usually an EOA)
    ///                 in charge of adding/removing accounts from the whitelist
    ///                _params.setupParams can be found in the MultiLiquidityManager
    function initialize(
        address _vaultManager,
        address, //orchestrator not needed here as, if this vault is to be managed by orchestrator, _vaultManager parameter should be the orchestrator address
        address _steer,
        bytes memory _params
    ) public virtual override(SushiBaseLiquidityManager) {
        // Not initializer because super is initializer
        // Get whitelist data
        (address _whitelistManager, bytes memory setupParams) = abi.decode(
            _params,
            (address, bytes)
        );

        // Set up whitelist
        address _whitelistRegistry = IBareVaultRegistry(msg.sender)
            .whitelistRegistry();
        IBareWhitelistRegistry(_whitelistRegistry).registerWhitelistManager(
            _whitelistManager
        );
        whitelistManager = _whitelistRegistry;

        // Set up vault
        super.initialize(
            _vaultManager,
            address(0), //passing address(0) here as, if this vault is to be managed by orchestrator, _vaultManager parameter should be the orchestrator address
            _steer,
            setupParams
        );
    }

    /// @dev Checks that user is authorized to deposit, then deposits
    ///      check BaseLiquidityManager for more info on the params
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    )
        public
        virtual
        override
        returns (uint256 shares, uint256 amount0Used, uint256 amount1Used)
    {
        // Check that user is authorized to deposit
        require(
            IBareWhitelistRegistry(whitelistManager).permissions(
                address(this),
                to
            ) == 1,
            "whitelist"
        );

        // Deposit
        return
            super.deposit(
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min,
                to
            );
    }
}

