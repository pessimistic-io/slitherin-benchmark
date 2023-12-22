
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IERC20 } from "./IERC20.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { ISwapPair } from "./ISwapPair.sol";
import { IRebaser } from "./IRebaser.sol";

contract Rebaser is IRebaser {

    address public _token;
    address public admin;
    bool private inRebase;
    bool public rebaseEnabled;

    uint256 public liquidityUnlockTime;
    uint256 public percentToRemove = 9800; // 98%
    uint256 public divisor = 10000;
    uint256 public teamFee = 5 * 10**5; // $0.50
    address public teamAddress;

    ISwapRouter public swapRouter;
    address public immutable USDC;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public swapPair;
    ISwapPair public pair;
    address public tokenA;
    address public tokenB;

    event LiquidityLocked(uint256 lockedLiquidityAmount, uint256 liquidityLockExpiration);
    event AdminUpdated(address newAdmin);
    event AdminRenounced();

    modifier onlyAdmin {
        require(msg.sender == admin, "Caller not Admin");
        _;
    }

    modifier lockTheSwap {
        inRebase = true;
        _;
        inRebase = false;
    }

    modifier onlyToken() {
        require(msg.sender == _token, "Caller not Token"); 
        _;
    }

    constructor(address _router, address _usdc, address _admin, address _teamAddress, address _pair) {
        swapRouter = ISwapRouter(_router);
        _token = msg.sender;
        USDC = _usdc;
        admin = _admin;
        teamAddress = _teamAddress;

        swapPair = _pair;
        pair = ISwapPair(_pair);

        tokenA = pair.token0();
        tokenB = pair.token1();
    }

    receive() external payable {}
   
    function updateAdmin(address _newAdmin) external onlyAdmin {
        admin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

    function renounceAdminRole() external onlyAdmin {
        admin = address(0);
        emit AdminRenounced();
    }

    function setRebaseEnabled(bool flag) external override {
        require(msg.sender == admin || msg.sender == _token, "Erection: caller not allowed");
        rebaseEnabled = flag;
    }

    function setPercentToRemove(uint256 _percent) external onlyAdmin {
        percentToRemove = _percent;
    }

    function setTeamAddress(address _teamAddress) external override {
        require(msg.sender == admin || msg.sender == _token, "Erection: caller not allowed");
        teamAddress = _teamAddress;
    }

    function setTeamFee(uint256 _amount) external onlyAdmin {
        teamFee = _amount;
    }

    function setSwapPair(address _pair) external override {
        require(msg.sender == admin || msg.sender == _token, "Erection: caller not allowed");
        swapPair = _pair;
        pair = ISwapPair(_pair);

        tokenA = pair.token0();
        tokenB = pair.token1();
    }

    function depositAndLockLiquidity(uint256 _amount, uint256 _unlockTime) external onlyAdmin {
        require(liquidityUnlockTime <= _unlockTime, "Can not shorten lock time");
        IERC20(swapPair).transferFrom(msg.sender, address(this), _amount);
        liquidityUnlockTime = _unlockTime;
        emit LiquidityLocked(_amount, _unlockTime);
    }

    function rebase(
        uint256 currentPrice, 
        uint256 targetPrice
    ) external override onlyToken lockTheSwap returns (
        uint256 amountToSwap,
        uint256 amountUSDCtoAdd,
        uint256 burnAmount
    ) {
        if(rebaseEnabled){
            removeLiquidity();
            uint256 balanceUSDC = IERC20(USDC).balanceOf(address(this));
            (uint reserve0, uint reserve1,) = pair.getReserves();
            uint256 adjustment = (((targetPrice * 10**18) / currentPrice) - 10**18) / 2;
            if(pair.token0() == USDC) {  
                uint256 reserve0Needed = (reserve0 * (adjustment + 10**18)) /  10**18;
                amountToSwap = reserve0Needed - reserve0;
            } else if(pair.token1() == USDC) {
                uint256 reserve1Needed = (reserve1 * (adjustment + 10**18)) / 10**18;
                amountToSwap = reserve1Needed - reserve1;
            }
            uint256 amountUSDCAvailable = balanceUSDC - amountToSwap;
            amountUSDCtoAdd = amountUSDCAvailable - teamFee;
            buyTokens(amountToSwap, amountUSDCtoAdd);
            IERC20(USDC).transfer(teamAddress, teamFee);
            burnAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).transfer(BURN_ADDRESS, burnAmount);
        } 
    }

    // Remove bnb that is sent here by mistake
    function removeBNB(uint256 amount, address to) external onlyAdmin{
        payable(to).transfer(amount);
      }

    // Remove tokens that are sent here by mistake
    function removeToken(IERC20 token, uint256 amount, address to) external onlyAdmin {
        if (block.timestamp < liquidityUnlockTime) {
            require(token != IERC20(swapPair), "Liquidity is locked");
        }
        if( token.balanceOf(address(this)) < amount ) {
            amount = token.balanceOf(address(this));
        }
        token.transfer(to, amount);
    }

    function removeLiquidity() internal {
        uint256 amountToRemove = (IERC20(swapPair).balanceOf(address(this)) * percentToRemove) / divisor;
       
        IERC20(swapPair).approve(address(swapRouter), amountToRemove);
        
        // Remove the liquidity
        swapRouter.removeLiquidity(
            tokenA,
            tokenB,
            amountToRemove,
            0, // Slippage is unavoidable
            0, // Slippage is unavoidable
            address(this),
            block.timestamp
        ); 
    }

    function buyTokens(uint256 amountToSwap, uint256 amountUSDCtoAdd) internal {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = _token;

        IERC20(USDC).approve(address(swapRouter), amountToSwap);

        swapRouter.swapExactTokensForTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        addLiquidity(amountUSDCtoAdd); 
    }

    function addLiquidity(uint256 amountUSDCtoAdd) internal {
        uint256 amountTokenToAdd = IERC20(_token).balanceOf(address(this));
       
        IERC20(_token).approve(address(swapRouter), amountTokenToAdd);
        IERC20(USDC).approve(address(swapRouter), amountUSDCtoAdd);
        
        // Add the liquidity
        swapRouter.addLiquidity(
            _token,
            USDC,
            amountTokenToAdd,
            amountUSDCtoAdd,
            0, // Slippage is unavoidable
            0, // Slippage is unavoidable
            address(this),
            block.timestamp
        ); 
    }
}
