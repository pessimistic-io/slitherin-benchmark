// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Owned} from "./Owned.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Controller} from "./Controller.sol";
import {Token} from "./Token.sol";

/// @notice Two-step minting contract.
contract Minter is Owned {
    using SafeTransferLib for ERC20;

    Token public immutable token;
    Controller public immutable controller;
    address public minter;
    /// @notice The list of accounts that are awaiting funds.
    address[] public accounts;

    /// @notice The amount of shares minted for each account.
    mapping(address account => uint256 shares) public mintedShares;

    event SetMinter(address indexed account);
    event Minted(address indexed account, uint256 amount);

    error NotMinter();

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    constructor(Token _token, Controller _controller) Owned(msg.sender) {
        token = _token;
        controller = _controller;
    }

    /// @notice Mints tokens and holds them in the contract.
    function mintFor(address account, uint256 amount) external onlyMinter {
        accounts.push(account);
        /// @dev Tokens are minted to address(this).
        mintedShares[account] += controller.mintFor(account, amount);
        emit Minted(account, amount);
    }

    /// @notice Sets the minter.
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit SetMinter(_minter);
    }

    /// @notice Distributes minted tokens to accounts.
    function distribute(uint256 count) external onlyOwner {
        uint256 n = accounts.length;
        uint256 to = n - count;
        for (uint256 i = n - 1; i >= to; i--) {
            address account = accounts[i];
            uint256 shares = mintedShares[account];
            if (shares > 0) {
                token.transferShares(account, shares);
                mintedShares[account] = 0;
            }
            accounts.pop();
        }
    }

    /// @notice Transfers tokens out of the contract.
    function transfer(address to, uint256 amount) external onlyOwner {
        ERC20(address(token)).safeTransfer(to, amount);
    }

}

