// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SlippageERC20} from "./SlippageERC20.sol";
import {IPair} from "./IPair.sol";

interface ERC20Interface {
    function balanceOf(address user) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to,uint256 amount) external returns(bool);
}

library SafeToken {

    function balance(address token, address user) internal view returns (uint256) {
        return ERC20Interface(token).balanceOf(user);
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
    }

}


contract Wallet {
    function safeTransfer(address token, address to, uint256 value) external {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
    }
}

contract AiETH is SlippageERC20 {

    using SafeToken for address;
    
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    /// @notice the rebase lp address
    address public lp;
    address public usdt;

    /// @notice lp pool
    address public lpPool;
    /// @notice node pool
    address public nodePool;
    /// @notice fund pool
    address public fundPool;

    Wallet public immutable wallet;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        _mint(msg.sender, _totalSupply);
        _setSlipWhite(msg.sender, true);
        _initERC20_();
        wallet = new Wallet();
    }

    function setLp(address _lp) external onlyCaller(OWNER) {
        lp = _lp;
        IPair iLp = IPair(_lp);
        address token = iLp.token0();
        usdt = token == address(this) ? iLp.token1() : token;
    }

    function setAddress(
        address _lpPool,
        address _nodePool,
        address _fundPool
    ) external onlyCaller(OWNER) {
        lpPool = _lpPool;
        nodePool = _nodePool;
        fundPool = _fundPool;
        _setSlipWhite(_lpPool, true);
        _setSlipWhite(_nodePool, true);
        _setSlipWhite(_fundPool, true);
    }

    function _transferSlippage(address _from, address _to, uint256, uint _fee) internal override {
        // buy or burn lp
        if ( lp != address(0) ) {
            if ( _from == lp ) {
                _totalSupply -= _fee;
                emit Transfer(_from, address(0), _fee);
            }
            // sell or mint lp
            else if ( _to == lp ) {
                emit Transfer(_from, address(this), _fee);
                _sell(_fee);
                uint _perFee = ERC20Interface(usdt).balanceOf(address(wallet));
                uint _perFee3 = _perFee / 3;
                wallet.safeTransfer(usdt, lpPool, _perFee3);
                wallet.safeTransfer(usdt, nodePool, _perFee3);
                wallet.safeTransfer(usdt, fundPool, _perFee - _perFee3 * 2);
            }
        }
    }

    /// @notice sell AiETH
    function _sell(uint _aiAmount) internal {

        IPair iLp = IPair(lp);
        (uint reserveAi, uint reserveUsdt, ) = iLp.getReserves();
        if (address(this) > usdt) {
            (reserveAi, reserveUsdt) = (reserveUsdt, reserveAi);
        }

        _balanceOf[lp] += _aiAmount;
        emit Transfer(address(this), lp, _aiAmount);
        uint amount0Out = uint(0);
        uint amount1Out = getAmountOut(_aiAmount, reserveAi, reserveUsdt, 9970);
        if (address(this) > usdt) {
            (amount0Out, amount1Out) = (amount1Out, amount0Out);
        }
        iLp.swap(amount0Out, amount1Out, address(wallet), new bytes(0));
    }

    /// given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint feeE4
    ) internal pure returns (uint amountOut) {
        uint amountInWithFee = amountIn * feeE4;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
