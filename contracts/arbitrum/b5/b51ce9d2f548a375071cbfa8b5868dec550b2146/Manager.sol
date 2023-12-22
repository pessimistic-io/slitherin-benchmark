// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {UpgradeableKeepable} from "./UpgradeableKeepable.sol";

import {IRouter} from "./IRouter.sol";
import {IOption} from "./IOption.sol";
import {ISwap} from "./ISwap.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";

contract Manager is UpgradeableKeepable {
    // @notice Use in case no specific swapper is set
    uint256 private defaultSlippage;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initialize(uint256 _defaultSlippage) external initializer {
        if (_defaultSlippage == 0) {
            revert ZeroValue();
        }

        defaultSlippage = _defaultSlippage;

        __Governable_init(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  KEEPER                                    */
    /* -------------------------------------------------------------------------- */

    function batchAutocompound(ICompoundStrategy[] calldata _cmpStrategy) external onlyKeeper {
        uint256 length = _cmpStrategy.length;
        for (uint256 i; i < length;) {
            _cmpStrategy[i].autoCompound();
            unchecked {
                ++i;
            }
        }
    }

    function batchStartEpoch(
        ICompoundStrategy[] calldata _cmpStrategy,
        uint64[] calldata _epochExpiry,
        uint64[] calldata _optionBullRisk,
        uint64[] calldata _optionBearRisk
    ) external onlyKeeper {
        uint256 length = _cmpStrategy.length;
        for (uint256 i; i < length;) {
            _cmpStrategy[i].startEpoch(_epochExpiry[i], _optionBullRisk[i], _optionBearRisk[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchEndEpoch(ICompoundStrategy[] calldata _cmpStrategy) external onlyKeeper {
        uint256 length = _cmpStrategy.length;
        for (uint256 i; i < length;) {
            _cmpStrategy[i].endEpoch();
            unchecked {
                ++i;
            }
        }
    }

    function batchExecuteBullStrategy(
        IOptionStrategy[] calldata _opStrategy,
        uint256[] calldata _epoch,
        uint128[] calldata _toSpend,
        IOptionStrategy.ExecuteStrategy[] calldata _execute
    ) external onlyKeeper {
        uint256 length = _opStrategy.length;
        for (uint256 i; i < length;) {
            _opStrategy[i].executeBullStrategy(_epoch[i], _toSpend[i], _execute[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchStartCrabStrategy(
        IOptionStrategy[] calldata _opStrategy,
        IRouter.OptionStrategy[] calldata _strategyType,
        uint256[] calldata _epoch
    ) external onlyKeeper {
        uint256 length = _opStrategy.length;
        for (uint256 i; i < length;) {
            _opStrategy[i].startCrabStrategy(_strategyType[i], _epoch[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchExecuteBearStrategy(
        IOptionStrategy[] calldata _opStrategy,
        uint256[] calldata _epoch,
        uint128[] calldata _toSpend,
        IOptionStrategy.ExecuteStrategy[] calldata _execute
    ) external onlyKeeper {
        uint256 length = _opStrategy.length;
        for (uint256 i; i < length;) {
            _opStrategy[i].executeBearStrategy(_epoch[i], _toSpend[i], _execute[i]);
            unchecked {
                ++i;
            }
        }
    }

    function batchCollectRewards(
        IOptionStrategy[] calldata _opStrategy,
        IOption.OPTION_TYPE[] calldata _type,
        IOptionStrategy.CollectRewards[] memory _collect
    ) external onlyKeeper {
        uint256 length = _opStrategy.length;
        for (uint256 i; i < length;) {
            _opStrategy[i].collectRewards(_type[i], _collect[i], "");
            unchecked {
                ++i;
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                   ERROR                                    */
    /* -------------------------------------------------------------------------- */

    error ZeroValue();
}

