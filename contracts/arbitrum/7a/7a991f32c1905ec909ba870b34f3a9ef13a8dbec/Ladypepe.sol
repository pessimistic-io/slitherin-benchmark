// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//   ##         ######     #######   ######     #######
//   ##         ##    ##   ##        ##    ##   ##
//   ##         ##    ##   ##        ##    ##   ##
//   ##         ## ####    ######    ## ####    ######
//   ##         ##         ##        ##         ##
//   ##         ##         ##        ##         ##
//   ########   ##         #######   ##         #######
//   Webside: https://ladypepe.xyz
//   twitter: LadyPepeFinance
//   discord: https://discord.com/channels/krvQ6JTpSh

import "./ERC20.sol";
import "./Context.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract Ladypepe is Context, ERC20, Pausable, Ownable {
    uint256 private constant MAX_SUPPLY = 1_000_000_000_000_000_000_000_000_000_000_000; // 1,000,000,000,000,000 tokens with 18 decimals
    uint256 private constant TRANSACTION_FEE = 3; // 3% transaction fee on each transaction

    address private _communityWallet;
    mapping(address => bool) private _excludedFromFees;

    event SentToWrongAddress(address indexed from, address indexed to, uint256 amount);

    constructor(address communityWalletAddress) ERC20("Lady Pepe", "LPEPE") {
        require(communityWalletAddress != address(0), "Ladypepe: community wallet is the zero address");
        _communityWallet = communityWalletAddress;
        _mint(_msgSender(), MAX_SUPPLY);
    }

    function communityWallet() public view returns (address) {
        return _communityWallet;
    }

    function setCommunityWallet(address communityWalletAddress) public onlyOwner {
        require(communityWalletAddress != address(0), "Ladypepe: community wallet is the zero address");
        _communityWallet = communityWalletAddress;
    }

    function transfer(address recipient, uint256 amount) public virtual override whenNotPaused returns (bool) {
        require(recipient != address(0), "Ladypepe: transfer to the zero address");

        uint256 feeAmount = calculateFeeAmount(amount);
        uint256 amountAfterFee = amount - feeAmount;

        _transfer(_msgSender(), recipient, amountAfterFee);
        _transfer(_msgSender(), _communityWallet, feeAmount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override whenNotPaused returns (bool) {
        require(recipient != address(0), "Ladypepe: transfer to the zero address");

        uint256 feeAmount = calculateFeeAmount(amount);
        uint256 amountAfterFee = amount - feeAmount;

        _transfer(sender, recipient, amountAfterFee);
        _transfer(sender, _communityWallet, feeAmount);

        _approve(sender, _msgSender(), allowance(sender, _msgSender()) - amount);

        return true;
    }

    function excludeFromFees(address account) public onlyOwner {
        _excludedFromFees[account] = true;
    }

    function includeInFees(address account) public onlyOwner {
        _excludedFromFees[account] = false;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _excludedFromFees[account];
    }

    function calculateFeeAmount(uint256 amount) private view returns (uint256) {
        if (_excludedFromFees[_msgSender()]) {
            return 0;
        }
        return amount * TRANSACTION_FEE / 100;
    }

}
