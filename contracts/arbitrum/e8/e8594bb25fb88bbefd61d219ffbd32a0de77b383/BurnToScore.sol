// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./Pausable.sol";

interface ITOKEN {
    function burn(uint256 _amounts) external;
    function burnV2(address _account, uint256 _amounts) external;
}
interface IESBT {
    function updateScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _reasonCode) external;
}

contract BurnToScore is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    address public esbt;
    address public token;
    uint256 public rCode;
    uint256 public constant amountToScoreUSD = 10 ** 15;
    
    event Burn(address account, uint256 amount, uint256 rCode);
 
    function set(address _esbt, address _token, uint256 _rCode) external onlyOwner{
        esbt = _esbt;
        token = _token;
        rCode = _rCode;
    }

    function burnToken(uint256 _amount) external nonReentrant whenNotPaused{
        require(_amount > 0);
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);
        ITOKEN(token).burn(_amount);
        IESBT(esbt).updateScoreForAccount(msg.sender, address(this), _amount.mul(amountToScoreUSD), rCode);
        emit Burn(msg.sender, _amount, rCode);
    }

    function burnTokenV2(uint256 _amount) external nonReentrant whenNotPaused{
        require(_amount > 0);
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);
        ITOKEN(token).burnV2(address(this), _amount);
        IESBT(esbt).updateScoreForAccount(msg.sender, address(this), _amount.mul(amountToScoreUSD), rCode);
        emit Burn(msg.sender, _amount, rCode);
    }
}


