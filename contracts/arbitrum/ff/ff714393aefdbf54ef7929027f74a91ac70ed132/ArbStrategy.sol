// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IUniV2Strategy.sol";
import "./IVaultStrategy.sol";
import "./IUniV3Strategy.sol";
import "./I1InchStrategy.sol";
import "./IFireBirdStrategy.sol";
import "./IOdosStrategy.sol";
import "./IParaswapStrategy.sol";
import "./IVault.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./IOdosRouter.sol";
import "./Errors.sol";
import "./Utils.sol";
import "./WithdrawableUpgradeable.sol";

contract ArbStrategy is WithdrawableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    bytes internal constant ZERO_BYTES = '';

    address public defaultUniV2Strategy;
    mapping(address => address) private uniV2Strategies;

    address public defaultVaultStrategy;
    mapping(address => address) private vaultStrategies;

    address public defaultUniV3Strategy;
    mapping(address => address) private uniV3Strategies;

    address public default1InchStrategy;
    mapping(address => address) private oneInchStrategies;

    address public defaultFireBirdStrategy;
    mapping(address => address) private fireBirdStrategies;

    address public defaultOdosStrategy;
    mapping(address => address) private odosStrategies;

    address public defaultParaStrategy;
    mapping(address => address) private paraStrategies;

    mapping(address => bool) public whitelist;

    modifier onlyWhitelist() {
        _require(whitelist[_msgSender()], Errors.NOT_WHITELIST);
        _;
    }

    //solhint-disable-next-line no-empty-blocks
    receive() external payable {
        // Required to receive funds
    }

    /**
     * @dev Initialize functions for withdrawable, reentrancy guard, pausable
     */
    function initialize() public initializer {
        __Withdrawable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    /**
     * @dev Get strategy address for univ2 router
     * @param uniV2 Address of univ2 router
     * @return strategy Address of strategy for univ2 router
     */
    function getUniV2Strategy(address uniV2) public view returns (address strategy) {
        address _strat = uniV2Strategies[uniV2];
        return _strat != address(0) ? _strat : defaultUniV2Strategy;
    }

    /**
     * @dev Get strategy address for vault
     * @param vault Address of vault
     * @return strategy Address of strategy for vault
     */
    function getVaultStrategy(address vault) public view returns (address strategy) {
        address _strat = vaultStrategies[vault];
        return _strat != address(0) ? _strat : defaultVaultStrategy;
    }

    /**
     * @dev Get strategy address for univ3 router
     * @param uniV3 Address of univ3 router
     * @return strategy Address of strategy for univ3 router
     */
    function getUniV3Strategy(address uniV3) public view returns (address strategy) {
        address _strat = uniV3Strategies[uniV3];
        return _strat != address(0) ? _strat : defaultUniV3Strategy;
    }

    /**
     * @dev Get strategy address for 1inch router
     * @param oneInch Address of 1inch router
     * @return strategy Address of strategy for 1inch router
     */
    function get1InchStrategy(address oneInch) public view returns (address strategy) {
        address _strat = oneInchStrategies[oneInch];
        return _strat != address(0) ? _strat : default1InchStrategy;
    }

    /**
     * @dev Get strategy address for firebird router
     * @param fireBird Address of firebird router
     * @return strategy Address of strategy for firebird router
     */
    function getFireBirdStrategy(address fireBird) public view returns (address strategy) {
        address _strat = fireBirdStrategies[fireBird];
        return _strat != address(0) ? _strat : defaultFireBirdStrategy;
    }

    /**
     * @dev Get strategy address for odos router
     * @param odos Address of odos router
     * @return strategy Address of strategy for odos router
     */
    function getOdosStrategy(address odos) public view returns (address strategy) {
        address _strat = odosStrategies[odos];
        return _strat != address(0) ? _strat : defaultOdosStrategy;
    }

    /**
     * @dev Get strategy address for paraswap router
     * @param para Address of paraswap router
     * @return strategy Address of strategy for paraswap router
     */
    function getParaStrategy(address para) public view returns (address strategy) {
        address _strat = paraStrategies[para];
        return _strat != address(0) ? _strat : defaultParaStrategy;
    }

    /**
     * @dev Set default strategy for univ2 router
     * @param strategy Address of strategy for univ2 router
     */
    function setDefaultUniV2Strategy(address strategy) external onlyOwner {
        defaultUniV2Strategy = strategy;
    }

    /**
     * @dev Set default strategy for vault
     * @param strategy Address of strategy for vault
     */
    function setDefaultVaultStrategy(address strategy) external onlyOwner {
        defaultVaultStrategy = strategy;
    }

    /**
     * @dev Set default strategy for univ3 router
     * @param strategy Address of strategy for univ3 router
     */
    function setDefaultUniV3Strategy(address strategy) external onlyOwner {
        defaultUniV3Strategy = strategy;
    }

    /**
     * @dev Set default strategy for 1inch router
     * @param strategy Address of strategy for 1inch router
     */
    function setDefault1InchStrategy(address strategy) external onlyOwner {
        default1InchStrategy = strategy;
    }

    /**
     * @dev Set default strategy for firebird router
     * @param strategy Address of strategy for firebird router
     */
    function setDefaultFireBirdStrategy(address strategy) external onlyOwner {
        defaultFireBirdStrategy = strategy;
    }

    /**
     * @dev Set default strategy for odos router
     * @param strategy Address of strategy for odos router
     */
    function setDefaultOdosStrategy(address strategy) external onlyOwner {
        defaultOdosStrategy = strategy;
    }

    /**
     * @dev Set default strategy for paraswap router
     * @param strategy Address of strategy for odos router
     */
    function setDefaultParaStrategy(address strategy) external onlyOwner {
        defaultParaStrategy = strategy;
    }

    /**
     * @dev Set strategy for univ2 router
     * @param uniV2 Address of univ2 router
     * @param strategy Address of strategy for univ2 router
     */
    function setUniV2Strategy(address uniV2, address strategy) external onlyOwner {
        uniV2Strategies[uniV2] = strategy;
    }

    /**
     * @dev Set strategy for vault
     * @param vault Address of vault
     * @param strategy Address of strategy for vault
     */
    function setVaultStrategy(address vault, address strategy) external onlyOwner {
        vaultStrategies[vault] = strategy;
    }

    /**
     * @dev Set strategy for univ3 router
     * @param uniV3 Address of univ3 router
     * @param strategy Address of strategy for univ3 router
     */
    function setUniV3Strategy(address uniV3, address strategy) external onlyOwner {
        uniV3Strategies[uniV3] = strategy;
    }

    /**
     * @dev Set strategy for 1inch router
     * @param oneInch Address of 1inch router
     * @param strategy Address of strategy for 1inch router
     */
    function set1InchStrategy(address oneInch, address strategy) external onlyOwner {
        oneInchStrategies[oneInch] = strategy;
    }

    /**
     * @dev Set strategy for firebird router
     * @param fireBird Address of firebird router
     * @param strategy Address of strategy for firebird router
     */
    function setFireBirdStrategy(address fireBird, address strategy) external onlyOwner {
        fireBirdStrategies[fireBird] = strategy;
    }

    /**
     * @dev Set strategy for odos router
     * @param odos Address of odos router
     * @param strategy Address of strategy for odos router
     */
    function setOdosStrategy(address odos, address strategy) external onlyOwner {
        odosStrategies[odos] = strategy;
    }

    /**
     * @dev Set strategy for paraswap router
     * @param para Address of paraswap router
     * @param strategy Address of strategy for paraswap router
     */
    function setParaStrategy(address para, address strategy) external onlyOwner {
        paraStrategies[para] = strategy;
    }

    /**
     * @dev Set the whitelist status of an address.
     * @param user Address of user
     * @param isWhitelist If true, add the address to the whitelist. If false, remove it from the whitelist.
     */
    function setWhitelist(address user, bool isWhitelist) external onlyOwner {
        whitelist[user] = isWhitelist;
    }

    /**
     * @dev Set the default strategies
     */
    function setup(
        address uniV2Strategy,
        address vaultStrategy,
        address uniV3Strategy,
        address oneInchStrategy,
        address fireBirdStrategy,
        address odosStrategy,
        address paraStrategy
    ) external onlyOwner {
        defaultUniV2Strategy = uniV2Strategy;
        defaultVaultStrategy = vaultStrategy;
        defaultUniV3Strategy = uniV3Strategy;
        default1InchStrategy = oneInchStrategy;
        defaultFireBirdStrategy = fireBirdStrategy;
        defaultOdosStrategy = odosStrategy;
        defaultParaStrategy = paraStrategy;
    }

    /**
     * @dev Pause the contract
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Resume the contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Get balance of this contract.
     */
    function getBalance() internal view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Ensure we got a profit
     */
    function _ensureProfit(uint256 amountIn, IERC20Upgradeable tokenOut) internal returns (uint256 actualAmountOut) {
        if (tokenOut == ZERO_ADDRESS) {
            actualAmountOut = getBalance();
            payable(_msgSender()).sendValue(actualAmountOut);
        } else {
            actualAmountOut = tokenOut.balanceOf(address(this));
            tokenOut.transfer(_msgSender(), actualAmountOut);
        }
        _require(actualAmountOut > amountIn, Errors.NO_PROFIT);
    }

    /**
     * @dev Transfer profit to treasury
     */
    function _transferProfit(uint256 amountIn, IERC20Upgradeable tokenOut) internal returns (uint256 profit) {
        uint256 amountOut;
        if (tokenOut == ZERO_ADDRESS) amountOut = getBalance();
        else amountOut = tokenOut.balanceOf(address(this));

        _require(amountOut > amountIn, Errors.NO_PROFIT);

        profit = amountOut - amountIn;
        if (tokenOut == ZERO_ADDRESS) payable(treasury).sendValue(profit);
        else tokenOut.safeTransfer(treasury, profit);
    }

    /**
     * @dev Get limits for vault
     */
    function getLimitsForVault(uint length) internal pure returns (int256[] memory) {
        int256[] memory limits = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            limits[i] = type(int256).max;
        }
        return limits;
    }
}

