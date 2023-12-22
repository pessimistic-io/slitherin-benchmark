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
import "./IVault.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./Errors.sol";
import "./WithdrawableUpgradeable.sol";

contract ArbStrategy is WithdrawableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    bytes internal constant ZERO_BYTES = '';

    IUniV2Strategy public defaultUniV2Strategy;
    mapping(address => IUniV2Strategy) private uniV2Strategies;

    IVaultStrategy public defaultVaultStrategy;
    mapping(address => IVaultStrategy) private vaultStrategies;

    IUniV3Strategy public defaultUniV3Strategy;
    mapping(address => IUniV3Strategy) private uniV3Strategies;

    I1InchStrategy public default1InchStrategy;
    mapping(address => I1InchStrategy) private oneInchStrategies;

    IFireBirdStrategy public defaultFireBirdStrategy;
    mapping(address => IFireBirdStrategy) private fireBirdStrategies;

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
    function getUniV2Strategy(address uniV2) public view returns (IUniV2Strategy strategy) {
        IUniV2Strategy _strat = uniV2Strategies[uniV2];
        return _strat != IUniV2Strategy(address(0)) ? _strat : defaultUniV2Strategy;
    }

    /**
     * @dev Get strategy address for vault
     * @param vault Address of vault
     * @return strategy Address of strategy for vault
     */
    function getVaultStrategy(address vault) public view returns (IVaultStrategy strategy) {
        IVaultStrategy _strat = vaultStrategies[vault];
        return _strat != IVaultStrategy(address(0)) ? _strat : defaultVaultStrategy;
    }

    /**
     * @dev Get strategy address for univ3 router
     * @param uniV3 Address of univ3 router
     * @return strategy Address of strategy for univ3 router
     */
    function getUniV3Strategy(address uniV3) public view returns (IUniV3Strategy strategy) {
        IUniV3Strategy _strat = uniV3Strategies[uniV3];
        return _strat != IUniV3Strategy(address(0)) ? _strat : defaultUniV3Strategy;
    }

    /**
     * @dev Get strategy address for 1inch router
     * @param oneInch Address of 1inch router
     * @return strategy Address of strategy for 1inch router
     */
    function get1InchStrategy(address oneInch) public view returns (I1InchStrategy strategy) {
        I1InchStrategy _strat = oneInchStrategies[oneInch];
        return _strat != I1InchStrategy(address(0)) ? _strat : default1InchStrategy;
    }

    /**
     * @dev Get strategy address for firebird router
     * @param fireBird Address of firebird router
     * @return strategy Address of strategy for firebird router
     */
    function getFireBirdStrategy(address fireBird) public view returns (IFireBirdStrategy strategy) {
        IFireBirdStrategy _strat = fireBirdStrategies[fireBird];
        return _strat != IFireBirdStrategy(address(0)) ? _strat : defaultFireBirdStrategy;
    }

    /**
     * @dev Set default strategy for univ2 router
     * @param strategy Address of strategy for univ2 router
     */
    function setDefaultUniV2Strategy(IUniV2Strategy strategy) external onlyOwner {
        defaultUniV2Strategy = strategy;
    }

    /**
     * @dev Set default strategy for vault
     * @param strategy Address of strategy for vault
     */
    function setDefaultVaultStrategy(IVaultStrategy strategy) external onlyOwner {
        defaultVaultStrategy = strategy;
    }

    /**
     * @dev Set default strategy for univ3 router
     * @param strategy Address of strategy for univ3 router
     */
    function setDefaultUniV3Strategy(IUniV3Strategy strategy) external onlyOwner {
        defaultUniV3Strategy = strategy;
    }

    /**
     * @dev Set default strategy for 1inch router
     * @param strategy Address of strategy for 1inch router
     */
    function setDefault1InchStrategy(I1InchStrategy strategy) external onlyOwner {
        default1InchStrategy = strategy;
    }

    /**
     * @dev Set default strategy for firebird router
     * @param strategy Address of strategy for firebird router
     */
    function setDefaultFireBirdStrategy(IFireBirdStrategy strategy) external onlyOwner {
        defaultFireBirdStrategy = strategy;
    }

    /**
     * @dev Set strategy for univ2 router
     * @param uniV2 Address of univ2 router
     * @param strategy Address of strategy for univ2 router
     */
    function setUniV2Strategy(address uniV2, IUniV2Strategy strategy) external onlyOwner {
        uniV2Strategies[uniV2] = strategy;
    }

    /**
     * @dev Set strategy for vault
     * @param vault Address of vault
     * @param strategy Address of strategy for vault
     */
    function setVaultStrategy(address vault, IVaultStrategy strategy) external onlyOwner {
        vaultStrategies[vault] = strategy;
    }

    /**
     * @dev Set strategy for univ3 router
     * @param uniV3 Address of univ3 router
     * @param strategy Address of strategy for univ3 router
     */
    function setUniV3Strategy(address uniV3, IUniV3Strategy strategy) external onlyOwner {
        uniV3Strategies[uniV3] = strategy;
    }

    /**
     * @dev Set strategy for 1inch router
     * @param oneInch Address of 1inch router
     * @param strategy Address of strategy for 1inch router
     */
    function set1InchStrategy(address oneInch, I1InchStrategy strategy) external onlyOwner {
        oneInchStrategies[oneInch] = strategy;
    }

    /**
     * @dev Set strategy for firebird router
     * @param fireBird Address of firebird router
     * @param strategy Address of strategy for firebird router
     */
    function setFireBirdStrategy(address fireBird, IFireBirdStrategy strategy) external onlyOwner {
        fireBirdStrategies[fireBird] = strategy;
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
        IUniV2Strategy uniV2Strategy,
        IVaultStrategy vaultStrategy,
        IUniV3Strategy uniV3Strategy,
        I1InchStrategy oneInchStrategy,
        IFireBirdStrategy fireBirdStrategy
    ) external onlyOwner {
        defaultUniV2Strategy = uniV2Strategy;
        defaultVaultStrategy = vaultStrategy;
        defaultUniV3Strategy = uniV3Strategy;
        default1InchStrategy = oneInchStrategy;
        defaultFireBirdStrategy = fireBirdStrategy;
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

