// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ITokenStorage.sol";

/**
 * @title TokenStorage - single token pool.
 */
contract TokenStorage is Ownable, ITokenStorage {
    using SafeERC20 for IERC20;

    // @dev Basic ERC20 token.
    IERC20 public override token;

    // @dev Initialize contract, set basic token.
    constructor(IERC20 _token) {
        require(address(token) == address(0), "TokenStorage: ZERO_ADDRESS");
        token = _token;
    }

    // @dev Approve token to account.
    function approve(address _spender, uint256 _amount) external onlyOwner {
        token.approve(_spender, _amount);
    }

    // @dev Charge approved tokens, alternative method for <IERC20.transferFrom>
    function charge(uint256 _amount) external {
        uint256 currentAllowance = token.allowance(address(this), msg.sender);

        require(currentAllowance >= _amount, "ERC20: transfer amount exceeds allowance");

        token.safeDecreaseAllowance(msg.sender, _amount);
        token.safeTransfer(msg.sender, _amount);
    }

    // @dev Interface for farming/staking. Similar to {TokenStorage-charge}.
    function charge(address _to, uint256 _amount) external {
        uint256 currentAllowance = token.allowance(address(this), msg.sender);

        require(currentAllowance >= _amount, "ERC20: transfer amount exceeds allowance");

        token.safeDecreaseAllowance(msg.sender, _amount);
        token.safeTransfer(_to, _amount);
    }

    // @dev Send tokens to account.
    function send(address _account, uint256 _amount) external onlyOwner {
        token.safeTransfer(_account, _amount);
    }

    // @dev Send another ERC20 tokens.
    function sendAnotherToken(IERC20 _token, address _account, uint256 _amount) external onlyOwner {
        _token.safeTransfer(_account, _amount);
    }

    // @dev Token allowance.
    function allowance(address _spender) external view returns (uint256 balance) {
        balance = token.allowance(address(this), _spender);
    }

    // @dev Get this token balance.
    function getBalance() external view returns (uint256 balance) {
        balance = token.balanceOf(address(this));
    }
}

