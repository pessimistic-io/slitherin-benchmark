// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./ITradingStorage.sol";
import "./TokenInterface.sol";
import "./Aggregator.sol";


contract OrderExecutionTokenManagement {
  using SafeERC20 for IERC20;

    uint256 constant public DIVIDER = 10000;

    enum OpenLimitOrderType{ LEGACY, REVERSAL, MOMENTUM }

    ITradingStorage public storageT;
    TokenInterface public linkToken;
    ISwapRouter public uniswapV3Router;
    IChainlinkFeed public linkPriceFeed;
    address public aggregator;
    address public openPnlFeed;

    address[] public swapPathIntermediate;
    uint24[] public poolsFees;

    uint256 public minLinkBalanceContract;
    uint256 public increaseInStableBalanceAmount;
    uint256 public priceImpact;
    uint256 public stalePriceDelay;

    mapping(address => mapping(uint256 => mapping(uint256 => OpenLimitOrderType))) public openLimitOrderTypes;

    error OrderTokenManagementWrongParameters();
    error OrderTokenManagementInvalidGovAddress(address account);
    error OrderTokenManagementInvalidTradingContract(address account);
    error OrderTokenManagementInvalidCallbacksContract(address account);
    error OrderTokenManagementInvalidOpenPnlFeed(address account);
    error OrderTokenManagementInvalidAddress(address account);
    error OrderTokenManagementInvalidOraclePrice();

    modifier onlyGov() {
      if (msg.sender != storageT.gov()) {
        revert OrderTokenManagementInvalidGovAddress(msg.sender);
      }
      _;
    }

    modifier onlyCallbacks() {
      if (msg.sender != storageT.callbacks()) {
        revert OrderTokenManagementInvalidCallbacksContract(msg.sender);
      }
      _;
    }

    modifier onlyTrading() {
      if (msg.sender != storageT.trading()) {
        revert OrderTokenManagementInvalidTradingContract(msg.sender);
      }
      _;
    }

    modifier onlyOpenPnlFeed(){ 
      if (msg.sender != openPnlFeed) {
        revert OrderTokenManagementInvalidOpenPnlFeed(msg.sender);
      }
      _; 
    }


    constructor(
      ITradingStorage _storageT,
      TokenInterface _linkToken,
      ISwapRouter _router,
      address[] memory _swapPathIntermediate,
      uint24[] memory _poolsFees,
      uint256 _minLinkBalanceContract,
      uint256 _increaseInStableBalanceAmount
    ) {
      if (address(_storageT) == address(0) ||
        address(_linkToken) == address(0) ||
        address(_router) == address(0) ||
        _swapPathIntermediate.length >= 3 ||
        _poolsFees.length != _swapPathIntermediate.length + 1) {
        revert OrderTokenManagementWrongParameters();
      }
      storageT = _storageT;
      linkToken = _linkToken;
      uniswapV3Router = _router;
      swapPathIntermediate = _swapPathIntermediate;
      poolsFees = _poolsFees;
      minLinkBalanceContract = _minLinkBalanceContract;
      increaseInStableBalanceAmount = _increaseInStableBalanceAmount;
    }

    function setOpenLimitOrderType(address _trader, uint256 _pairIndex, uint256 _index, OpenLimitOrderType _type) external onlyTrading{
      openLimitOrderTypes[_trader][_pairIndex][_index] = _type;
    }


    function setminLinkBalanceContract(uint256 _minBalance) external onlyGov returns (bool) {
        minLinkBalanceContract = _minBalance;
        return true;
    }

    function setincreaseInStableBalanceAmount(uint256 _amount) external onlyGov returns (bool) {
        increaseInStableBalanceAmount = _amount;
        return true;
    }

    function setStorage(address _storage) external onlyGov returns (bool) {
      if (_storage == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      storageT = ITradingStorage(_storage);
      return true;
    }

    function setLinkToken(address _linkToken) external onlyGov returns (bool) {
      if (_linkToken == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      linkToken = TokenInterface(_linkToken);
      return true;
    }

    function setLinkPriceFeed(address _linkPriceFeed) external onlyGov returns (bool) {
      if (_linkPriceFeed == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      linkPriceFeed = IChainlinkFeed(_linkPriceFeed);
      return true;
    }
    
    function setAggregator(address _aggregator) external onlyGov returns (bool) {
      if (_aggregator == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      aggregator = _aggregator;
      return true;
    }

    function setOpenPnlFeed(address _openPnlFeed) external onlyGov returns (bool) {
      if (_openPnlFeed == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      openPnlFeed = _openPnlFeed;
      return true;
    }

    function setRouter(address _router) external onlyGov returns (bool) {
      if (_router == address(0)) revert OrderTokenManagementInvalidAddress(address(0));
      uniswapV3Router = ISwapRouter(_router);
      return true;
    }

    function setPriceImpact(uint256 _priceImpact) external onlyGov returns (bool) {
      if (_priceImpact > DIVIDER) revert OrderTokenManagementWrongParameters();
      priceImpact = _priceImpact;
      return true;
    }

    function setStalePriceDelay(uint256 _stalePriceDelay) external onlyGov returns (bool) {
      if (_stalePriceDelay < 1 hours) revert OrderTokenManagementWrongParameters();
      stalePriceDelay = _stalePriceDelay;
      return true;
    }

    function updateSwapPathIntermediate(address[] memory _path) external onlyGov returns (bool) {
        _updateSwapPathIntermediate(_path);
        return true;
    }

    function updatePoolsFees(uint24[] memory _fees) external onlyGov returns (bool) {
        _updatePoolsFees(_fees);
        return true;
    }

    function addAggregatorFund() external onlyCallbacks returns (uint256 amountOut) {
      uint256 aggregatorBalance = checkAggregatorLinkBalance();
      if (aggregator != address(0) && aggregatorBalance < minLinkBalanceContract) {

        uint256 balanceOfThisContract = storageT.stable().balanceOf(address(this));

        uint256 amountIn = increaseInStableBalanceAmount > balanceOfThisContract 
          ? balanceOfThisContract 
          : increaseInStableBalanceAmount;

        if ((poolsFees.length != swapPathIntermediate.length + 1) || swapPathIntermediate.length >= 3) revert OrderTokenManagementWrongParameters();
        address stable = address(storageT.stable());
        bytes memory pathParams;

        if (swapPathIntermediate.length == 0) {
          pathParams = abi.encodePacked(stable, poolsFees[0], address(linkToken));
        } else if (swapPathIntermediate.length == 1) {
          pathParams = abi.encodePacked(stable, poolsFees[0], swapPathIntermediate[0], poolsFees[1], address(linkToken));
        } else {
          pathParams = abi.encodePacked(stable, poolsFees[0], swapPathIntermediate[0], poolsFees[1], swapPathIntermediate[1], poolsFees[2], address(linkToken));
        }

        TransferHelper.safeApprove(stable, address(uniswapV3Router), amountIn);

        uint256 amountOutMin = estimateLinkAmount(amountIn) * (DIVIDER - priceImpact) / DIVIDER;

        ISwapRouter.ExactInputParams memory params =
          ISwapRouter.ExactInputParams({
            path: pathParams,
            recipient: aggregator,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
          });

        amountOut = uniswapV3Router.exactInput(params);
      }
    }

    function addOpenPnlFeedFund() external onlyOpenPnlFeed returns (uint256 amountOut) {
      uint256 openPnlFeedBalance = checkOpenPnlFeedLinkBalance();
      if (openPnlFeed != address(0) && openPnlFeedBalance < minLinkBalanceContract) {

        uint256 balanceOfThisContract = storageT.stable().balanceOf(address(this));

        uint256 amountIn = increaseInStableBalanceAmount > balanceOfThisContract 
          ? balanceOfThisContract 
          : increaseInStableBalanceAmount;

        if ((poolsFees.length != swapPathIntermediate.length + 1) || swapPathIntermediate.length >= 3) revert OrderTokenManagementWrongParameters();
        address stable = address(storageT.stable());
        bytes memory pathParams;

        if (swapPathIntermediate.length == 0) {
          pathParams = abi.encodePacked(stable, poolsFees[0], address(linkToken));
        } else if (swapPathIntermediate.length == 1) {
          pathParams = abi.encodePacked(stable, poolsFees[0], swapPathIntermediate[0], poolsFees[1], address(linkToken));
        } else {
          pathParams = abi.encodePacked(stable, poolsFees[0], swapPathIntermediate[0], poolsFees[1], swapPathIntermediate[1], poolsFees[2], address(linkToken));
        }

        TransferHelper.safeApprove(stable, address(uniswapV3Router), amountIn);

        uint256 amountOutMin = estimateLinkAmount(amountIn) * (DIVIDER - priceImpact) / DIVIDER;

        ISwapRouter.ExactInputParams memory params =
          ISwapRouter.ExactInputParams({
            path: pathParams,
            recipient: openPnlFeed,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
          });

        amountOut = uniswapV3Router.exactInput(params);
      }
    }

    function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyGov returns (bool) {
        _token.safeTransfer(_to, _amount);
        return true;
    }

    function checkAggregatorLinkBalance() public view returns (uint256) {
        return linkToken.balanceOf((aggregator));
    }

    function checkOpenPnlFeedLinkBalance() public view returns (uint256) {
        return linkToken.balanceOf((openPnlFeed));
    }

    function estimateLinkAmount(uint256 _amountStableIn) private view returns (uint256 amountOut) {
      if (address(linkPriceFeed) != address(0)) {
        (, int256 answer, , uint256 updatedAt, ) = linkPriceFeed.latestRoundData();
        if (answer < 0 || block.timestamp - updatedAt > stalePriceDelay) revert OrderTokenManagementInvalidOraclePrice();
        uint256 feedPrice = uint256(answer);
        amountOut = _amountStableIn * 1e18 * 1e8 / (feedPrice * 1e6);
      }
    }

    function _updateSwapPathIntermediate(address[] memory _path) private {
      swapPathIntermediate = _path;
    }

    function _updatePoolsFees(uint24[] memory _fees) private {
      poolsFees = _fees;
    }

}

