//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Observable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./SafeMathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IUniswapV3Factory.sol";

contract ObserveMaxWallet is Observable, Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public token;
    IUniswapV3Factory public factory;
    
    address public weth;
    uint256 public maxWallet;
    address public userManager;

    mapping(address => bool) public pairs;

    address internal constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    function initialize() public initializer {
        __Ownable_init();
        maxWallet = 3;
        factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    }

    function observe(
        address from,
        address to,
        uint256 amount
    ) external view override returns (bool) {
        if (pairs[from]) {
            if (
                to != owner() &&
                to != DEAD_ADDRESS &&
                to != address(0) &&
                to != address(this)
            ) {
                uint256 balance = token.balanceOf(to);
                uint256 amountLimit = token.totalSupply().mul(maxWallet).div(
                    100
                );
                require(
                    balance.add(amount) <= amountLimit,
                    "Transfer amount exceeds the MaxHolding"
                );
            }
        }
        return true;
    }

    function createPair() external virtual onlyOwner{
        require(address(token) != address(0), 'Missing implementation');
        uint24 feePool = 10000;
        address pair = factory.getPool(weth, address(token), feePool);
        if(pair == address(0)) {
            pair = factory.createPool(weth, address(token), feePool);
        }
        pairs[pair] = true;
    }

    function setToken(address newAddr) external virtual onlyOwner {
        token = IERC20Upgradeable(newAddr);
    }

    function setUserManager(address newUserManager) external virtual onlyOwner {
        userManager = newUserManager;
    }

    function setMaxWallet(uint256 newMaxWallet) external virtual onlyOwner {
        maxWallet = newMaxWallet;
    }

    function addPair(address addr) external virtual onlyOwner {
        pairs[addr] = true;
    }

    function removePair(address addr) external virtual onlyOwner {
        pairs[addr] = false;
    }
    function setFactory(address newFactory) external virtual onlyOwner {
        factory = IUniswapV3Factory(newFactory);
    }
    function setWeth(address newEth) external virtual onlyOwner {
        weth = newEth;
    }
}

