// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";

import {Ownable} from "./Ownable.sol";

import {IDuelPepesWhitelist} from "./IDuelPepesWhitelist.sol";
import {IDuelPepes} from "./IDuelPepes.sol";
import {IDP2} from "./IDP2.sol";

import {IWETH9} from "./IWETH9.sol";

contract DP2Mint is Ownable {
    using SafeERC20 for IERC20;

    uint public maxMints;
    uint public mintCounter;
    uint public startTime;
    uint public endTime;
    uint public mintPrice;
    uint public discountedMintPrice;
    IWETH9 public weth;
    IDuelPepesWhitelist public whitelist;
    IDuelPepes public duelpepes;
    IDP2 public DP2;

    /// @notice Constructor for the UniversalONFT
    /// @param _whitelist whitelist manager
    /// @param _mintPrice price of one mint in ETH
    /// @param _discountedMintPrice price of one mint in ETH if paid using credit
    /// @param _weth address of WETH
    /// @param _maxMints max number of pepes to mint
    constructor(
      address _whitelist,
      uint _mintPrice,
      uint _discountedMintPrice,
      address _weth,
      uint _maxMints
    ) {
        whitelist = IDuelPepesWhitelist(_whitelist);
        mintPrice = _mintPrice;
        discountedMintPrice = _discountedMintPrice;
        weth = IWETH9(_weth);
    }

    /// @notice Mint your ONFT
    function mint(uint256 number, address receiver) external payable {
        require(block.chainid == 42161, "Invalid chain id");
        require(mintCounter <= maxMints, "Sold out");

        uint mintPriceToUse = msg.sender == address(duelpepes) ? discountedMintPrice : mintPrice;

        require(block.timestamp > startTime && block.timestamp < endTime, "Not open");
        require(msg.value >= mintPriceToUse * number, "Insufficient ETH sent for mint");

        if (whitelist.isWhitelistActive()) require(whitelist.isWhitelisted(tx.origin), "Duellor not whitelisted");

        mintCounter += number;

        DP2.mint(number, receiver);
    }

    /// @notice Mint your ONFT using WETH
    function mintUsingWETH(uint256 number, address receiver) external payable {
        uint mintPriceToUse = msg.sender == address(duelpepes) ? discountedMintPrice : mintPrice;

        uint amount = mintPriceToUse * number;

        weth.transferFrom(msg.sender, address(this), amount);

        weth.withdraw(amount);

        this.mint(number, receiver);
    }

    /// @notice Withdraw
    function adminWithdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Set startTime
    function adminSetStartTime(uint time) external onlyOwner {
        startTime = time;
    }

    /// @notice Set endTime
    function adminSetEndTime(uint time) external onlyOwner {
        endTime = time;
    }

    /// @notice Set mint price
    function adminSetMintPrice(uint price) external onlyOwner {
        mintPrice = price;
    }

    /// @notice Set discounted mint price
    function adminSetDiscountedMintPrice(uint price) external onlyOwner {
        discountedMintPrice = price;
    }

    /// @notice Set trusted DuelPepes contract
    function adminSetTrustedDuelPepes(address newAddress) external onlyOwner {
        duelpepes = IDuelPepes(newAddress);
    }

    /// @notice Set trusted DP2 contract
    function adminSetTrustedDP2(address newAddress) external onlyOwner {
        DP2 = IDP2(newAddress);
    }

    receive() external payable {}
}
