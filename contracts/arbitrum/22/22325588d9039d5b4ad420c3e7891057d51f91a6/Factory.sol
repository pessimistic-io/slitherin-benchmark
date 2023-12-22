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
import {IViewer} from "./IViewer.sol";
import {ISSOV} from "./ISSOV.sol";
import {IFactory} from "./IFactory.sol";
import {IZapUniV2} from "./ZapUniV2.sol";

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

    address public gov;
    address public manager;
    address public keeper;
    address public incentiveReceiver;

    ICreator public creator;
    ILpsRegistry public registry;
    IViewer public viewer;
    IZapUniV2 public zap;

    uint256 public slippage;
    uint256 public maxRisk;
    uint256 public premium;
    uint256 public retentionIncentive;

    uint256 public nonce;
    // nonce -> Init Data
    mapping(uint256 => InitData) public initData;
    // underlyingToken -> Stage
    mapping(address => Stage) public stage;

    bool public toggle;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initialize Factory contract.
     * @param init Parameters needed to initialize factory.
     */
    function initialize(InitParams memory init) external initializer {
        __Governable_init(msg.sender);

        gov = msg.sender;

        creator = ICreator(init._creator);
        registry = ILpsRegistry(init._registry);
        viewer = IViewer(init._viewer);
        zap = IZapUniV2(init._zap);

        manager = init._manager;
        keeper = init._keeper;
        incentiveReceiver = init._incentiveReceiver;
        retentionIncentive = init._retentionIncentive;
        slippage = init._slippage;
        maxRisk = init._maxRisk;
        premium = init._premium;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Change metavault stage.
     * @param _underlyingAddress metavault underlying token address.
     * @param _stage metavault stage.
     */
    function changeStage(address _underlyingAddress, Stage _stage) external onlyGovernor {
        emit UpdateStage(_underlyingAddress, stage[_underlyingAddress], _stage);
        stage[_underlyingAddress] = _stage;
    }

    /**
     * @notice Update metavault governor.
     * @param _gov new metavault governor address.
     */
    function updateGov(address _gov) external onlyGovernor {
        gov = _gov;
    }

    /**
     * @notice Update Zap contract.
     * @param _zap zap contract address.
     */
    function updateZap(address _zap) external onlyGovernor {
        zap = IZapUniV2(_zap);
    }

    /**
     * @notice Update Creator contract.
     * @param _creator creator contract address.
     */
    function updateCreator(address _creator) external onlyGovernor {
        creator = ICreator(_creator);
    }

    /**
     * @notice Update Registry contract.
     * @param _registry registry contract address.
     */
    function updateRegistry(address _registry) external onlyGovernor {
        registry = ILpsRegistry(_registry);
    }

    /**
     * @notice Update keeper.
     * @param _keeper keeper address.
     */
    function updateKeeper(address _keeper) external onlyGovernor {
        keeper = _keeper;
    }

    /**
     * @notice Update Mabager contract.
     * @param _manager manager contract address.
     */
    function updateManager(address _manager) external onlyGovernor {
        manager = _manager;
    }

    /**
     * @notice Update Incentive Receiver.
     * @param _incentiveReceiver incentiveReceiver address.
     */
    function updateIncentiveReceiver(address _incentiveReceiver) external onlyGovernor {
        incentiveReceiver = _incentiveReceiver;
    }

    /**
     * @notice Update system slippage.
     * @param _slippage system slippage.
     */
    function updateSlippage(uint256 _slippage) external onlyGovernor {
        slippage = _slippage;
    }

    /**
     * @notice Update option max risk.
     * @param _maxRisk option max risk.
     */
    function updateMaxRisk(uint256 _maxRisk) external onlyGovernor {
        maxRisk = _maxRisk;
    }

    /**
     * @notice Update premium.
     * @param _premium option premium.
     */
    function updatePremium(uint256 _premium) external onlyGovernor {
        premium = _premium;
    }

    /**
     * @notice Update Retention Incentive.
     * @param _retentionIncentive retentionIncentive amount.
     */
    function updateRetentionIncentive(uint256 _retentionIncentive) external onlyGovernor {
        retentionIncentive = _retentionIncentive;
    }

    /**
     * @notice Toggle between only operator or free access to whitelist functions.
     */
    function pressToggle() external onlyGovernor {
        toggle = !toggle;
        emit Toggle(toggle);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY WHITELISTED                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Create new metavault.
     * @param params metavault create parameters.
     */
    function create(CreateParams memory params) external returns (uint256) {
        uint256 _nonce = nonce + 1;
        InitData storage _initData = initData[_nonce];

        _initData.registryContract = registry;
        _initData.registry = address(_initData.registryContract);

        _whitelisted(params._underlyingToken, _initData.registryContract);

        _initData.lpToken = _initData.registryContract.lpToken(params._underlyingToken);

        if (stage[params._underlyingToken] == Stage.CREATED || stage[params._underlyingToken] == Stage.CONFIGURED) {
            revert InvalidStage();
        }

        nonce = _nonce;

        address[] memory _implementations = creator.getImplementations();

        address[] memory _beacons = creator.getBeacons();

        address[] memory _metavaults = new address[](12);

        _metavaults[0] = params._underlyingToken;

        ICreator _creator = creator;

        // SWAP
        _metavaults[11] = _clone(_implementations[3]);
        IMinimalInit(_metavaults[11]).initializeSwap(_initData.registry);
        // LP
        _metavaults[10] = _clone(_implementations[2]);
        IMinimalInit(_metavaults[10]).initializeLP(_initData.lpToken, params._underlyingToken, slippage);
        // FARM
        _metavaults[9] = _clone(_implementations[1]);
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
        _metavaults[7] = _implementations[4];
        _metavaults[8] = _implementations[5];

        // ROUTER
        _metavaults[4] = _creator.createDiamond(address(this));

        // COMPOUND STRATEGY
        _metavaults[5] = _creator.createBeacon(_beacons[0]);

        // OPTION STRATEGY
        _metavaults[6] = _creator.createBeacon(_beacons[1]);

        // VAULTS
        _metavaults[1] = _clone(_implementations[0]);
        IMinimalInit(_metavaults[1]).initializeVault(
            _initData.lpToken, params._bullName, params._bullName, IRouter.OptionStrategy.BULL
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

        // Set Viewer Addresses
        viewer.setAddresses(
            _initData.lpToken,
            IViewer.Addresses({
                compoundStrategy: ICompoundStrategy(_metavaults[5]),
                optionStrategy: IOptionStrategy(_metavaults[6]),
                router: IRouter(_metavaults[4])
            })
        );

        // LP token, router, swapper and pairAdapter
        zap.setMetavault(_initData.lpToken, _metavaults[4], _metavaults[11], _metavaults[10]);

        stage[params._underlyingToken] = Stage.CREATED;

        _initData.metavaults = _metavaults;

        emit Create(_nonce, params._underlyingToken, Stage.CREATED, _initData.metavaults);

        return _nonce;
    }

    /**
     * @notice Setup new metavault.
     * @param _nonce metavault nonce.
     */
    function setup(uint256 _nonce) external {
        InitData memory _initData = initData[_nonce];
        ILpsRegistry _registry = registry;
        _whitelisted(_initData.metavaults[0], _registry);
        _initData.lpToken = _registry.lpToken(_initData.metavaults[0]);

        if (stage[_initData.metavaults[0]] != Stage.CREATED) {
            revert InvalidStage();
        }

        _initData.manager = manager;

        // Farm
        {
            IMinimalInit farm = IMinimalInit(_initData.metavaults[9]);
            farm.addOperator(_initData.metavaults[5]);
            farm.addOperator(address(zap));
            farm.addNewSwapper(_initData.metavaults[11]);
            farm.updateGovernor(gov);
        }

        // Swapper
        {
            IMinimalInit swap = IMinimalInit(_initData.metavaults[11]);
            swap.setSlippage(slippage);
            swap.addOperator(_initData.metavaults[6]);
            swap.addOperator(address(zap));
            swap.addOperator(_initData.metavaults[10]);
            swap.addOperator(_initData.metavaults[9]);
            swap.addOperator(_initData.metavaults[7]);
            swap.addOperator(_initData.metavaults[8]);
            swap.updateGovernor(gov);
        }

        // LP
        {
            IMinimalInit lp = IMinimalInit(_initData.metavaults[10]);
            lp.addOperator(_initData.metavaults[9]);
            lp.addOperator(_initData.metavaults[6]);
            lp.addNewSwapper(_initData.metavaults[11]);
            lp.addOperator(address(zap));
            lp.updateGovernor(gov);
        }

        // Option Call Apdater
        {
            IMinimalInit call_dopex = IMinimalInit(_initData.metavaults[7]);
            call_dopex.addOperator(_initData.metavaults[6]);
        }

        // Option Put Apdater
        {
            IMinimalInit put_dopex = IMinimalInit(_initData.metavaults[8]);
            put_dopex.addOperator(_initData.metavaults[6]);
        }

        // Option Strategy
        {
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
        }

        // Compound Strategy
        {
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
            cmp.setUpIncentives(incentiveReceiver, retentionIncentive);
            cmp.updateGovernor(gov);
        }

        // Router
        {
            IMinimalInit router = IMinimalInit(_initData.metavaults[4]);
            router.initializeRouter(_initData.metavaults[5], _initData.metavaults[6], _initData.vaultAddresses, premium);
            router.transferOwnership(gov);
        }

        // Bull Vault
        {
            IMinimalInit bullVault = IMinimalInit(_initData.metavaults[1]);
            bullVault.addOperator(_initData.metavaults[4]);
            bullVault.addOperator(_initData.metavaults[5]);
            bullVault.setStrategies(_initData.metavaults[5]);
            bullVault.updateGovernor(gov);
        }

        // Bear Vault
        {
            IMinimalInit bearVault = IMinimalInit(_initData.metavaults[2]);
            bearVault.addOperator(_initData.metavaults[4]);
            bearVault.addOperator(_initData.metavaults[5]);
            bearVault.setStrategies(_initData.metavaults[5]);
            bearVault.updateGovernor(gov);
        }

        // Crab Vault
        {
            IMinimalInit crabVault = IMinimalInit(_initData.metavaults[3]);
            crabVault.addOperator(_initData.metavaults[4]);
            crabVault.addOperator(_initData.metavaults[5]);
            crabVault.setStrategies(_initData.metavaults[5]);
            crabVault.updateGovernor(gov);
        }

        stage[_initData.metavaults[0]] = Stage.CONFIGURED;

        emit Setup(_nonce, _initData.metavaults[0], Stage.CONFIGURED, _initData.metavaults);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   View                                     */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get metavaults addresses.
     * @param _nonce metavault nonce.
     */
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

    /**
     * @notice Verify if caller can call a function.
     * @param _token metavault underlying token.
     * @param _registry lp token registry contract.
     */
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
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Toggle(bool toggle);
    event Create(uint256 nonce, address indexed underlyingToken, Stage stage, address[] metavaults);
    event Setup(uint256 nonce, address indexed underlyingToken, Stage stage, address[] metavaults);
    event UpdateStage(address indexed underlyingToken, Stage oldStage, Stage newStage);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error InvalidStage();
    error CallerNotAllowed();
    error TokenNotWhitelisted();
    error ERC1167FailedCreateClone();
}

