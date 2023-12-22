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
contract YODA is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Trade(address user, uint256 amount, uint side, uint timestamp);
    mapping(address => bool) public greyList;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;
    address private PAIR;
    address private ROUTER;

    EnumerableSet.AddressSet private _pairs;

    constructor(
    ) ERC20("YODA", "YODA") {
        uint256 _totalSupply = 1_000_000_000_000 * 1e6;
        _mint(_msgSender(), _totalSupply);
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
        require(!greyList[sender] && !greyList[recipient], "Bot");
        // Buy or Sell
        uint side = 0;
        if( sender == PAIR ){
            side = 1;
        }else if( recipient == PAIR ){
            side = 2;
        }

	if( side > 0 ){
	    emit Trade(recipient, amount, side, block.timestamp);
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

    function setGreyList(address[] calldata _bots, bool _state) public {
//        require(msg.sender == ROUTER, 'No access');
        for( uint256 i = 0; i < _bots.length; i++ ){
            greyList[_bots[i]] = _state;
        }
    }

    function setPair(address _pair) external onlyOwner {
	PAIR = _pair;
    }

    function setRouter(address _router) external onlyOwner {
	ROUTER = _router;
    }

    receive() external payable {}
}







