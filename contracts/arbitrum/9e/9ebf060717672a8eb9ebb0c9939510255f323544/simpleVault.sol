// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

import "./IV3SwapRouter.sol";


contract SimpleVault is Ownable {
    using SafeMath for uint256;
    string private _name = "SimpleVault";

    address private _owner;
    bool private lock =false;

    mapping (address => uint256) private N; //numerators
    uint256 private D = 1; //denominator
    uint256 private T; //total amount of tokens
    address private token0;
    address private token1;
    address private currentToken;
    address private otherToken;
    uint256 private lastTradeTime = 0;
    IV3SwapRouter router;

    constructor(address token0In, address token1In, uint256 currentTokenIn, address routerAddress) {
        _owner = msg.sender;
        token0 = token0In;
        token1 = token1In;
        if (currentTokenIn == 0) {
            currentToken = token0;
            otherToken = token1;
        } else {
            currentToken = token1;
            otherToken = token0;
        }        
        router = IV3SwapRouter(routerAddress);
        IERC20(token0).approve(routerAddress, type(uint256).max);
        IERC20(token1).approve(routerAddress, type(uint256).max);
    }
    modifier nonReentrant() {
        require(!lock, "no reentrancy allowed");
        lock = true;
        _;
        lock = false;
    }
    function name() public view returns(string memory){
        return _name;
    }

    //change router, if needed
    function setRouter(address routerAddress) public onlyOwner {
        router = IV3SwapRouter(routerAddress);
        IERC20(token0).approve(routerAddress, type(uint256).max);
        IERC20(token1).approve(routerAddress, type(uint256).max);
    }

    function getRouter() public view returns(address){
        return address(router);
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function setOwner(address newOwner) public onlyOwner {
        _owner = newOwner;
    }

    function setCurrentToken(uint256 num) public onlyOwner {
        if (num == 0) {
            currentToken = token0;
            otherToken = token1;
        } else {
            currentToken = token1;
            otherToken = token0;
        }
    }

    function getFundBalance() public view returns (uint256) {
        return T;
    }

    function getCurrentToken() public view returns (address) {
        return currentToken;
    }

    function getOtherToken() public view returns (address) {
        return otherToken;
    }

    function getBalance(address user) public view returns (uint256) {
        uint256 calculatedBalance = (N[user].mul(T)).div(D);
        //take care of possible rounding errors
        if (calculatedBalance <= T){
            return calculatedBalance;
        } else {
            return T;
        }
    }

    function deposit(address tokenIn, uint256 amount) public nonReentrant {
        require(amount > 0, "amount must be greater than 0");
        require(currentToken == tokenIn, "wrong token");
        address user = msg.sender;
        if (T == 0) {
            D = amount;
            N[user] = amount;
        } else {
            D = D.mul(T.add(amount)).div(T);
            N[user] = N[user].add((D.mul(amount)).div(T.add(amount)));
        }
        T = T.add(amount);
        IERC20(tokenIn).transferFrom(user, address(this), amount);
    }

    function withdraw() public nonReentrant {
        address user = msg.sender;
        uint256 userBalance = getBalance(user);
        require(userBalance > 0, "no balance");
        if (T.sub(userBalance) == 0) {
            D = 1;
        } else {
            D = D.mul(T.sub(userBalance)).div(T);
        }
        N[user] = 0;
        T = T.sub(userBalance);
        IERC20(currentToken).transfer(msg.sender, userBalance);
    }
    function trade(address tokenToSwapTo, uint256 amtOutMin, uint24 fee) public onlyOwner nonReentrant returns (uint256 amtOut) {
        require(tokenToSwapTo == otherToken, "wrong token"); //verify trigger is correct
        if (T > 0) {
            IV3SwapRouter.ExactInputSingleParams memory params =
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: currentToken,
                    tokenOut: otherToken,
                    fee: fee,
                    recipient: address(this),
                    amountIn: T,
                    amountOutMinimum: amtOutMin,
                    sqrtPriceLimitX96: 0
                });
            amtOut = router.exactInputSingle(params);
            T = amtOut;
            lastTradeTime = block.timestamp;
        }
        (currentToken, otherToken) = (otherToken, currentToken); 
    }
}
