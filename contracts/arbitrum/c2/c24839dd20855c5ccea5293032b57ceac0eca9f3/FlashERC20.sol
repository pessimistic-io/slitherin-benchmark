// SPDX-License-Identifier: MIT
//  _    _ _           _            _
// | |  | | |         | |          | |
// | |  | | |__   __ _| | ___      | | ___   __ _ _ __  ___
// | |/\| | '_ \ / _` | |/ _ \     | |/ _ \ / _` | '_ \/ __|
// \  /\  / | | | (_| | |  __/  _  | | (_) | (_| | | | \__ \
//  \/  \/|_| |_|\__,_|_|\___| (_) |_|\___/ \__,_|_| |_|___/
//
//  Whale.loans Flashmintable token wrappers
//
//  https://Whale.Loans
//
pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IBorrower.sol";
import "./FlashmintFactory.sol";

// @title FlashERC20
// @notice A simple ERC20 wrapper with flash-mint functionality.
contract FlashERC20 is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    // internal vars
    uint256 public _depositLimit = 500e22;
    mapping(address => bool) public whitelistAddr;

    // constants
    uint256 private constant oneEth = 1e18;

    // contracts
    ERC20 public immutable underlying;
    FlashmintFactory public immutable factory;

    // Events with parameter names that are consistent with the WETH9 contract.
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    event FlashMint(address indexed src, uint256 wad);
    event NewDepositLimit(uint256 dpl);
    event WhitelistUpdate(address addr, bool status);
    
    constructor(ERC20 _underlying)
        ERC20(
            string(abi.encodePacked("Flash ", _underlying.name())),
            string(abi.encodePacked("f", _underlying.symbol()))
        )
    {
        underlying = _underlying;
        factory = FlashmintFactory(msg.sender);
        _setupDecimals(_underlying.decimals());
    }

    function setWhitelist(address addr, bool status) external onlyOwner {
        whitelistAddr[addr] = status;
        emit WhitelistUpdate(addr, status);
    }

    function setDepositLimit(uint256 value) public onlyOwner {
        _depositLimit = value;
        emit NewDepositLimit(_depositLimit);
    }

    // Mints fERC20 in 1-to-1 correspondence with underlying.
    function deposit(uint256 wad) public {
        underlying.safeTransferFrom(msg.sender, address(this), wad);
        _mint(msg.sender, wad);
        assert(underlying.balanceOf(address(this)) <= _depositLimit);
        emit Deposit(msg.sender, wad);
    }

    // Redeems fERC20 1-to-1 for underlying.
    function withdraw(uint256 wad) public {
        _burn(msg.sender, wad); // reverts if `msg.sender` does not have enough fERC20
        underlying.safeTransfer(msg.sender, wad);
        emit Withdrawal(msg.sender, wad);
    }

    // Allows anyone to mint unbacked flash-underlying as long as it gets burned by the end of the transaction.
    function flashMint(uint256 amount) external nonReentrant {
        require(amount < (type(uint256).max - totalSupply()));

        // calculate fee
        uint256 fee = FlashmintFactory(factory).fee();
        uint256 actualFee = amount.mul(fee).div(oneEth);

        // mint tokens
        _mint(msg.sender, amount);

        // hand control to borrower
        IBorrower(msg.sender).executeOnFlashMint(amount, actualFee);

        // burn tokens
        _burn(msg.sender, amount); // reverts if `msg.sender` does not have enough units of the FMT

        // double-check that all fERC20 is backed by the underlying
        assert(underlying.balanceOf(address(this)) >= totalSupply());

        // send the fee
        if (fee != 0) {
            underlying.safeTransferFrom(msg.sender, address(this), actualFee);
        }

        emit FlashMint(msg.sender, amount);
    }
}

