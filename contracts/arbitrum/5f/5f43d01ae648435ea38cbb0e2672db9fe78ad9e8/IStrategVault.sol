// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./ERC4626.sol";
import "./ERC20Permit.sol";
import "./Ownable.sol";
import "./Strings.sol";
import {DataTypes} from "./DataTypes.sol";

enum StrategVaultUpdateType {
    Transfer,
    MiddlewareInit,
    NewTimelockParams,
    NewDepositLimits,
    NewHoldingParams,
    NewBufferParams,
    EditWhitelist,
    NewFeeParams,
    StrategyInitialized
}

enum StrategVaultSettings {
    TimelockParams,
    DepositLimits,
    HoldingParams,
    EditWhitelist,
    FeeParams,
    BufferParams
}

interface IStrategVault  {
    event StrategVaultUpdate(StrategVaultUpdateType indexed update, bytes data);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event StrategyInitialized(
        address[] _stratBlocksIndex,
        bytes[] _stratBlocksParameters,
        address[] _harvestBlocksIndex,
        bytes[] _harvestBlocksParameters
    );

    function initialize(
        address _owner,
        address _erc3525,
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _strategy,
        uint256 _bufferSize,
        uint256 _creatorFee,
        uint256 _harvestFee
    ) external;

    function transferFrom(address from, address to, uint256 amount) external;

    function setStrat(
        address[] memory _positionManagers,
        address[] memory _stratBlocks,
        bytes[] memory _stratBlocksParameters,
        address[] memory _harvestBlocks,
        bytes[] memory _harvestBlocksParameters
    ) external;

    function configuration() external view returns (DataTypes.VaultConfigurationMap memory config);

    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function userMinDeposit() external view returns (uint256);
    function userMaxDeposit() external view returns (uint256);
    function vaultMinDeposit() external view returns (uint256);
    function vaultMaxDeposit() external view returns (uint256);

    function registry() external view returns (address);
    function buffer() external view returns (address);
    function feeCollector() external view returns (address);
    function factory() external view returns (address);
    function asset() external view returns (address);

    function harvest(uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) external;

    /**
     * @dev See {IERC4262-deposit}.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256);

    /**
     * @dev See {IERC4262-mint}.
     */
    function mint(uint256 shares, address receiver) external returns (uint256);

    /**
     * @dev See {IERC4262-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);

    /**
     * @dev See {IERC4262-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 _v, bytes32 _r, bytes32 _s)
        external;

    function getStrat()
        external
        view
        returns (
            address[] memory _strategyBlocks,
            bytes[] memory _strategyBlocksParameters,
            address[] memory _harvestBlocks,
            bytes[] memory _harvestBlocksParameters
        );

    function owner() external view returns (address);
    function rebalance(
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external;

    function stopStrategy(uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) external;

    function withdrawalRebalance(
        address _user,
        uint256 _amount,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external;

    function partialStrategyEnter(uint256 _from, uint256[] memory _dynParamsIndex, bytes[] memory _dynParams)
        external;

    function partialStrategyExit(uint256 _to, uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) external;

        function setDepositLimits(
        uint256 _minUserDeposit,
        uint256 _maxUserDeposit,
        uint256 _minVaultDeposit,
        uint256 _maxVaultDeposit
    ) external ;
    
    function whitelist(bool _add, address addr) external;
    function setTimelockParams(bool _enabled, uint256 _duration) external;
    function setHoldingParams(address _token, uint256 _amount) external;
    function setFeeParams(uint256 _creatorFees, uint256 _harvestFees) external;
    function setBufferParams(uint256 _bufferSize, uint256 _bufferDerivation) external;

    function emergencyExecution(address[] memory _targets, bytes[] memory _datas) external;
}

