// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./IFuel.sol";
import "./IUniswapV2Router.sol";

contract FuelPresale is Ownable, ReentrancyGuard {
    // ====== EVENTS ====== //

    event BoughtPresale(uint256 ethAmount, uint256 tokensAmount);
    event AddedLiquidity(uint256 ethAmount, uint256 tokensAmount);

    // ====== STORAGE ====== //

    uint256 public immutable startPresaleTime;
    uint256 public immutable startPublicTime;
    uint256 public immutable endTime;

    uint256 public immutable whitelistPresaleDuration = 1 days;
    uint256 public immutable overallPresaleDuration = 2 days;
    uint256 public immutable claimDelayAfterPresale = 1 hours;

    mapping(address => uint256) public ethSpent;
    mapping(address => uint256) public tokensToClaim;
    uint256 public softCap = 20 ether;
    uint256 public hardCap = 200 ether;
    uint256 public maxPerWallet = 10 ether;
    uint256 public presalePrice = 2250 * 1e18;
    uint256 public whitelistHardCap = 40 ether;
    uint256 public whitelistMaxPerWallet = 0.5 ether;
    uint256 public whitelistPresalePrice = 2770 * 1e18;
    mapping(address => bool) public isWhitelisted;

    uint256 public totalEthRaised = 0;
    uint256 public totalTokensSold = 0;

    uint256 public unclaimedTokens = 0;

    IFuel public immutable fuel;
    IUniswapV2Router02 public router;

    address public treasury;

    bool public liquidityAdded = false;

    // ====== CONSTRUCTOR ====== //

    constructor(uint256 _startTime, IFuel _fuel, IUniswapV2Router02 _router) {
        startPresaleTime = _startTime;
        startPublicTime = _startTime + whitelistPresaleDuration;
        endTime = _startTime + overallPresaleDuration;
        fuel = _fuel;
        router = _router;
    }

    // ====== PUBLIC FUNCTIONS ====== //

    function buyPresale() external payable {
        require(block.timestamp >= startPresaleTime && block.timestamp <= endTime, "Not active");
        require(msg.sender == tx.origin, "No contracts");
        require(msg.value > 0, "Zero amount");
        uint256 tokensPerEth = presalePrice;
        if (block.timestamp < startPublicTime) {
            // whitelist presale
            require(isWhitelisted[msg.sender], "Not whitelisted");
            require(ethSpent[msg.sender] + msg.value <= whitelistMaxPerWallet, "Over wallet limit");
            require(totalEthRaised + msg.value <= whitelistHardCap, "Amount over limit");
            tokensPerEth = whitelistPresalePrice;
        } else {
            // public presale
            require(ethSpent[msg.sender] + msg.value <= maxPerWallet, "Over wallet limit");
            require(totalEthRaised + msg.value <= hardCap, "Amount over limit");
        }

        uint256 tokensSold = (msg.value * tokensPerEth) / 1e18;

        ethSpent[msg.sender] += msg.value;
        tokensToClaim[msg.sender] += tokensSold;

        totalEthRaised += msg.value;
        totalTokensSold += tokensSold;
        unclaimedTokens += tokensSold;

        emit BoughtPresale(msg.value, tokensSold);
    }

    function claim() external {
        require(block.timestamp > endTime + claimDelayAfterPresale, "Not claimable");
        require(totalEthRaised >= softCap, "SoftCap was NOT reached");
        require(tokensToClaim[msg.sender] > 0, "No amount claimable");

        uint256 tokensAmount = tokensToClaim[msg.sender];

        unclaimedTokens -= tokensAmount;
        tokensToClaim[msg.sender] = 0;
        fuel.transferUnderlying(msg.sender, tokensAmount);
    }

    function refund() external {
        require(block.timestamp > endTime + claimDelayAfterPresale, "Presale not ended yet");
        require(totalEthRaised < softCap, "SoftCap was reached, no refund possible");
        require(ethSpent[msg.sender] > 0, "No ETH spent");

        uint256 refundEth = ethSpent[msg.sender];

        ethSpent[msg.sender] = 0;
        payable(msg.sender).transfer(refundEth);
    }

    // ====== ONLY OWNER ====== //

    function setHardCap(uint256 _hardCap) external onlyOwner {
        hardCap = _hardCap;
    }

    function setRouter(IUniswapV2Router02 _router) external onlyOwner {
        router = _router;
    }

    function setIsWhitelisted(address[] calldata wallets) external onlyOwner {
        for (uint256 i = 0; i < wallets.length; i++) {
            isWhitelisted[wallets[i]] = true;
        }
    }

    function addLiquidity() external nonReentrant onlyOwner {
        require(block.timestamp > endTime, "Not finished");
        require(!liquidityAdded, "Already added");
        require(totalEthRaised >= softCap, "SoftCap was NOT reached");

        fuel.approve(address(router), uint256(2 ** 256 - 1));
        uint256 totalAmount = address(this).balance;
        payable(owner()).transfer((totalAmount * 20) / 100);

        uint256 ethAmount = totalAmount - ((totalAmount * 20) / 100);
        uint256 tokenAmount = (((ethAmount * presalePrice) / 1e18) * 80) / 100;
        router.addLiquidityETH{value: ethAmount}(address(fuel), tokenAmount, 1, 1, msg.sender, type(uint256).max);
        emit AddedLiquidity(ethAmount, tokenAmount);
        liquidityAdded = true;

        uint256 totalBurnedTokens = fuel.balanceOf(address(this)) - totalTokensSold;
        fuel.burn(totalBurnedTokens);
    }
}

