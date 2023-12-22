// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./ERC20BurnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

//import gmx interfaces
import "./IExchangeRouter.sol";
import "./IDepositCallbackReceiver.sol";
import "./IWithdrawalCallbackReceiver.sol";
import "./IOracle.sol";
//import hardhat console
import "./console.sol";

contract TestGMX is IDepositCallbackReceiver, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public depositVault;
    address public withdrawalVault;
    address public router;
    address public exchangeRouter;
    address public depositHandler;
    address public gmxasset;
    address public weth;

    uint256 public longTokenAmount;
    uint256 public shortTokenAmount;
    uint256 public receivedMarketTokens;
    int256 public receivedMarketTokens2;
    uint256 public outputAmount;
    uint256 public secondaryOutputAmount;
    address public usdc;

    //add event for afterDepositExecution
    event AfterDepositExecution(uint256 receivedMarketTokens2, bytes32 key, Deposit.Props deposit, EventUtils.EventLogData eventData);

    function initialize() external initializer {
        depositVault = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
        router = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
        exchangeRouter = 0x3B070aA6847bd0fB56eFAdB351f49BBb7619dbc2;
        depositHandler = 0xD9AebEA68DE4b4A3B58833e1bc2AEB9682883AB0;
        gmxasset = 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4;
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        withdrawalVault = 0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55;
        usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

        __Ownable_init();
    }

    function openPosition(uint256 _usdcAmount, address _inputAsset, IExchangeRouter.CreateDepositParams memory params) external payable onlyOwner {
        IERC20Upgradeable(_inputAsset).transferFrom(msg.sender, address(this), _usdcAmount);
        IERC20Upgradeable(_inputAsset).approve(router, _usdcAmount);

        IExchangeRouter(exchangeRouter).sendTokens(_inputAsset, depositVault, _usdcAmount);

        IExchangeRouter(exchangeRouter).sendWnt{ value: msg.value }(depositVault, msg.value);
        IExchangeRouter(exchangeRouter).createDeposit(params);
    }

    function takeAll(address _inputSsset, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, _amount);
    }

    function withdrawGMXMarket(address gmToken, uint256 amount, IExchangeRouter.CreateWithdrawalParams calldata params) public payable returns (bytes32 key) {
        //transfer gmxMarket to this contract
        // IERC20Upgradeable(gmToken).transferFrom(msg.sender, address(this), amount);
        IERC20Upgradeable(gmToken).approve(router, amount);

        IExchangeRouter(exchangeRouter).sendWnt{ value: msg.value }(withdrawalVault, msg.value);

        IExchangeRouter(exchangeRouter).sendTokens(gmToken, withdrawalVault, amount);

        IExchangeRouter(exchangeRouter).createWithdrawal(params);

        return (key);
    }

    function afterDepositExecution(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {
        // longTokenAmount = eventData.uintItems.items[0].value;
        // shortTokenAmount = eventData.uintItems.items[1].value;
        receivedMarketTokens = eventData.uintItems.items[0].value;

        IERC20Upgradeable(0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4).transfer(owner(), receivedMarketTokens);

        emit AfterDepositExecution(receivedMarketTokens, key, deposit, eventData);
    }

    // @dev called after a deposit cancellation
    // @param key the key of the deposit
    // @param deposit the deposit that was cancelled
    function afterDepositCancellation(bytes32 key, Deposit.Props memory deposit, EventUtils.EventLogData memory eventData) external {}

    function afterWithdrawalExecution(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external {
        outputAmount = eventData.uintItems.items[0].value;
        secondaryOutputAmount = eventData.uintItems.items[1].value;
    }

    function afterWithdrawalCancellation(bytes32 key, Withdrawal.Props memory withdrawal, EventUtils.EventLogData memory eventData) external {}

    function getGmTokenPrice(address oracle, address _token) public view returns (Props memory price) {
        price = IOracle(oracle).getPrimaryPrice(_token);
    }

    //receive function to receive eth
    receive() external payable {}
}

