// SPDX-License-Identifier: MIT

pragma solidity ^0.7.5;

/*
*
* MIT License
* ===========
*
* Copyright Mizu (c) 2020
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import "./SafeMath.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";
import "./IPancakePair.sol";
import "./IPancakeRouter02.sol";
import "./ISafeSwapBNB.sol";
import "./ZapHelper.sol";
import "./IZap.sol";

contract OmniZap is Ownable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    IBEP20 public WNAT; // WRAPPED NATIVE FOR DEPLOYED CHAIN
    address public safeSwapBNB;

    constructor ( 
        address _WNAT
    ) {
        require( _WNAT != address(0) );
        WNAT = IBEP20(_WNAT);
        safeSwapBNB = _WNAT;
        IBEP20(WNAT).approve(_WNAT, uint(-1));
    }

    /* ========== EVENTS ========== */

    event ZapETH(address _to, address _router);
    event ZapToken(address _from, uint amount, address _to, address _router);
    event ZapOut(address _from, uint amount, address _router);
    event TokenAdded(address token);
    event TokenRemoved(address token);
    event SetRoute(address asset, address route);

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private notLP;
    mapping(address => address) private routePairAddresses;
    mapping (address => bool) Blacklist;
    address[] public tokens;
    uint256 public ListingFee;
    address public ListingToken;

    receive() external payable {}


    /* ========== View Functions ========== */

    function isLP(address _address) public view returns (bool) {
        return !notLP[_address];
    }

    function routePair(address _address) external view returns(address) {
        return routePairAddresses[_address];
    }

    /* ========== External Functions ========== */

    function zapInToken(address _from, uint amount, address _to, address _router) external {
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, _router);

        if (isLP(_to)) {
            IPancakePair pair = IPancakePair(_to);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (_from == token0 || _from == token1) {
                // swap half amount for other
                address other = _from == token0 ? token1 : token0;
                _approveTokenIfNeeded(other, _router);
                uint sellAmount = amount.div(2);
                uint otherAmount = _swap(_from, sellAmount, other, address(this), _router);
                pair.skim(address(this));
                IPancakeRouter02(_router).addLiquidity(_from, other, amount.sub(sellAmount), otherAmount, 0, 0, msg.sender, block.timestamp);
            } else {
                uint bnbAmount = _from == address(WNAT) ? _safeSwapToBNB(amount) : _swapTokenForBNB(_from, amount, address(this), _router);
                _swapBNBToLP(_to, bnbAmount, msg.sender, _router);
            }
        } else {
            _swap(_from, amount, _to, msg.sender, _router);
        }
        emit ZapToken(_from, amount, _to, _router);
    }

    function zapIn(address _to, address _router) external payable {
        _swapBNBToLP(_to, msg.value, msg.sender, _router);
        emit ZapETH(_to, _router);
    }

    function zapOut(address _from, uint amount, address _router) external {
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, _router);

        if (!isLP(_from)) {
            _swapTokenForBNB(_from, amount, msg.sender, _router);
        } else {
            IPancakePair pair = IPancakePair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();

            if (pair.balanceOf(_from) > 0) {
                pair.burn(address(this));
            }

            if (token0 == address(WNAT) || token1 == address(WNAT)) {
                IPancakeRouter02(_router).removeLiquidityETH(token0 != address(WNAT) ? token0 : token1, amount, 0, 0, msg.sender, block.timestamp);
            } else {
                IPancakeRouter02(_router).removeLiquidity(token0, token1, amount, 0, 0, msg.sender, block.timestamp);
            }
        }
        emit ZapOut(_from, amount, _router);
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token, address _router) private {
        if (IBEP20(token).allowance(address(this), address(_router)) == 0) {
            IBEP20(token).safeApprove(address(_router), uint(- 1));
        }
    }

    function _swapBNBToLP(address flip, uint amount, address receiver, address _router) private {
        if (!isLP(flip)) {
            _swapBNBForToken(flip, amount, receiver, _router);
        } else {
            IPancakePair pair = IPancakePair(flip);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == address(WNAT) || token1 == address(WNAT)) {
                address token = token0 == address(WNAT) ? token1 : token0;
                uint swapValue = amount.div(2);
                uint tokenAmount = _swapBNBForToken(token, swapValue, address(this), _router);

                _approveTokenIfNeeded(token, _router);
                pair.skim(address(this));
                IPancakeRouter02(_router).addLiquidityETH{value : amount.sub(swapValue)}(token, tokenAmount, 0, 0, receiver, block.timestamp);
            } else {
                uint swapValue = amount.div(2);
                uint token0Amount = _swapBNBForToken(token0, swapValue, address(this), _router);
                uint token1Amount = _swapBNBForToken(token1, amount.sub(swapValue), address(this), _router);

                _approveTokenIfNeeded(token0, _router);
                _approveTokenIfNeeded(token1, _router);
                pair.skim(address(this));
                IPancakeRouter02(_router).addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
            }
        }
    }

    function _swapBNBForToken(address token, uint value, address receiver, address _router) private returns (uint) {     
        address[] memory path;

        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = address(WNAT);
            path[1] = routePairAddresses[token];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = address(WNAT);
            path[1] = token;
        }

        uint[] memory amounts = IPancakeRouter02(_router).swapExactETHForTokens{value : value}(0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForBNB(address token, uint amount, address receiver, address _router) private returns (uint) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = address(WNAT);
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = address(WNAT);
        }

        uint[] memory amounts = IPancakeRouter02(_router).swapExactTokensForETH(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint amount, address _to, address receiver, address _router) private returns (uint) {
        address intermediate = routePairAddresses[_from];
        if (intermediate == address(0)) {
            intermediate = routePairAddresses[_to];
        }

        address[] memory path;
        if (intermediate != address(0) && (_from == address(WNAT) || _to == address(WNAT))) {

            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (intermediate != address(0) && (_from == intermediate || _to == intermediate)) {

            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] == routePairAddresses[_to]) {

            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (routePairAddresses[_from] != address(0) && routePairAddresses[_to] != address(0) && routePairAddresses[_from] != routePairAddresses[_to]) {

            path = new address[](5);
            path[0] = _from;
            path[1] = routePairAddresses[_from];
            path[2] = address(WNAT);
            path[3] = routePairAddresses[_to];
            path[4] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] != address(0)) {

            path = new address[](4);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = address(WNAT);
            path[3] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_to] != address(0)) {

            path = new address[](4);
            path[0] = _from;
            path[1] = address(WNAT);
            path[2] = intermediate;
            path[3] = _to;
        } else if (_from == address(WNAT) || _to == address(WNAT)) {

            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {

            path = new address[](3);
            path[0] = _from;
            path[1] = address(WNAT);
            path[2] = _to;
        }

        uint[] memory amounts = IPancakeRouter02(_router).swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _safeSwapToBNB(uint amount) private returns (uint) {
        require(IBEP20(WNAT).balanceOf(address(this)) >= amount, "Zap: Not enough WNAT balance");
        require(safeSwapBNB != address(0), "Zap: safeSwapBNB is not set");
        uint beforeBNB = address(this).balance;
        ISafeSwapBNB(safeSwapBNB).withdraw(amount);
        return (address(this).balance).sub(beforeBNB);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    //setRoutePair
    function setRoutePairAddress(address asset, address route) external onlyOwner {
        routePairAddresses[asset] = route;
        emit SetRoute(asset, route);
    }

    //set new token
    function setNotLPOwner(address token) external onlyOwner {
        bool needPush = notLP[token] == false;
        notLP[token] = true;
        if (needPush) {
            tokens.push(token);
        }
        emit TokenAdded(token);
    }

        function setBlacklist(address token, bool _state) external onlyOwner{
            Blacklist[token] = _state;
        }

    function payListing() internal {
        if (ListingFee > 0){
            require (IBEP20(ListingToken).balanceOf(msg.sender) >= ListingFee);
            IBEP20(ListingToken).transferFrom(msg.sender, address(this), ListingFee);
        }
    }


    function setNotLP(address token) external {
        require (ZapHelper.isToken(token), "Token = LP");
        require (!Blacklist[token], "Blacklisted");
        payListing();
        bool needPush = notLP[token] == false;
        notLP[token] = true;
        if (needPush) {tokens.push(token);}
        emit TokenAdded(token);
    }

    function setListingFee(uint256 _amount) external onlyOwner {
        ListingFee = _amount;        
    }

    function setListingToken(address _token) external onlyOwner {
        ListingToken = _token;
    }
  

    //remove old token
    function removeToken(uint i) external onlyOwner {
        address token = tokens[i];
        notLP[token] = false;
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();
        emit TokenRemoved(tokens[i]);
    }

    function sweep() external onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint amount = IBEP20(token).balanceOf(address(this));
            if (amount > 0) {
                IBEP20(token).transfer(msg.sender, amount);
            }
        }
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function zapOutFor(address _from, uint amount, address _router) internal returns(uint amt1, uint amt2){
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, _router);

        if (!isLP(_from)) {
            _swapTokenForBNB(_from, amount, msg.sender, _router);
        } else {
            IPancakePair pair = IPancakePair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();

            if (pair.balanceOf(_from) > 0) {
                (amt1, amt2) = pair.burn(address(this));
            }

            if (token0 == address(WNAT) || token1 == address(WNAT)) {
                (amt1, amt2) = IPancakeRouter02(_router).removeLiquidityETH(token0 != address(WNAT) ? token0 : token1, amount, 0, 0, address(this), block.timestamp);
            } else {
                (amt1, amt2) = IPancakeRouter02(_router).removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);
            }
        }
        emit ZapOut(_from, amount, _router);
        return (amt1, amt2);
    }

    function swapLpToNative(address _lp, uint _amount, address _router) internal returns (uint){
        (uint amt1, uint amt2) = zapOutFor(_lp, _amount, _router); //ZAPOUT THE LP
        IPancakePair pair = IPancakePair(_lp);
        address token0 = pair.token0(); // GET TOKEN 0 ADDR
        address token1 = pair.token1(); // GET TOKEN 1 ADDR
        uint natSum;
            //SWAP ALL TO WNAT
            if (token0 == address(WNAT))
            {   
                _approveTokenIfNeeded(token1, _router);
                uint amtSwap = _swap(token1, amt1, address(WNAT), address(this), _router);
                _safeSwapToBNB(amtSwap);
                natSum = (amtSwap + amt2);
            }
            if (token1 == address(WNAT))
            {   
                _approveTokenIfNeeded(token0, _router);
                uint amtSwap = _swap(token0, amt1, address(WNAT), address(this), _router);
                _safeSwapToBNB(amtSwap);
                natSum = (amtSwap + amt2);
            }
            else {
                _approveTokenIfNeeded(token0, _router);
                _approveTokenIfNeeded(token1, _router);
                uint amtSwap = _swap(token0, amt1, address(WNAT), address(this), _router);
                amtSwap += _swap(token1, amt2, address(WNAT), address(this), _router);
                _safeSwapToBNB(amtSwap);
                natSum = amtSwap;
            }
        return natSum;
    }

    function zapOutTo(address _lp, uint _amount, address _to, address _routerFrom, address _routerTo) external {
        uint balanceBefore = address(this).balance;
        swapLpToNative(_lp, _amount, _routerFrom);
        uint payOut = ((address(this).balance).sub(balanceBefore));
        require(address(this).balance > balanceBefore);
            if(_to == address(0) && _routerTo == address(0)){
                payable(msg.sender).transfer(payOut);
            }
            else{
                if(isLP(_to)){
                    IZap(address(this)).zapIn{value: payOut}(_to, _routerTo);
                }
                if(!isLP(_to)){
                    _swapBNBForToken(_to, payOut, msg.sender, _routerTo);
                }
            }
    } 
}
