// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {IRouter} from "./IRouter.sol";
import {ILPVault} from "./ILPVault.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {LibDiamond} from "./LibDiamond.sol";

error ReentrantCall();
error PauseError();

library RouterLib {
    /**
     * @notice Router storage position.
     */
    bytes32 constant ROUTER_STORAGE_POSITION = keccak256("diamond.standard.router.storage");

    /**
     * @notice Reentrancy constant.
     */
    uint256 constant _NOT_ENTERED = 1;
    /**
     * @notice Reentrancy constant.
     */
    uint256 constant _ENTERED = 2;

    /**
     * @notice Router storage.
     */
    struct RouterStorage {
        IERC20 lpToken;
        uint256 basis;
        uint256 premium;
        uint256 slippage;
        bool initialized;
        uint256 status;
        bool paused;
        mapping(IRouter.OptionStrategy => ILPVault) vaults;
        ICompoundStrategy compoundStrategy;
        IOptionStrategy optionStrategy;
    }

    /**
     * @notice Get router storage.
     */
    function routerStorage() internal pure returns (RouterStorage storage rs) {
        bytes32 position = ROUTER_STORAGE_POSITION;
        assembly {
            rs.slot := position
        }
    }

    /**
     * @notice To avoid reentrancy.
     */
    function nonReentrantBefore() internal {
        RouterStorage storage rs = routerStorage();
        // On the first call to nonReentrant, _status will be 1 _NOT_ENTERED
        if (rs.status == _ENTERED) {
            revert ReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        rs.status = _ENTERED;
    }

    /**
     * @notice To avoid reentrancy.
     */
    function nonReentrantAfter() internal {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        RouterStorage storage rs = routerStorage();
        rs.status = _NOT_ENTERED;
    }

    event PauseChanged(address _caller, bool _paused);

    /**
     * @notice Switch between paused and unpaused.
     */
    function togglePause() internal {
        LibDiamond.enforceIsContractOwner();
        RouterStorage storage rs = routerStorage();
        rs.paused = !rs.paused;
        emit PauseChanged(msg.sender, rs.paused);
    }

    /**
     * @notice If it is paused revert.
     */
    function requireNotPaused() internal view {
        if (routerStorage().paused) {
            revert PauseError();
        }
    }

    /**
     * @notice Get LP Token.
     */
    function lpToken() internal view returns (IERC20) {
        return routerStorage().lpToken;
    }

    /**
     * @notice Get basis point.
     */
    function basis() internal view returns (uint256) {
        return routerStorage().basis;
    }

    /**
     * @notice Get premium.
     */
    function premium() internal view returns (uint256) {
        return routerStorage().premium;
    }

    /**
     * @notice Get slippage.
     */
    function slippage() internal view returns (uint256) {
        return routerStorage().slippage;
    }

    /**
     * @notice Get initialized.
     */
    function initialized() internal view returns (bool) {
        return routerStorage().initialized;
    }

    /**
     * @notice Get strategy vault.
     */
    function vaults(IRouter.OptionStrategy _strategy) internal view returns (ILPVault) {
        return routerStorage().vaults[_strategy];
    }

    /**
     * @notice Get compound strategy.
     */
    function compoundStrategy() internal view returns (ICompoundStrategy) {
        return routerStorage().compoundStrategy;
    }

    /**
     * @notice Get option strategy.
     */
    function optionStrategy() internal view returns (IOptionStrategy) {
        return routerStorage().optionStrategy;
    }
}

