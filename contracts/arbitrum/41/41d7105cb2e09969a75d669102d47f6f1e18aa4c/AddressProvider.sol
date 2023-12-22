// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IAddressProvider.sol";

import "./OwnableUpgradeable.sol";
import "./ERC20.sol";
import "./ILendVault.sol";
import "./IBorrower.sol";
import "./IReserve.sol";
import "./ISwapper.sol";
import "./IOracle.sol";
import "./IController.sol";
import "./IStrategyVault.sol";
import "./INonfungiblePositionManager.sol";
import "./AddressArray.sol";
import "./AccessControl.sol";

/**
 * @notice AddressProvider acts as a registry for addresses that are used throughout the lending module
 * @dev Most of the setter functions call the address being set with an expected function as input validation
 */
contract AddressProvider is AccessControl, IAddressProvider {
    using AddressArray for address[];
    
    address public networkToken;
    address public usdc;
    address public usdt;
    address public dai;
    address public swapper;
    address public reserve;
    address public lendVault;
    address public borrowerManager;
    address public oracle;
    address public uniswapV3Integration;
    address public uniswapV3StrategyLogic;
    address public borrowerBalanceCalculator;

    // Farming addresses
    address public keeper;
    address public governance;
    address public guardian;
    address public controller;
    address[] public vaults;
    address public uniswapV3StrategyData;

    function initialize() external initializer {
        governance = msg.sender;
        provider = IAddressProvider(address(this));
    }

    function getVaults() external view returns (address[] memory v) {
        v = vaults.copy();
    }
    
    function setNetworkToken(address token) external restrictAccess(GOVERNOR) {
        networkToken = token;
        ERC20(networkToken).decimals();
    }

    function setUsdc(address token) external restrictAccess(GOVERNOR) {
        usdc = token;
        ERC20(usdc).decimals();
    }
    
    function setUsdt(address token) external restrictAccess(GOVERNOR) {
        usdt = token;
        ERC20(usdt).decimals();
    }
    
    function setDai(address token) external restrictAccess(GOVERNOR) {
        dai = token;
        ERC20(dai).decimals();
    }

    function setReserve(address _reserve) external restrictAccess(GOVERNOR) {
        reserve = _reserve;
        IReserve(_reserve).expectedBalance();
    }

    function setSwapper(address _swapper) external restrictAccess(GOVERNOR) {
        swapper = _swapper;
        ISwapper(_swapper).getETHValue(networkToken, 1e18);
    }

    function setLendVault(address _lendVault) external restrictAccess(GOVERNOR) {
        lendVault = _lendVault;
        ILendVault(_lendVault).getSupportedTokens();
    }

    function setBorrowerManager(address _manager) external restrictAccess(GOVERNOR) {
        borrowerManager = _manager;
    }
    
    function setOracle(address _oracle) external restrictAccess(GOVERNOR) {
        oracle = _oracle;
        IOracle(oracle).getPrice(networkToken);
    }
    
    function setUniswapV3Integration(address _integration) external restrictAccess(GOVERNOR) {
        uniswapV3Integration = _integration;
    }

    function setUniswapV3StrategyData(address _address) external restrictAccess(GOVERNOR) {
        uniswapV3StrategyData = _address;
    }

    function setUniswapV3StrategyLogic(address _logic) external restrictAccess(GOVERNOR) {
        uniswapV3StrategyLogic = _logic;
    }
    
    function setBorrowerBalanceCalculator(address _calculator) external restrictAccess(GOVERNOR) {
        borrowerBalanceCalculator = _calculator;
    }
    
    function setKeeper(address _keeper) external restrictAccess(GOVERNOR) {
        keeper = _keeper;
    }
    
    /**
     * @notice Sets the governance address and transfers ownership
     * to the new governance address
     */
    function setGovernance(address _governance) external restrictAccess(GOVERNOR) {
        governance = _governance;
    }
    
    function setGuardian(address _guardian) external restrictAccess(GOVERNOR) {
        guardian = _guardian;
    }
    
    function setController(address _controller) external restrictAccess(GOVERNOR) {
        IController(_controller).vaults(address(0));
        controller = _controller;
    }
    
    function addVault(address _vault) external restrictAccess(GOVERNOR) {
        IStrategyVault(_vault).depositToken();
        if (!vaults.exists(_vault)) vaults.push(_vault);
    }

    function removeVault(address _vault) external restrictAccess(GOVERNOR) {
        uint index = vaults.findFirst(_vault);
        if (index<vaults.length) {
            vaults[index] = vaults[vaults.length-1];
            vaults.pop();
        }
    }
}
