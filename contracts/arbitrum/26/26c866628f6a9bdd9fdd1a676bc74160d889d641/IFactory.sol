// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {MiniChefV2Adapter} from "./MiniChefV2Adapter.sol";
import {SushiSwapAdapter} from "./SushiSwapAdapter.sol";
import {UniV2PairAdapter} from "./UniV2PairAdapter.sol";
import {CompoundStrategy} from "./CompoundStrategy.sol";
import {OptionStrategy} from "./OptionStrategy.sol";
import {LPBaseVault} from "./LPBaseVault.sol";

import {IDiamond} from "./IDiamond.sol";
import {ILpsRegistry} from "./ILpsRegistry.sol";

interface IFactory {
    enum Stage {
        NON_CREATED,
        CREATED,
        CONFIGURED,
        OBSOLETE
    }

    struct InitParams {
        address _keeper;
        address _creator;
        address _manager;
        address _registry;
        address _viewer;
        address _zap;
        uint256 _slippage;
        uint256 _maxRisk;
        uint256 _premium;
    }

    struct CreateParams {
        address _underlyingToken;
        string _bullName;
        string _bearName;
        string _crabName;
    }

    // External
    function create(CreateParams memory params) external returns (uint256);
    function setup(uint256 _nonce) external;

    // View
    function registry() external view returns (ILpsRegistry);
    function getMetavault(uint256 _nonce) external view returns (address[] memory);

    // Only Gov
    function changeStage(address underlyingAddress, Stage _stage) external;
    function updateGov(address _gov) external;
    function updateCreator(address _creator) external;
    function updateRegistry(address _registry) external;
    function updateKeeper(address _keeper) external;
    function updateManager(address _manager) external;
    function updateSlippage(uint256 _slippage) external;
    function updateMaxRisk(uint256 _maxRisk) external;
    function updatePremium(uint256 _premium) external;
    function pressToggle() external;
}

