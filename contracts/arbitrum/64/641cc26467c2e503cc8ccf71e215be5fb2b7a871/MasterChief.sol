// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Peon.sol";
import "./IPeon.sol";
import "./IControllerInterface.sol";
import "./IRewardDistributorV3.sol";
import "./IiToken.sol";
import "./IDODOV2Proxy01.sol";
import "./ISwapRouter.sol";

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract MasterChief is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant DF = 0xaE6aab43C4f3E0cea4Ab83752C278f8dEbabA689;
    address public constant USX = 0x641441c631e2F909700d2f41FD87F0aA6A6b4EDb;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public constant CONTROLLER = 0x8E7e9eA9023B81457Ae7E6D2a51b003D421E5408;
    address public constant REWARD_DISTRIBUTOR = 0xF45e2ae152384D50d4e9b08b8A1f65F0d96786C3;
    address public constant I_USDC = 0x8dc3312c68125a94916d62B97bb5D925f84d4aE0;

    address public constant DODO_ROUTER = 0x88CBf433471A0CD8240D2a12354362988b4593E5;
    address public constant DODO_APPROVE = 0xA867241cDC8d3b0C07C85cC06F25a0cD3b5474d8;
    address public constant DODO_DF_USX_POOL = 0x19E5910F61882Ff6605b576922507F1E1A0302FE;
    address public constant DODO_USX_USDC_POOL = 0x9340e3296121507318874ce9C04AFb4492aF0284;

    uint256 public constant MAX_BPS = 10000;
    uint256 public constant TARGET_LTV = 8000;
    uint256 public constant LEVERAGE = 8;

    address public token;
    address public iToken;
    uint256 public aum = 0;
    uint256 public lastAmount = 0;

    /** proxioor **/

    function initialize(address _owner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        transferOwnership(_owner);

        token = USDC;
        iToken = I_USDC;

        address[] memory markets = new address[](1);
        markets[0] = iToken;
        IControllerInterface(CONTROLLER).enterMarkets(markets);

        IERC20Upgradeable(token).safeApprove(iToken, type(uint256).max);
        IERC20Upgradeable(DF).safeApprove(DODO_APPROVE, type(uint256).max);
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyOwner
    {}

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /** ownoor */

    function deposit(uint256 amount, bool mustHarvest) external onlyOwner nonReentrant {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        if (mustHarvest) {
            _harvest();
        }
        aum += amount;
        _leverage();
    }

    function withdraw() external onlyOwner nonReentrant {
        _harvest();
        _deleverage();
        aum = 0;
        lastAmount = 0;
        uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    }

    function supply(uint256 amount) external onlyOwner nonReentrant {
        _supply(amount);
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        _withdraw(amount);
    }

    function borrow(uint256 amount) external onlyOwner nonReentrant {
        _borrow(amount);
    }

    function repay(uint256 amount) external onlyOwner nonReentrant {
        _repay(amount);
    }

    function harvest() external onlyOwner nonReentrant returns (uint256) {
        return _harvest();
    }

    function getBalanceOfUnderlying() public onlyOwner returns (uint256) {
        return IiToken(iToken).balanceOfUnderlying(address(this));
    }

    function getBorrowBalanceCurrent() public onlyOwner returns (uint256) {
        return IiToken(iToken).borrowBalanceCurrent(address(this));
    }

    function rescueToken(address _token) external onlyOwner nonReentrant {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, IERC20Upgradeable(_token).balanceOf(address(this)));
    }

    function rescueNative() external onlyOwner nonReentrant {
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /** internaloor */

    function _supply(uint256 amount) internal {
        IiToken(iToken).mint(address(this), amount);
    }

    function _withdraw(uint256 amount) internal {
        IiToken(iToken).redeemUnderlying(address(this), amount);
    }

    function _borrow(uint256 amount) internal {
        IiToken(iToken).borrow(amount);
    }

    function _repay(uint256 amount) internal {
        IiToken(iToken).repayBorrow(amount);
    }

    function _leverage() internal {
        uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
        for (uint256 i = 0; i < LEVERAGE; i++) {
            _supply(amount);
            amount = amount * TARGET_LTV / MAX_BPS;
            _borrow(amount);
        }
        _supply(amount);
        lastAmount += amount;
    }

    function _deleverage() internal {
        uint256 amount = lastAmount;
        _withdraw(amount);
        for (uint256 i = 0; i < LEVERAGE; i++) {
            _repay(amount);
            amount = amount * MAX_BPS / TARGET_LTV;
            if (i == LEVERAGE - 1) {
                amount = getBalanceOfUnderlying() - (getBorrowBalanceCurrent() * MAX_BPS / TARGET_LTV);
            }
            _withdraw(amount);
        }
    }

    function _harvest() internal returns (uint256) {
        // Claim rewards
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        IRewardDistributorV3(REWARD_DISTRIBUTOR).claimAllReward(holders);

        // Swap rewards
        uint256 dfAmount = IERC20Upgradeable(DF).balanceOf(address(this)); 
        address[] memory dodoPool = new address[](2);
        dodoPool[0] = DODO_DF_USX_POOL;
        dodoPool[1] = DODO_USX_USDC_POOL;
        IDODOV2Proxy01(DODO_ROUTER).dodoSwapV2TokenToToken(DF, token, dfAmount, 1, dodoPool, 0, false, block.timestamp + 10);     

        // Compute target amounts
        uint256 targetAmount = aum;
        uint256 targetSupplyBalance = 0;
        uint256 targetBorrowBalance = 0;
        for (uint256 i = 0; i < LEVERAGE; i++) {
            targetSupplyBalance += targetAmount;
            targetAmount = targetAmount * TARGET_LTV / MAX_BPS;
            targetBorrowBalance += targetAmount;
        }
        targetSupplyBalance += targetAmount;

        // Repay debt interest
        uint256 debtInterest = getBorrowBalanceCurrent() - targetBorrowBalance;
        _repay(debtInterest);

        // Withdraw profit
        uint256 supplyProfit = getBalanceOfUnderlying() - targetSupplyBalance;
        _withdraw(supplyProfit);

        // Leverage
        uint256 netProfit = IERC20Upgradeable(token).balanceOf(address(this)); 
        aum += netProfit;
        _leverage();

        return getBorrowBalanceCurrent() * 10000 / (getBalanceOfUnderlying() - lastAmount);
    }

    /** fallbackoor **/

    receive() external payable {}
}

