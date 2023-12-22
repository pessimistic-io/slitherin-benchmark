//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISSOV} from "./ISSOV.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {IOption} from "./IOption.sol";
import {IFarm} from "./IFarm.sol";
import {IRouter} from "./IRouter.sol";
import {ILPVault} from "./ILPVault.sol";

interface IMinimalInit {
    // ACESSS
    function addOperator(address _newOperator) external;
    function addKeeper(address _keeper) external;
    function updateGovernor(address _newGovernor) external;
    function transferOwnership(address _newOwner) external;

    // UTILS
    function addProvider(address _provider) external;
    function setDefaultProviders(address _callProvider, address _putProvider) external;
    function addNewSwapper(address _swapper) external;
    function setSlippage(uint256 _slippage) external;
    function setStrategies(address _strategy) external;
    function setCompoundStrategy(address _strategy) external;

    // INITS
    function initializeSwap(address _lpsRegistry) external;
    function initializeLP(address _lp, address _otherToken, uint256 _slippage) external;
    function initializeFarm(
        uint256 _pid,
        address _lp,
        address _lpAdapter,
        address _rewardToken,
        address _lpsRegistry,
        address _defaultSwapper,
        uint256 _defaultSlippage
    ) external;
    function initializeOptionAdapter(
        IOption.OPTION_TYPE _type,
        ISSOV _ssov,
        uint256 _slippage,
        IOptionStrategy _optionStrategy,
        ICompoundStrategy _compoundStrategy
    ) external;
    function initializeOpStrategy(address _lp, address _pairAdapter, address _swapper) external;
    function initializeRouter(
        address _compoundStrategy,
        address _optionStrategy,
        address[] calldata _strategyVaults,
        uint256 _premium
    ) external;
    function initializeCmpStrategy(
        IFarm _farm,
        IOptionStrategy _option,
        IRouter _router,
        ILPVault[] memory _vaults,
        address _lpToken,
        uint256 _maxRisk
    ) external;
    function initializeVault(
        address _asset,
        string memory _name,
        string memory _symbol,
        IRouter.OptionStrategy _vaultType
    ) external;
}

