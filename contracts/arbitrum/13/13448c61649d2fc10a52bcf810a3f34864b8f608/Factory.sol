// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {UpgradeableOperable} from "./UpgradeableOperable.sol";
import {ICreator} from "./ICreator.sol";
import {ILpsRegistry} from "./ILpsRegistry.sol";
import {IRouter} from "./IRouter.sol";
import {ILPVault} from "./ILPVault.sol";
import {IOption} from "./IOption.sol";
import {IFarm} from "./IFarm.sol";
import {IMinimalInit} from "./IMinimalInit.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {ISSOV} from "./ISSOV.sol";
import {IFactory} from "./IFactory.sol";

contract Factory is IFactory, UpgradeableOperable {
    struct InitData {
        ILPVault[] lpVaults;
        address[] vaultAddresses;
        address[] metavaults;
        address lpToken;
        address manager;
        address registry;
        ILpsRegistry registryContract;
    }

    address private gov;
    address private manager;
    address private keeper;

    uint256 public nonce;

    // nonce -> Init Data
    mapping(uint256 => InitData) private initData;
    // underlyingToken -> stage
    mapping(address => uint256) public stage;

    ICreator private creator;
    ILpsRegistry public registry;
    uint256 public slippage;
    uint256 public maxRisk;
    uint256 public premium;
    bool public toggle;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initialize(
        address _creator,
        address _registry,
        address _manager,
        address _keeper,
        uint256 _slippage,
        uint256 _maxRisk,
        uint256 _premium
    ) external initializer {
        
        __Governable_init(msg.sender);

        gov = msg.sender;
        creator = ICreator(_creator);
        registry = ILpsRegistry(_registry);
        manager = _manager;
        keeper = _keeper;
        slippage = _slippage;
        maxRisk = _maxRisk;
        premium = _premium;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function changeStage(address underlyingAddress, uint256 _stage) external onlyGovernor {
        stage[underlyingAddress] = _stage;
    }

    function updateCreator(address _creator) external onlyGovernor {
        creator = ICreator(_creator);
    }

    function updateRegistry(address _registry) external onlyGovernor {
        registry = ILpsRegistry(_registry);
    }

    function updateKeeper(address _keeper) external onlyGovernor {
        keeper = _keeper;
    }

    function updateManager(address _manager) external onlyGovernor {
        manager = _manager;
    }

    function updateSlippage(uint256 _slippage) external onlyGovernor {
        slippage = _slippage;
    }

    function updateMaxRisk(uint256 _maxRisk) external onlyGovernor {
        maxRisk = _maxRisk;
    }

    function updatePremium(uint256 _premium) external onlyGovernor {
        premium = _premium;
    }

    function pressToggle() external onlyGovernor {
        toggle = !toggle;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY OPERATOR                              */
    /* -------------------------------------------------------------------------- */

    function create(CreateParams memory params) external onlyOperator returns (uint256) {
        uint256 _nonce = nonce + 1;
        InitData storage _initData = initData[_nonce];

        _initData.registryContract = registry;
        _initData.registry = address(_initData.registryContract);

        _whitelisted(params._underlyingToken, _initData.registryContract);

        _initData.lpToken = _initData.registryContract.lpToken(params._underlyingToken);

        if (stage[params._underlyingToken] != 0) {
            revert InvalidStage();
        }

        nonce = _nonce;

        address[] memory _implementations = creator.getImplementations();

        address[] memory _metavaults = new address[](12);

        _metavaults[0] = params._underlyingToken;

        ICreator _creator = creator;

        // SWAP
        _metavaults[11] = _clone(_implementations[6]);
        IMinimalInit(_metavaults[11]).initializeSwap(_initData.registry);
        // LP
        _metavaults[10] = _clone(_implementations[5]);
        IMinimalInit(_metavaults[10]).initializeLP(_initData.lpToken, params._underlyingToken, slippage);
        // FARM
        _metavaults[9] = _clone(_implementations[4]);
        IMinimalInit(_metavaults[9]).initializeFarm(
            _initData.registryContract.poolID(params._underlyingToken),
            _initData.lpToken,
            _metavaults[10],
            _initData.registryContract.rewardToken(params._underlyingToken),
            _initData.registry,
            _metavaults[11],
            slippage
        );

        // OPTION ADAPTER
        _metavaults[7] = _creator.createTransparent(_implementations[3]);
        _metavaults[8] = _creator.createTransparent(_implementations[3]);

        // ROUTER
        _metavaults[4] = _creator.createDiamond(address(this));

        // COMPOUND STRATEGY
        _metavaults[5] = _creator.createTransparent(_implementations[1]);

        // OPTION STRATEGY
        _metavaults[6] = _creator.createTransparent(_implementations[2]);

        // VAULTS
        _metavaults[1] = _clone(_implementations[0]);
        IMinimalInit(_metavaults[1]).initializeVault(
            _initData.lpToken, params._bullName, params._bearName, IRouter.OptionStrategy.BULL
        );
        _metavaults[2] = _clone(_implementations[0]);
        IMinimalInit(_metavaults[2]).initializeVault(
            _initData.lpToken, params._bearName, params._bearName, IRouter.OptionStrategy.BEAR
        );
        _metavaults[3] = _clone(_implementations[0]);
        IMinimalInit(_metavaults[3]).initializeVault(
            _initData.lpToken, params._crabName, params._crabName, IRouter.OptionStrategy.CRAB
        );

        _initData.lpVaults.push(ILPVault(_metavaults[1]));
        _initData.lpVaults.push(ILPVault(_metavaults[2]));
        _initData.lpVaults.push(ILPVault(_metavaults[3]));

        _initData.vaultAddresses.push(_metavaults[1]);
        _initData.vaultAddresses.push(_metavaults[2]);
        _initData.vaultAddresses.push(_metavaults[3]);

        stage[params._underlyingToken] = 1;

        _initData.metavaults = _metavaults;

        return _nonce;
    }

    function setup(uint256 _nonce) external {
        InitData memory _initData = initData[_nonce];
        ILpsRegistry _registry = registry;
        _whitelisted(_initData.metavaults[0], _registry);
        _initData.lpToken = _registry.lpToken(_initData.metavaults[0]);

        if (stage[_initData.metavaults[0]] != 1) {
            revert InvalidStage();
        }

        _initData.manager = manager;

        // Farm
        IMinimalInit farm = IMinimalInit(_initData.metavaults[9]);
        farm.addOperator(_initData.metavaults[5]);
        farm.addNewSwapper(_initData.metavaults[11]);
        farm.updateGovernor(gov);

        // Swapper
        IMinimalInit swap = IMinimalInit(_initData.metavaults[11]);
        swap.setSlippage(slippage);
        swap.addOperator(_initData.metavaults[6]);
        swap.addOperator(_initData.metavaults[10]);
        swap.addOperator(_initData.metavaults[9]);
        swap.addOperator(_initData.metavaults[7]);
        swap.addOperator(_initData.metavaults[8]);
        swap.updateGovernor(gov);

        // LP
        IMinimalInit lp = IMinimalInit(_initData.metavaults[10]);
        lp.addOperator(_initData.metavaults[9]);
        lp.addOperator(_initData.metavaults[6]);
        lp.addNewSwapper(_initData.metavaults[11]);
        lp.updateGovernor(gov);

        // Option Call Apdater
        IMinimalInit call_dopex = IMinimalInit(_initData.metavaults[7]);
        call_dopex.initializeOptionAdapter(
            IOption.OPTION_TYPE.CALLS,
            ISSOV(0xFca61E79F38a7a82c62f469f55A9df54CB8dF678),
            slippage,
            IOptionStrategy(_initData.metavaults[6]),
            ICompoundStrategy(_initData.metavaults[5])
        );

        call_dopex.addOperator(_initData.metavaults[6]);
        call_dopex.updateGovernor(gov);

        // Option Put Apdater
        IMinimalInit put_dopex = IMinimalInit(_initData.metavaults[8]);
        put_dopex.initializeOptionAdapter(
            IOption.OPTION_TYPE.PUTS,
            ISSOV(0x32449DF9c617C59f576dfC461D03f261F617aD5a),
            slippage,
            IOptionStrategy(_initData.metavaults[6]),
            ICompoundStrategy(_initData.metavaults[5])
        );

        put_dopex.addOperator(_initData.metavaults[6]);
        put_dopex.updateGovernor(gov);

        // Option Strategy
        IMinimalInit op = IMinimalInit(_initData.metavaults[6]);
        op.initializeOpStrategy(_initData.lpToken, _initData.metavaults[10], _initData.metavaults[11]);
        op.addOperator(_initData.metavaults[5]);
        op.addOperator(_initData.metavaults[7]);
        op.addOperator(_initData.metavaults[8]);
        op.addOperator(_initData.metavaults[4]);
        op.addOperator(_initData.manager);
        op.addProvider(_initData.metavaults[7]);
        op.addProvider(_initData.metavaults[8]);
        op.addKeeper(keeper);
        op.setCompoundStrategy(_initData.metavaults[5]);
        op.setDefaultProviders(_initData.metavaults[7], _initData.metavaults[8]);
        op.updateGovernor(gov);

        // Compound Strategy
        IMinimalInit cmp = IMinimalInit(_initData.metavaults[5]);
        cmp.initializeCmpStrategy(
            IFarm(_initData.metavaults[9]),
            IOptionStrategy(_initData.metavaults[6]),
            IRouter(_initData.metavaults[4]),
            _initData.lpVaults,
            _initData.lpToken,
            maxRisk
        );
        cmp.addOperator(_initData.metavaults[4]);
        cmp.addOperator(_initData.metavaults[6]);
        cmp.addOperator(_initData.manager);
        cmp.addKeeper(keeper);
        cmp.initApproves();
        cmp.updateGovernor(gov);

        // Router
        IMinimalInit router = IMinimalInit(_initData.metavaults[4]);
        router.initializeRouter(_initData.metavaults[5], _initData.metavaults[6], _initData.vaultAddresses, premium);
        router.transferOwnership(gov);

        // Bull Vault
        IMinimalInit bullVault = IMinimalInit(_initData.metavaults[1]);
        bullVault.addOperator(_initData.metavaults[4]);
        bullVault.addOperator(_initData.metavaults[5]);
        bullVault.setStrategies(_initData.metavaults[5]);
        bullVault.updateGovernor(gov);

        // Bear Vault
        IMinimalInit bearVault = IMinimalInit(_initData.metavaults[2]);
        bearVault.addOperator(_initData.metavaults[4]);
        bearVault.addOperator(_initData.metavaults[5]);
        bearVault.setStrategies(_initData.metavaults[5]);
        bearVault.updateGovernor(gov);

        // Crab Vault
        IMinimalInit crabVault = IMinimalInit(_initData.metavaults[3]);
        crabVault.addOperator(_initData.metavaults[4]);
        crabVault.addOperator(_initData.metavaults[5]);
        crabVault.setStrategies(_initData.metavaults[5]);
        crabVault.updateGovernor(gov);

        stage[_initData.metavaults[0]] = 2;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   View                                     */
    /* -------------------------------------------------------------------------- */

    function getMetavault(uint256 _nonce) external view returns (address[] memory) {
        // 0  -> Underlying Token
        // 1  -> Bull Vault
        // 2  -> Bear Vault
        // 3  -> Crab Vault
        // 4  -> Router
        // 5  -> Compound Strategy
        // 6  -> Option Strategy
        // 7  -> Call Adapter
        // 8  -> Put Adapter
        // 9  -> Farm Adapter
        // 10 -> LP Adapter
        // 11 -> Swap Adapter
        return initData[_nonce].metavaults;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  PRIVATE                                   */
    /* -------------------------------------------------------------------------- */

    function _whitelisted(address _token, ILpsRegistry _registry) private view {
        if (!hasRole(OPERATOR, msg.sender) && !toggle) {
            revert CallerNotAllowed();
        }
        if (_registry.poolID(_token) == 0) {
            revert TokenNotWhitelisted();
        }
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function _clone(address implementation) private returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create(0, 0x09, 0x37)
        }
        if (instance == address(0)) {
            revert ERC1167FailedCreateClone();
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error InvalidStage();
    error CallerNotAllowed();
    error TokenNotWhitelisted();
    error ERC1167FailedCreateClone();
}

