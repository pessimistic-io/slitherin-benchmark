//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//creates pair, adds liquidity, removes liquidity, swaps tokens, etc.

//import interfaces
import "./KarrotInterfaces.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./Strings.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract DexInterfacerSushiswap is Ownable {
    IConfig public config;
    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    address public admin;
    address public tokenEthPairAddress;
    bool public tokenDeposited;
    bool public ethDeposited;
    bool public poolCreated;
    bool public poolFunded;

    event PoolCreated(address poolAddress);
    event LiquidityAdded(uint liquidity);

    error CallerIsNotConfig();

    constructor(address _configManager) {
        admin = msg.sender;
        config = IConfig(_configManager);
    }

    bool public isStable = false;

    function createPool() public onlyOwner returns (address) {
        IERC20 karrotToken = IERC20(config.karrotsAddress());

        require(ethDeposited && tokenDeposited, "eth or token not deposited!");
        require(!poolCreated, "pool already created!");

        address routerAddress = config.sushiswapRouterAddress();

        karrotToken.approve(routerAddress, type(uint).max);
        karrotToken.approve(config.sushiswapFactoryAddress(), type(uint).max);

        tokenEthPairAddress = IUniswapV2Factory(config.sushiswapFactoryAddress()).createPair(config.karrotsAddress(), IUniswapV2Router02(config.sushiswapRouterAddress()).WETH());
        
        IERC20(tokenEthPairAddress).approve(routerAddress, type(uint).max);
        
        emit PoolCreated(tokenEthPairAddress);
        poolCreated = true;
        return tokenEthPairAddress;
    }

    function addLiquidity() public onlyOwner {
        require(poolCreated, "pool not created!");
        require(!poolFunded, "pool already funded!");

        IERC20 karrotToken = IERC20(config.karrotsAddress());

        require(karrotToken.balanceOf(address(this)) > 0, "no karrot token in contract!");
        uint256 thisContractsKarrotBalance = karrotToken.balanceOf(address(this));
        IUniswapV2Router02(config.sushiswapRouterAddress()).addLiquidityETH{value: address(this).balance}( // eth balance
            config.karrotsAddress(),
            thisContractsKarrotBalance, 
            0,
            0,
            address(this),
            block.timestamp
        );
        poolFunded = true;
        emit LiquidityAdded(thisContractsKarrotBalance);
    }

    function depositEth() public payable onlyOwner {
        require(msg.value > 0, "no eth sent!");
        ethDeposited = true;
    }

    //must have allowance for this contract set before calling
    function depositErc20(uint256 _amount) public onlyOwner {
        IERC20 karrotToken = IERC20(config.karrotsAddress());
        require(karrotToken.allowance(msg.sender, address(this)) >= _amount, "not enough allowance!");
        require(_amount > 0, "no tokens sent!");
        require(karrotToken.balanceOf(msg.sender) >= _amount, "not enough tokens!");
        
        karrotToken.transferFrom(msg.sender, address(this), _amount);
        tokenDeposited = true;
    }

    function getPairAddressFromThis() public view returns (address) {
        return tokenEthPairAddress;
    }

    function getPoolIsCreated() public view returns (bool) {
        return poolCreated;
    }

    function getPoolIsFunded() public view returns (bool) {
        return poolFunded;
    }

    function getContractLpTokenBalance() public view returns (uint256) {
        return IERC20(tokenEthPairAddress).balanceOf(address(this));
    }

    function withdrawTokens() public onlyOwner {
        (bool os, ) = admin.call{value: address(this).balance}("");
        require(os, "transfer failed");
    }
    //add amount for production to avoid having to withdraw all tokens at once
    function withdrawERC20Tokens(address _token, uint256 _amount) public onlyOwner {
        IKarrotsToken(_token).transfer(msg.sender, _amount);
    }
}

