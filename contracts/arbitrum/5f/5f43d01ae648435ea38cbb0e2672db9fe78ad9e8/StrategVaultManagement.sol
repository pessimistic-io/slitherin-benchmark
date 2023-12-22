// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./OwnableUpgradeable.sol";
import {VaultConfiguration} from "./VaultConfiguration.sol";
import {DataTypes} from "./DataTypes.sol";
import {IStrategVault, StrategVaultUpdateType} from "./IStrategVault.sol";
import "./IStrategERC3525.sol";
//import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * Errors
 */
error NotFactory();
error NotOwner();
error NotWhitelisted();
error MinDepositNotReached();
error MaxUserDepositReached();
error MaxVaultDepositReached();
error TimelockNotReached();
error HoldAmountNotReached();
error BadHarvestFee();
error BadCreatorFee();
error BadBufferParams();

/**
 *   @title StrategVaultMiddleware
 *
 *   @notice This contract serves as a middleware between the user and the actual
 *   strategy vault. It handles the access control and deposit limits for the user
 *   based on the defined middleware strategy.
 */
abstract contract StrategVaultManagement {
    using VaultConfiguration for DataTypes.VaultConfigurationMap;

    address public erc3525;
    address public factory;
    
    mapping(address => uint256) timelocks; // last deposit timestamp

    uint256 public userMinDeposit; // minimum deposit from user if he want to enter in a strategy
    uint256 public userMaxDeposit; // maximum deposit from user if he want to enter in a strategy

    uint256 public vaultMinDeposit; // minimum deposit
    uint256 public vaultMaxDeposit; // maximum deposit

    IERC20 token; // address of token in the vault
    uint256 holdAmount; // Holder of an amount of a specific token

    DataTypes.VaultConfigurationMap config;

    mapping(address => bool) isWhitelisted; // whitelist addresses
    mapping(address => uint256) userDeposit; // user deposits
    event StrategVaultUpdate(StrategVaultUpdateType indexed update, bytes data);

    modifier onlyOwner() {
        if (msg.sender != _owner()) revert NotOwner();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    constructor() {}

    /**
     * @notice Initializes the middleware with the given owner and middleware strategy.
     * @param _erc3525 Address of the vault's ERC3525 contract.
     * @param _strategy Middleware strategy to be applied.
     * @param _creatorFees Creator fees for the vault.
     * @param _harvestFees Harvest fees for the vault.
     */
    function __StrategVaultManagement_init(
        address _factory,
        address _erc3525,
        uint256 _strategy,
        uint256 _creatorFees,
        uint256 _harvestFees
    ) internal {
        factory = _factory;
        erc3525 = _erc3525;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.MiddlewareInit,
            abi.encode(_erc3525, _strategy)
        );

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewFeeParams,
            abi.encode(_creatorFees, _harvestFees)
        );
    }

    function _owner() internal view returns (address) {
        return IStrategERC3525(erc3525).ownerOf(1);
    }

    function owner() external view returns (address) {
        return _owner();
    }

    /**
     * @notice Applies the middleware strategy to the given deposit amount and vault total value.
     * @param _amount Deposit amount
     * @param _vaultTvl Total value of the vault
     */
    function _applyMiddleware(uint256 _amount, uint256 _vaultTvl) internal view {
        uint256 s = config.getMiddlewareStrategy();

        //Check tvl limits
        _applyTvlLimits(_amount, _vaultTvl);

        //Execute middle strategy
        //Public
        if (s == 0) return;

        //Whitelisted
        if (s == 1) {
            _applyWhitelisted();
        }

        //Holder
        if (s == 2) {
            _applyHolder();
        }
    }

    /**
     * @notice Applies the total value locked (TVL) limits to the given deposit amount and vault total value.
     * @param _amount Deposit amount
     * @param _vaultTvl Total value of the vault
     */
    function _applyTvlLimits(uint256 _amount, uint256 _vaultTvl) internal view {
        uint256 mode = config.getLimitMode();
        uint256 userDeposited = userDeposit[msg.sender];

        //No limit set
        if (mode == 0) return;

        //Minimum limit set
        if (mode % 2 == 1) {
            uint256 minDeposit = userMinDeposit;
            if (userDeposited == 0) {
                if (_amount < minDeposit) revert MinDepositNotReached();
            } else {
                if (userDeposited + _amount < minDeposit) {
                    revert MinDepositNotReached();
                }
            }
        }

        //Vault max limit set
        if (mode >= 4) {
            if (_vaultTvl + _amount > vaultMaxDeposit) {
                revert MaxVaultDepositReached();
            }
        }

        //User max limit set
        if (mode % 4 > 1) {
            if (userDeposited + _amount > userMaxDeposit) {
                revert MaxUserDepositReached();
            }
        }
    }

    /**
     * @notice Checks if the sender's address is whitelisted.
     */
    function _applyWhitelisted() internal view {
        if (!isWhitelisted[msg.sender]) revert NotWhitelisted();
    }

    /**
     * @notice Checks if the sender's address holds the required amount of tokens.
     */
    function _applyTimelock() internal view {
        DataTypes.VaultConfigurationMap memory _config = config;
        if (!_config.getTimelockEnabled()) return;

        if (timelocks[msg.sender] + _config.getTimelockDuration() > block.timestamp) revert TimelockNotReached();
    }

    /**
     * @notice Checks if the sender's address holds the required amount of tokens.
     */
    function _applyHolder() internal view {
        if (holdAmount == 0) return;

        uint256 balance = token.balanceOf(msg.sender);
        if (balance < holdAmount) revert HoldAmountNotReached();
    }

    /**
     * @notice Sets the deposit limits for user and vault.
     * @param _minUserDeposit Minimum user deposit
     * @param _maxUserDeposit Maximum user deposit
     * @param _minVaultDeposit Minimum vault deposit
     * @param _maxVaultDeposit Maximum vault deposit
     */
    function setDepositLimits(
        uint256 _minUserDeposit,
        uint256 _maxUserDeposit,
        uint256 _minVaultDeposit,
        uint256 _maxVaultDeposit
    ) external onlyFactory {
        uint256 mode = 0;
        userMinDeposit = _minUserDeposit;
        userMaxDeposit = _maxUserDeposit;
        vaultMinDeposit = _minVaultDeposit;
        vaultMaxDeposit = _maxVaultDeposit;

        if (_minUserDeposit > 0) mode += 1;

        if (_maxUserDeposit > 0) mode += 2;

        if (vaultMaxDeposit > 0) mode += 4;

        DataTypes.VaultConfigurationMap memory c = config;
        c.setLimitMode(mode);
        config = c;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewDepositLimits,
            abi.encode(_minUserDeposit, _maxUserDeposit, _minVaultDeposit, _maxVaultDeposit)
        );
    }

    /**
     * @notice Sets the deposit limits for user and vault.
     * @param _user Minimum user deposit
     * @return _userDeposit Minimum user deposit
     * @return _minUserDeposit Minimum user deposit
     * @return _maxUserDeposit Maximum user deposit
     * @return _minVaultDeposit Minimum vault deposit
     * @return _maxVaultDeposit Maximum vault deposit
     */
    function getLimits(address _user)
        external
        view
        returns (
            uint256 _userDeposit,
            uint256 _minUserDeposit,
            uint256 _maxUserDeposit,
            uint256 _minVaultDeposit,
            uint256 _maxVaultDeposit
        )
    {
        uint256 mode = config.getLimitMode();
        _minVaultDeposit = vaultMinDeposit;
        _userDeposit = userDeposit[_user];
        //No limit set
        if (mode != 0) {
            //Minimum limit set
            if (mode % 2 == 1) _minUserDeposit = userMinDeposit;

            //Vault max limit set
            if (mode >= 4) _maxVaultDeposit = vaultMaxDeposit;

            //User max limit set
            if (mode % 4 > 1) _maxUserDeposit = userMaxDeposit;
        }
    }

    function _whitelistInit(address _address) internal {
        isWhitelisted[_address] = true;
    }

    /**
     * @notice Adds the given addresses to the whitelist.
     * @param _add Array of addresses to be added to the whitelist
     * @param _addr Array of addresses to be added to the whitelist
     */
    function whitelist(bool _add, address _addr) external onlyFactory {
        isWhitelisted[_addr] = _add;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.EditWhitelist,
            abi.encode(_add, _addr)
        );
    }

    /**
     * @notice Sets the timelock parameters
     * @param _enabled enable the timelock
     * @param _duration timelock duration after a deposit
     */
    function setTimelockParams(bool _enabled, uint256 _duration) external onlyFactory {
        DataTypes.VaultConfigurationMap memory c = config;
        c.setTimelockEnabled(_enabled);
        c.setTimelockDuration(_duration);
        config = c;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewTimelockParams,
            abi.encode(_enabled, _duration)
        );
    }

    /**
     * @notice Sets the buffer parameters
     * @param _bufferSize enable the timelock
     * @param _bufferDerivation timelock duration after a deposit
     */
    function setBufferParams(uint256 _bufferSize, uint256 _bufferDerivation) external onlyFactory {
        if(
            _bufferSize > 9000 || _bufferSize < 1000 || _bufferDerivation < 500 || _bufferDerivation > 2000
        ) revert BadBufferParams();

        DataTypes.VaultConfigurationMap memory c = config;
        c.setBufferSize(_bufferSize);
        c.setBufferDerivation(_bufferDerivation);
        config = c;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewBufferParams,
            abi.encode(_bufferSize, _bufferDerivation)
        );
    }

    /**
     * @notice Resets the deposited value for the given user address.
     * @param _user Address of the user
     */
    function _resetTimelock(address _user) internal {
        if (config.getTimelockEnabled()) timelocks[_user] = block.timestamp;
    }

    /**
     * @notice Sets the holding parameters for the token and amount.
     * @param _token Address of the token
     * @param _amount Amount of the token to be held
     */
    function setHoldingParams(address _token, uint256 _amount) external onlyFactory {
        token = IERC20(_token);
        holdAmount = _amount;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewHoldingParams,
            abi.encode(_token, _amount)
        );
    }

    /**
     * @notice Sets fees parameters
     * @param _creatorFees creator fees
     * @param _harvestFees tharvester fees
     */
    function setFeeParams(uint256 _creatorFees, uint256 _harvestFees) external onlyFactory {
        DataTypes.VaultConfigurationMap memory c = config;
        c.setCreatorFee(_creatorFees);
        c.setHarvestFee(_harvestFees);
        config = c;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.NewFeeParams,
            abi.encode(_creatorFees, _harvestFees)
        );
    }

    /**
     * @notice Resets the deposited value for the given user address.
     * @param _user Address of the user
     */
    function _resetValueDeposited(address _user) internal {
        userDeposit[_user] = 0;
    }

    /**
     * @notice Decreases the deposited value for the given user address by the specified amount.
     * @param _user Address of the user
     * @param _amount Amount to decrease the deposited value by
     */
    function _decreaseValueDeposited(address _user, uint256 _amount) internal {
        uint256 userAmount = userDeposit[_user];
        if (_amount >= userAmount) {
            _resetValueDeposited(_user);
        } else {
            userDeposit[_user] -= _amount;
        }
    }

    /**
     * @notice Increases the deposited value for the given user address by the specified amount.
     * @param _user Address of the user
     * @param _amount Amount to increase the deposited value by
     */
    function _incrementValueDeposited(address _user, uint256 _amount) internal {
        userDeposit[_user] += _amount;
    }
}

