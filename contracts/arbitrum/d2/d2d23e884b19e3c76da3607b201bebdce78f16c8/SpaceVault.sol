// SPDX-License-Identifier: MIT
// Copyright (c) 2021 TrinityLabDAO

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
pragma solidity 0.8.7;

import "./ERC20Burnable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./WrapedTokenDeployer.sol";
import "./IVault.sol";
import "./OnlyGovernance.sol";
import "./OnlyBridge.sol";


/**
 * @title Space Vault
 */
contract SpaceVault is  IVault,
                        WrapedTokenDeployer,
                        ReentrancyGuard,
                        OnlyGovernance, 
                        OnlyBridge
{
    using SafeERC20 for IERC20;

    event Deposit(
        address indexed token,
        address indexed sender,
        uint256 amount
    );

    event Burn(
        address indexed token,
        address indexed sender,
        uint256 amount
    );

    event Withdraw(
        address indexed sender,
        address indexed token,
        address indexed to,
        uint256 amount
    );

    event Mint(
        address token_address,
        address dst_address,
        uint256 amount
    );

    address public bridge;
    
    function deposit(
        address token,
        address from,
        uint256 amount
    ) nonReentrant onlyBridge external override {
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit Deposit(from, token, amount);
    }

    function withdraw(
        address token,
        address to,
        uint256 amount
    ) nonReentrant onlyBridge external override {
        require(IERC20(token).balanceOf(address(this)) > amount, "Vault token balance to low");
        IERC20(token).safeTransfer(to, amount);
        emit Withdraw(msg.sender, token, to, amount);
    }

    function deploy(
        string memory name,
        string memory symbol,
        uint256 origin,
        bytes memory origin_hash,
        uint8 origin_decimals
    ) nonReentrant onlyBridge external override returns(address){
        return _deploy(name, symbol, origin, origin_hash, origin_decimals);
    }

    function mint(
        address token_address,
        address to,
        uint256 amount
    ) nonReentrant onlyBridge external override {
        WrapedToken(token_address).mint(to, amount);
        emit Mint(token_address, to, amount);
    }

    function burn(
        address token,
        address from,
        uint256 amount
    ) nonReentrant onlyBridge external override {
        ERC20Burnable(token).burnFrom(from, amount); 
        emit Burn(from, token, amount);
    }

    function tokenTransferOwnership(address token, address new_vault) nonReentrant onlyGovernance external {
        WrapedToken(token).transferOwnership(new_vault);
    }

    /**
     * @notice Balance of token in vault.
     */
    function getBalance(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Removes tokens accidentally sent to this vault.
     */
    function sweep(
        address token,
        uint256 amount,
        address to
    ) onlyGovernance external {
        IERC20(token).safeTransfer(to, amount);
    }
}
