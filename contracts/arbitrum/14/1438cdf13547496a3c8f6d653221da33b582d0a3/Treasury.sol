// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Address.sol";

import "./IRouter.sol";
import "./IRewards.sol";

// This contract should be relatively upgradeable = no important state

contract TreasuryV2 {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // Contract dependencies
    address public owner;
    address public router;
    address public trading;
    address public oracle;

    address public distributor;

    mapping(address => uint256) private poolShare; // currency (eth, usdc, etc.) => bps
    mapping(address => uint256) private capPoolShare; // currency => bps
    uint256 private TokenDistributorShare;

    uint256 public constant UNIT = 10 ** 18;

    constructor() {
        owner = msg.sender;
    }

    // Governance methods
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
        oracle = IRouter(router).oracle();
        trading = IRouter(router).trading();
    }

    function setPoolShare(address currency, uint256 share) external onlyOwner {
        poolShare[currency] = share;
    }

    function setCapPoolShare(
        address currency,
        uint256 share
    ) external onlyOwner {
        capPoolShare[currency] = share;
    }

    function setTokenDistShare(uint256 share) external onlyOwner {
        TokenDistributorShare = share;
    }

    function setDistributor(address dist) external onlyOwner {
        distributor = dist;
    }

    uint256 public basisPoint = 10000;
    uint256 public mulPoint = 100;

    function setDistPrecision(uint256 p1, uint256 p2) external onlyOwner {
        basisPoint = p1;
        mulPoint = p2;
    }

    function calculateDistAmount(
        address token
    ) external view returns (uint256, uint256, uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 fraction = TokenDistributorShare;
        uint256 amount = (fraction * balance) / basisPoint;
        return (amount, fraction, balance);
    }

    function fundFeeDistributor(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 fraction = TokenDistributorShare;
        uint256 amount = (fraction * balance) / basisPoint;
        IERC20(token).transfer(distributor, amount);
    }

    function DistributeToProjectPool(
        address currency,
        uint256 amount
    ) external onlyOwner {
        // Contracts from Router
        address capRewards = IRouter(router).getCapRewards(currency);
        // Send capPoolShare to cap-currency rewards contract
        uint256 capReward = (capPoolShare[currency] * amount) / 10 ** 4;
        _transferOut(currency, capRewards, capReward);
        IRewards(capRewards).notifyRewardReceived(capReward);
    }

    function distributeFeesAllocation(
        address currency,
        uint256 amount
    ) external onlyOwner {
        // Contracts from Router
        address poolRewards = IRouter(router).getPoolRewards(currency);
        // Send poolShare to pool-currency rewards contract
        uint256 poolReward = (poolShare[currency] * amount) / 10 ** 4;
        _transferOut(currency, poolRewards, poolReward);
        IRewards(poolRewards).notifyRewardReceived(poolReward);
    }

    function notifyFeeReceived(
        address currency,
        uint256 amount
    ) external onlyTrading {
        // Contracts from Router
        address poolRewards = IRouter(router).getPoolRewards(currency);
        address capRewards = IRouter(router).getCapRewards(currency);

        // Send poolShare to pool-currency rewards contract
        uint256 poolReward = (poolShare[currency] * amount) / 10 ** 4;
        _transferOut(currency, poolRewards, poolReward);
        IRewards(poolRewards).notifyRewardReceived(poolReward);

        // Send capPoolShare to cap-currency rewards contract
        uint256 capReward = (capPoolShare[currency] * amount) / 10 ** 4;
        _transferOut(currency, capRewards, capReward);
        IRewards(capRewards).notifyRewardReceived(capReward);
    }

    function fundOracle(
        address destination,
        uint256 amount,
        address currency
    ) external onlyOracle {
        uint256 balance = IERC20(currency).balanceOf(address(this));
        require(balance > amount, "!balance");
        IERC20(currency).transfer(destination, amount);
    }

    function fundOracleViaEther(
        address destination,
        uint256 amount
    ) external onlyOracle {
        uint256 balance = address(this).balance;
        require(balance > amount, "!balance");
        payable(destination).sendValue(amount);
    }

    // To receive ETH
    fallback() external payable {}

    receive() external payable {}

    // Utils

    function _transferOut(
        address currency,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0 || currency == address(0) || to == address(0)) return;
        // adjust decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / UNIT;
        IERC20(currency).safeTransfer(to, amount);
    }

    // Getters

    function getPoolShare(address currency) external view returns (uint256) {
        return poolShare[currency];
    }

    function getCapShare(address currency) external view returns (uint256) {
        return capPoolShare[currency];
    }

    // Modifiers

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    modifier onlyTrading() {
        require(msg.sender == trading, "!trading");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "!oracle");
        _;
    }
}

