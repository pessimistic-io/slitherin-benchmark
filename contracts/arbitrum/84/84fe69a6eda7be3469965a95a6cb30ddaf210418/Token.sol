// SPDX-License-Identifier: MIT

// Website: https://www.pekachu.vip/

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Context.sol";
import "./SafeMath.sol";
import "./console.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256 totalSupply);

    function name() external view returns (string memory name);

    function symbol() external view returns (string memory symbol);

    function decimals() external view returns (uint8 decimals);

    /// @param _owner The address from which the balance will be retrieved
    /// @return balance the balance
    function balanceOf(address _owner) external view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transfer(
        address _to,
        uint256 _value
    ) external returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return success Whether the approval was successful or not
    function approve(
        address _spender,
        uint256 _value
    ) external returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return remaining Amount of remaining tokens allowed to spent
    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;
}

contract Token is IERC20, Context, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public _totalSupply;
    string public _name;
    uint8 public _decimals;
    string public _symbol;

    uint8 public communityFee = 5;
    uint8 private denominator = 100;
    mapping(address => bool) private feeFreed;

    address public communityAddress;
    address public uniswapV2Pair;

    IUniswapV2Router02 public uniswapV2Router;
    bool private inSwap;

    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol,
        address _swapRouterAddress,
        address _communityAddress
    ) {
        _name = _tokenName;
        _symbol = _tokenSymbol;
        _decimals = _decimalUnits;
        _totalSupply = _initialAmount * 10 ** _decimals;
        balances[_msgSender()] = _totalSupply;
        uniswapV2Router = IUniswapV2Router02(_swapRouterAddress);
        // uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
        //     address(this),
        //     uniswapV2Router.WETH()
        // );
        communityAddress = _communityAddress;

        feeFreed[address(this)] = true;
        feeFreed[_msgSender()] = true;
        feeFreed[communityAddress] = true;

        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    receive() external payable {}

    function createPair(address weth) external onlyOwner {
        if (weth == address(0x0)) {
            weth = uniswapV2Router.WETH();
        }
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            weth
        );
    }

    function setFeeFreed(address account, bool isFeeFreed) external onlyOwner {
        feeFreed[account] = isFeeFreed;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function checkFee(
        address from,
        address to
    ) internal view returns (uint8 fee) {
        if (feeFreed[from] || feeFreed[to]) {
            return 0;
        }
        if (to == uniswapV2Pair) {
            return communityFee;
        }
        return 0;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: trasnfer to zero address");
        require(amount > 0, "ERC20: transfer amount is zero");
        uint8 fee = checkFee(from, to);

        balances[from] = balances[from].sub(amount);
        if (fee == 0) {
            balances[to] = balances[to].add(amount);
            emit Transfer(from, to, amount);
            return;
        }
        if (from != uniswapV2Pair) {
            transferToCommunity(balances[address(this)]);
        }

        uint256 totalFeeAmount = amount.mul(communityFee).div(denominator);
        balances[address(this)] = balances[address(this)].add(totalFeeAmount);
        emit Transfer(from, address(this), totalFeeAmount);

        uint256 toAmount = amount.sub(totalFeeAmount);
        balances[to] = balances[to].add(toAmount);
        emit Transfer(from, to, toAmount);
    }

    function transferToCommunity(uint256 amount) internal {
        if (!inSwap && amount > 0) {
            inSwap = true;
            swapTokensForEth(amount, address(this));
            uint256 ethBalance = address(this).balance;
            payable(communityAddress).transfer(ethBalance);
            inSwap = false;
        }
    }

    function swapTokensForEth(uint256 amount, address to) internal {
        _approve(address(this), address(uniswapV2Router), amount);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            to,
            address(0x0),
            block.timestamp
        );
    }

    function transfer(
        address _to,
        uint256 _value
    ) public override returns (bool success) {
        _transfer(_msgSender(), _to, _value);
        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool success) {
        _transfer(_from, _to, _value);
        _approve(
            _from,
            _msgSender(),
            allowances[_from][_msgSender()].sub(
                _value,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function balanceOf(
        address _owner
    ) public view override returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(
        address _spender,
        uint256 _value
    ) public override returns (bool success) {
        _approve(msg.sender, _spender, _value);
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function allowance(
        address _owner,
        address _spender
    ) public view override returns (uint256 remaining) {
        return allowances[_owner][_spender];
    }

    function withdraw(address token, uint256 amount) public onlyOwner {
        if (token == address(0x0)) {
            uint256 ethBalance = address(this).balance;
            if (amount == 0 || amount > ethBalance) {
                amount = ethBalance;
            }
            payable(_msgSender()).transfer(amount);
            return;
        }
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (amount == 0 || amount > tokenBalance) {
            amount = tokenBalance;
        }
        IERC20(token).transfer(_msgSender(), amount);
    }

    function setCommunityFee(uint8 fee) public onlyOwner {
        require(fee <= 10, "at most 10% for community fee");
        communityFee = fee;
    }
}

