// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IComptroller.sol";
import "./IVault.sol";
import "./IFundDeployer.sol";
import {IExternalPositionProxy} from "./IExternalPositionProxy.sol";

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import {UUPSProxiable} from "./UUPSProxiable.sol";

/**
 * @title BaseStorage Base Contract for containing all storage variables
 */
abstract contract BaseStorage is
    Initializable,
    UUPSProxiable,
    ReentrancyGuardUpgradeable
{
    /**
     * @dev struct for callOnExtension methods
     */
    struct ExtensionArgs {
        address _extension;
        uint256 _actionId;
        bytes _callArgs;
    }

    /**
     * @notice address of denomination Asset
     * @dev is set at initializer
     */
    address internal denominationAsset;

    /**
     * @notice address of enzyme fund deployer contract
     * @dev is set at initializer
     */
    address public FUND_DEPLOYER;

    /**
     * @notice address of vault
     */
    address public vaultProxy;

    /**
     * @notice address of the alfred factory
     * @dev is set at initializer
     */
    address internal ALFRED_FACTORY;

    /**
     * @notice share action time lock
     * @dev is set at initializer
     */
    uint256 public shareActionTimeLock;

    /**
     * @notice share action block number difference
     * @dev is set at initializer
     */
    uint256 public shareActionBlockNumberLock;

    /**
    A blockNumber after the last time shares were bought for an account
        that must expire before that account transfers or redeems their shares
    */
    mapping(address => uint256) internal acctToLastSharesBought;

    /**
     * @notice Emits after fund investment
     *  @dev emits after successful asset deposition, shares miniting and creation of LP position
     *  @custom:emittedby addFund function
     *  @param _user the end user interacting with Alfred wrapper
     *  @param _investmentAmount the amount of USDC being deposited
     *  @param _sharesReceived The actual amount of shares received
     */
    event FundsAdded(
        address _user,
        uint256 _investmentAmount,
        uint256 _sharesReceived
    );

    /**
     * @notice Emits at vault creation
     * @custom:emitted by createNewFund function
     * @param _user the end user interacting with Alfred wrapper
     * @param _comptrollerProxy The address of the comptroller deployed for this user
     * @param _vaultProxy The address of the vault deployed for this user
     */
    event VaultCreated(
        address _user,
        address _fundOwner,
        address _comptrollerProxy,
        address _vaultProxy
    );
}

