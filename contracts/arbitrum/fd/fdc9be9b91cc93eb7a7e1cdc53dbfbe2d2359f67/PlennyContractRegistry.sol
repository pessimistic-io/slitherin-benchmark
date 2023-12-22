// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ContextUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IContractRegistry.sol";
import "./IPlennyLocking.sol";
import "./IUniswapV2Router02.sol";

/// @title  PlennyContractRegistry
/// @notice Contract address registry for all Plenny-related contract addresses.
/// @dev    Addresses are registered as a mapping name --> address.
contract PlennyContractRegistry is AccessControlUpgradeable, OwnableUpgradeable, IContractRegistry {

    /// An event emitted when a contract is added in the registry
    event LogRegistered(address indexed destination, bytes32 name);

    /// @notice registry name --> address map
    mapping(bytes32 => address) public registry;

    /// @notice Initializes the contract instead of constructor.
    /// @dev    Can be called only once during contract deployment.
    function initialize() public initializer {
        AccessControlUpgradeable.__AccessControl_init();
        OwnableUpgradeable.__Ownable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @notice Batch register of pairs (name, address) in the contract registry.
    /// @dev    Called by the owner. The names and addresses must be the same length.
    /// @param  _names Array of names
    /// @param  _destinations Array of addresses for the contracts
    function importAddresses(bytes32[] calldata _names, address[] calldata _destinations) external onlyOwner {
        require(_names.length == _destinations.length, "ERR_INVALID_LENGTH");

        for (uint i = 0; i < _names.length; i++) {
            registry[_names[i]] = _destinations[i];
            emit LogRegistered(_destinations[i], _names[i]);
        }
    }

    /// @notice Gets a contract address by a given name.
    /// @param  _bytes name in bytes
    /// @return address contract address, or address(0) if not found
    function getAddress(bytes32 _bytes) external override view returns (address) {
        return registry[_bytes];
    }

    /// @notice Gets the interface of the Plenny token contract.
    /// @return Plenny token
    function plennyTokenContract() external view override returns (IPlennyERC20) {
        return IPlennyERC20(requireAndGetAddress("PlennyERC20"));
    }

    /// @notice Gets the interface of the Plenny factory contract.
    /// @return Plenny factory
    function factoryContract() external view override returns (IPlennyDappFactory) {
        return IPlennyDappFactory(requireAndGetAddress("PlennyDappFactory"));
    }

    /// @notice Gets the interface of Plenny Ocean contract.
    /// @return Plenny Ocean
    function oceanContract() external view override returns (IPlennyOcean) {
        return IPlennyOcean(requireAndGetAddress("PlennyOcean"));
    }

    /// @notice Gets the interface of UniswapV2 liquidity pair corresponding to a Plenny-WETH pool.
    /// @return Uniswap pair
    function lpContract() external view override returns (IUniswapV2Pair) {
        return IUniswapV2Pair(requireAndGetAddress("UNIETH-PL2"));
    }

    /// @notice Gets the interface of the UniswapV2 Router contract.
    /// @return Uniswap router
    function uniswapRouterV2() external view override returns (IUniswapV2Router02) {
        return IUniswapV2Router02(requireAndGetAddress("UniswapRouterV2"));
    }

    /// @notice Gets the interface of the Plenny Treasury contract.
    /// @return Plenny treasury
    function treasuryContract() external view override returns (IPlennyTreasury) {
        return IPlennyTreasury(requireAndGetAddress("PlennyTreasury"));
    }

    /// @notice Gets the interface of the Plenny staking contract.
    /// @return Plenny staking
    function stakingContract() external view override returns (IPlennyStaking) {
        return IPlennyStaking(requireAndGetAddress("PlennyStaking"));
    }

    /// @notice Gets the interface of the Plenny coordinator contract.
    /// @return Plenny coordinator
    function coordinatorContract() external view override returns (IPlennyCoordinator) {
        return IPlennyCoordinator(requireAndGetAddress("PlennyCoordinator"));
    }

    /// @notice Gets the interface of the Plenny election contract.
    /// @return Plenny validator election
    function validatorElectionContract() external view override returns (IPlennyValidatorElection) {
        return IPlennyValidatorElection(requireAndGetAddress("PlennyValidatorElection"));
    }

    /// @notice Gets the interface of the Plenny oracle validation contract.
    /// @return Plenny oracle validator
    function oracleValidatorContract() external view override returns (IPlennyOracleValidator) {
        return IPlennyOracleValidator(requireAndGetAddress("PlennyOracleValidator"));
    }

    /// @notice Gets the interface of the WETH.
    /// @return Wrapped ETH
    function wrappedETHContract() external view override returns (IWETH) {
        return IWETH(requireAndGetAddress("WETH"));
    }

    /// @notice Gets the interface of the Plenny Reward contract.
    /// @return Plenny reward
    function rewardContract() external view override returns (IPlennyReward) {
        return IPlennyReward(requireAndGetAddress("PlennyReward"));
    }

    /// @notice Gets the interface of the Plenny Liquidity mining contract.
    /// @return Plenny liquidity mining
    function liquidityMiningContract() external view override returns (IPlennyLiqMining) {
        return IPlennyLiqMining(requireAndGetAddress("PlennyLiqMining"));
    }

    /// @notice Gets the interface of the Plenny governance locking contract.
    /// @return Plenny governanace locking
    function lockingContract() external view override returns (IPlennyLocking) {
        return IPlennyLocking(requireAndGetAddress("PlennyLocking"));
    }

    /// @notice Gets a contract address by a given name.
    /// @param  name name in bytes
    /// @return address contract address, fails if not found
    function requireAndGetAddress(bytes32 name) public override view returns (address) {
        address _foundAddress = registry[name];
        require(_foundAddress != address(0), string(abi.encodePacked("Name not registered: ", name)));
        return _foundAddress;
    }

    /// @notice Gets a contract address by a given name as string.
    /// @param  _name contract name
    /// @return address contract address, or address(0) if not found
    function getAddressByString(string memory _name) public view returns (address) {
        return registry[stringToBytes32(_name)];
    }

    /// @notice Converts string to bytes32.
    /// @param  _string String to convert
    /// @return result bytes32
    function stringToBytes32(string memory _string) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(_string);

        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(_string, 32))
        }
    }
}

