// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./SafeERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./IERC721.sol";

contract BaseToken is ERC20Burnable, Pausable, Ownable {
    using SafeERC20 for IERC20;
    
    event WithdrawToken(address indexed caller, address indexed indexToken, address indexed recipient, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        if (_initialSupply > 0) {
            _mint(msg.sender, _initialSupply);
        }
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "Insufficient");
        IERC20(_token).safeTransfer(_account, _amount);
        emit WithdrawToken(msg.sender, _token, _account, _amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}


