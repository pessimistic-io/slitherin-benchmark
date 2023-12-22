// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Owned} from "./Owned.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Controller} from "./Controller.sol";
import {Token} from "./Token.sol";

// Two-step minting process for added security.
// 1. Minter mints tokens to the vault.
// 2. Owner distributes tokens to users.
contract Minter is Owned {
    using SafeTransferLib for ERC20;

    mapping(address user => uint256 shares) public mintedShares;

    Token public immutable token;
    Controller public immutable controller;
    address public minter;
    address[] public users;

    event SetMinter(address indexed user);
    event Minted(address indexed user, uint256 amount);

    error NotMinter();

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    constructor(Token _token, Controller _controller) Owned(msg.sender) {
        token = _token;
        controller = _controller;
    }

    function mintFor(address user, uint256 amount) external onlyMinter {
        users.push(user);
        mintedShares[user] += controller.mintToVault(user, amount);
        emit Minted(user, amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit SetMinter(_minter);
    }

    function distribute(uint256 count) external onlyOwner {
        uint256 n = users.length;
        uint256 to = n - count;
        for (uint256 i = n - 1; i >= to; i--) {
            address user = users[i];
            uint256 shares = mintedShares[user];
            if (shares > 0) {
                token.transferShares(user, shares);
                mintedShares[user] = 0;
            }
            users.pop();
        }
    }

    function transfer(address to, uint256 amount) external onlyOwner {
        ERC20(address(token)).safeTransfer(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        token.burn(amount);
    }
}

