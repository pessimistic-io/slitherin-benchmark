// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { FlashLoanSimpleReceiverBase } from "./FlashLoanSimpleReceiverBase.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
// import { IERC20 } from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";


import "./console.sol";

// interfaces
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Router02.sol";


interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract AAVEFLASHLOAN is FlashLoanSimpleReceiverBase {
    address payable owner;

    // Factory and router addresses 
    address public DEX_A_ROUTER = 0x7d13268144adcdbEBDf94F654085CC15502849Ff;
    address public DEX_B_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public DEX_A_FACTORY = 0xCf083Be4164828f00cAE704EC15a36D711491284;
    address public DEX_B_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

    // Token addresses 
    address public WETH = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public USDC = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    // Trade variables 
    uint256 private deadline = block.timestamp + 1 days;
    uint256 private MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    bool public startAtDexA = true;

    constructor(address _addressProvider) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) 
    {
        owner = payable(msg.sender);
    }

    function isProfitable(uint256 inputAmount, uint256 outputAmount) internal returns(bool) {
        return outputAmount > inputAmount;
    }

    function buyAndSellTokens(address tokenA, address tokenB, uint256 amount, address factory, address router) private returns(uint256) {

        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);

        require(pair != address(0), "Pool does not exist");

        // Calculate Amount Out
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;

        uint256 amountRequired = IUniswapV2Router01(router).getAmountsOut(amount, path)[1];

        console.log("Amount Required: ", amountRequired);

        // Perform Arbitrage - Swap token for another token 
        uint256 amountReceived = IUniswapV2Router01(router)
            .swapExactTokensForTokens(
                amount, // amountIn
                amountRequired, // amountOutMin
                path, // path
                address(this), // address to
                deadline
            )[1];

        console.log("Amount Received: ", amountReceived);

        require(amountReceived > 0, "Aborted Tx:, Trade returned zero");

        return amountReceived;

    }

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        
        // This contract now has the funds requested.
        // Your logic goes here.

        uint256 trade_one;
        uint256 trade_two;

        if (startAtDexA) {
            console.log("DexA");
            trade_one = buyAndSellTokens(USDC, WETH, amount, DEX_A_FACTORY, DEX_A_ROUTER);
            trade_two = buyAndSellTokens(WETH, USDC, trade_one, DEX_B_FACTORY, DEX_B_ROUTER);
        } else {
            console.log("Dex B");
            trade_one = buyAndSellTokens(USDC, WETH, amount, DEX_B_FACTORY, DEX_B_ROUTER);
            trade_two = buyAndSellTokens(WETH, USDC, trade_one, DEX_A_FACTORY, DEX_A_ROUTER);
        }
        

        // At the end of your logic above, this contract owes
        // the flashloaned amount + premium.
        // Therefore ensure your contract has enough to repay
        // these amounts.

        // get total amount owed
        uint256 amountOwed = amount + premium;

        // check for profitability 
        // require(isProfitable(amountOwed, trade_two), "Flashswap was not profitable");
        
         // Approve the Pool contract allowance to *pull* the owed amount
        IERC20(asset).approve(address(POOL), amountOwed);

        return true;
    }

    function requestFlashLoan(address _token, uint256 _amount, bool _startAtDexA) public {

        startAtDexA = _startAtDexA;

        IERC20(USDC).approve(DEX_A_ROUTER, MAX_INT);
        IERC20(WETH).approve(DEX_A_ROUTER, MAX_INT);

        IERC20(USDC).approve(DEX_B_ROUTER, MAX_INT);
        IERC20(WETH).approve(DEX_B_ROUTER, MAX_INT);

        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = "";
        uint16 referralCode = 0;

        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );
    }

    // GET CONTARCT BALANCE 
    // A function to get the balance of a token
    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function withdraw(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function setDexARouter(address _address) external {
        DEX_A_ROUTER = _address;
    }

    function setDexBRouter(address _address) external {
        DEX_B_ROUTER = _address;
    }

    function setDexAFactory(address _address) external {
        DEX_A_FACTORY = _address;
    }

    function setDexBFactory(address _address) external {
        DEX_B_FACTORY = _address;
    }

    function setWETHAddress(address _address) external {
        WETH = _address;
    }

    function setUSDCAddesss(address _address) external {
        USDC = _address;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    receive() external payable {}
}

