// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AddressUpgradeable.sol";

import "./IUniV2Strategy.sol";
import "./IVaultStrategy.sol";
import "./IUniV3Strategy.sol";
import "./I1InchStrategy.sol";
import "./IVault.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./Errors.sol";
import "./WithdrawableUpgradeable.sol";

contract ArbStrategy is WithdrawableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
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

    mapping(address => bool) public whitelist;

    modifier onlyWhitelist() {
        _require(whitelist[_msgSender()], Errors.NOT_WHITELIST);
        _;
    }

    //solhint-disable-next-line no-empty-blocks
    receive() external payable {
        // Required to receive funds
    }

    function initialize() public initializer {
        __Withdrawable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function getUniV2Strategy(address uniV2) public view returns (IUniV2Strategy strategy) {
        IUniV2Strategy _strat = uniV2Strategies[uniV2];
        return _strat != IUniV2Strategy(address(0)) ? _strat : defaultUniV2Strategy;
    }

    function getVaultStrategy(address vault) public view returns (IVaultStrategy strategy) {
        IVaultStrategy _strat = vaultStrategies[vault];
        return _strat != IVaultStrategy(address(0)) ? _strat : defaultVaultStrategy;
    }

    function getUniV3Strategy(address uniV3) public view returns (IUniV3Strategy strategy) {
        IUniV3Strategy _strat = uniV3Strategies[uniV3];
        return _strat != IUniV3Strategy(address(0)) ? _strat : defaultUniV3Strategy;
    }

    function get1InchStrategy(address oneInch) public view returns (I1InchStrategy strategy) {
        I1InchStrategy _strat = oneInchStrategies[oneInch];
        return _strat != I1InchStrategy(address(0)) ? _strat : default1InchStrategy;
    }

    function setDefaultUniV2Strategy(IUniV2Strategy strategy) external onlyOwner {
        defaultUniV2Strategy = strategy;
    }

    function setDefaultVaultStrategy(IVaultStrategy strategy) external onlyOwner {
        defaultVaultStrategy = strategy;
    }

    function setDefaultUniV3Strategy(IUniV3Strategy strategy) external onlyOwner {
        defaultUniV3Strategy = strategy;
    }

    function setDefault1InchStrategy(I1InchStrategy strategy) external onlyOwner {
        default1InchStrategy = strategy;
    }

    function setUniV2Strategy(address uniV2, IUniV2Strategy strategy) external onlyOwner {
        uniV2Strategies[uniV2] = strategy;
    }

    function setVaultStrategy(address vault, IVaultStrategy strategy) external onlyOwner {
        vaultStrategies[vault] = strategy;
    }

    function setUniV3Strategy(address uniV3, IUniV3Strategy strategy) external onlyOwner {
        uniV3Strategies[uniV3] = strategy;
    }

    function set1InchStrategy(address oneInch, I1InchStrategy strategy) external onlyOwner {
        oneInchStrategies[oneInch] = strategy;
    }

    function setWhitelist(address user, bool isWhitelist) external onlyOwner {
        whitelist[user] = isWhitelist;
    }

    function setup(
        IUniV2Strategy uniV2Strategy,
        IVaultStrategy vaultStrategy,
        IUniV3Strategy uniV3Strategy,
        I1InchStrategy oneInchStrategy
    ) external onlyOwner {
        defaultUniV2Strategy = uniV2Strategy;
        defaultVaultStrategy = vaultStrategy;
        defaultUniV3Strategy = uniV3Strategy;
        default1InchStrategy = oneInchStrategy;
    }

    function pause() public onlyOwner {
        _pause();
    }

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
    function _afterSwap(uint256 amountIn) internal returns(uint256 actualAmountOut) {
        actualAmountOut = getBalance();
        _require(actualAmountOut > amountIn, Errors.NO_PROFIT);
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }
}

