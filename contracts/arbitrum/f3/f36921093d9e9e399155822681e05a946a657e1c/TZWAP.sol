// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
*                                                                                  
..................................................................            
.                                                                .            
.  ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::  .            
.  ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::  .            
.  ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::  .            
.  ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::  .            
.  ::::::::::::::::::::--:.......:-==--:...::==::::::::::::::::  .            
.  ::::::::::::::::::--.    .:::.:--+=::::::--::-::::::::::::::  .            
.  :::::::::::::::::+:    ::.    .:--+=-===:..:--=-::::::::::::  .            
.  :::::::::::::::--     ..     .:-----=--. .:-=-:---::::::::::  .            
.  ::::::::::::::-.      .-::::.:+=====-=::---===--.:-:::::::::  .            
.  :::::::::::::-.   ...:...::::==+===::+=:-:::===:-=-==-::::::  .            
.  ::::::::::::=:.  :..:    ...---=-:::--=-:-=--::..:---+-:::::  .            
.  :::::::::::=:.. .::---...#+*@%%@-...:-==--=+*@@#-.:-=+::::::  .            
.  ::::::::::--..........::-%%#@=.%#    --=--:@+@#.+.   +::::::  .            
.  ::::::::::=..........:--:.-=*#%@=   ..=-=:-@#%@%%:.:-=::::::  .            
.  :::::::::-+=--:...:-:....-=========--:-=+**+:....::=-:::::::  .            
.  ::::::::--+==-:::-:..:::::------::--:..:::.-:.  ::::=-::::::  .            
.  ::::::::= ---. .:::..::::::--:-==--:::--:... ..     :+=:::::  .            
.  :::::::-: .:-:.:=++=-:::::::--=---------:.. ... .:--:*#-::::  .            
.  ::::::-=..  ::..-----=-::::---:--=---==--:..:. :---=*#=:::::  .            
.  :::::-: -   ....::.   .:::::=*####*****++====--++*##%-::::::  .            
.  ::::-.   :::....:.     .::::::+######################+::::::  .            
.  :::-.    .------:::::::::======+####################+:::::::  .            
.  ::-#=.     --++=-:=:::::-======++++*****+++++++=--:=::::::::  .            
.  ::#@@@%+:  ::  .-==-----*====::--:::-::   .:.:...:-=::::::::  .            
.  :=@@@@@@@@#-   --:...--++=-+....:..-*=-....:-::::-%@%+::::::  .            
.  :%@@@@@@@@@:::...:-=+-:. .--::-::..:+=:.  :==-.:: @@@@@*-:::  .            
.  =@@@@@@@@@+. .:..---:...:=:*@@@@@@@@@@@@@@@@@@@@+.@@@@@@@+::  .            
.  %@@@@@@@@@:..  .::::--:..:%@@@@@@@@@@@@@@@@@@@@@@#@@@@@@@@#-  .            
.  @@@@@@@@%-      .:::.:=#@=:%@@@#-.  -=:-=+*%@@@@@@@@@@@@@@@@  .            
.  @@@@@@@@@..        :#@@@@@%-:+@@.   ..  =-+%@@@@@@@@@@@@@@@@. .            
.  @@@@@@@@@%:...     :@@@@@@@@@@@@@=  :.:%@@@@@@@@@@@@@@@@@@@@. .            
.  @@@@@@@@@@@%+-:-*#@@@@@@@@@@@@@@#-  .. -@@@@@@@@@@@@@@@@@@@@. .            
.  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%. :. #@@@@@@@@@@@@@@@@@@@@. .            
.                                                                .            
..................................................................            

            ████████╗███████╗██╗    ██╗ █████╗ ██████╗ 
            ╚══██╔══╝╚══███╔╝██║    ██║██╔══██╗██╔══██╗
              ██║     ███╔╝ ██║ █╗ ██║███████║██████╔╝
              ██║    ███╔╝  ██║███╗██║██╔══██║██╔═══╝ 
              ██║   ███████╗╚███╔███╔╝██║  ██║██║     
              ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝     
                                                      
                TZWAP: On-chain TWAP Service
*/
import "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IWETH9} from "./IWETH9.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";

contract TZWAP {

  using SafeERC20 for IERC20;

  address public owner;
  I1inchAggregationRouterV4 public aggregationRouterV4;
  IWETH9 public weth;

  // Min TWAP interval in seconds
  uint public minInterval = 60;

  // Min number of intervals for a TWAP order
  uint public minNumOfIntervals = 3;

  // Precision for all % math
  uint public percentagePrecision =  10 ** 3;
  // Min fees per TWAP order
  uint public minFees = 10; // 0.01%
  // Max fees per TWAP order
  uint public maxFees = 50 * percentagePrecision; // 50%

  // Auto-incrementing of orders
  uint public orderCount;
  // TWAP orders mapped to auto-incrementing ID
  mapping (uint => TWAPOrder) public orders;
  // Fills for TWAP orders
  mapping (uint => Fill[]) public fills;

  struct TWAPOrder {
    // Order creator
    address creator;
    // Token to swap from
    address srcToken;
    // Token to swap to
    address dstToken;
    // How often a swap should be made
    uint interval;
    // srcToken to swap per interval
    uint tickSize;
    // Total srcToken to swap
    uint total;
    // Fees in % to be paid per swap interval
    uint fees;
    // Creation timestamp
    uint created;
    // Toggled to true when an order is killed
    bool killed;
  }
  
  struct Fill {
    // Address that called fill
    address filler;
    // Amount of ticks filled
    uint ticksFilled;
    // Amount of srcToken spent
    uint srcTokensSwapped;
    // Amount of dstToken received
    uint dstTokensReceived;
    // Fees collected
    uint fees;
    // Time of last fill
    uint timestamp;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Sender must be owner");
    _;
  }

  event LogNewOrder(uint id);
  event LogNewFill(uint id, uint fillIndex);
  event LogOrderKilled(uint id);

  constructor(
    address payable _aggregationRouterV4Address,
    address payable _wethAddress
  ) {
    owner = msg.sender;
    aggregationRouterV4 = I1inchAggregationRouterV4(_aggregationRouterV4Address);
    weth = IWETH9(_wethAddress);
  }

  receive() external payable {}

  /**
  * Creates a new TWAP order
  * @param order Order params
  * @return Whether order was created
  */
  function newOrder(
    TWAPOrder memory order
  )
  payable
  public
  returns (bool) {
    require(order.srcToken != address(0), "Invalid srcToken address");
    require(order.dstToken != address(0), "Invalid dstToken address");
    require(order.interval >= minInterval, "Invalid interval");
    require(order.tickSize > 0, "Invalid tickSize");
    require(order.total > order.tickSize && order.total % order.tickSize == 0, "Invalid total");
    require(order.total / order.tickSize > minNumOfIntervals, "Number of intervals is too less");
    require(order.fees >= minFees && order.fees <= maxFees, "Invalid fees");
    order.creator = msg.sender;
    order.created = block.timestamp;
    order.killed = false;

    if (order.srcToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
      require(msg.value == order.total, "Invalid msg value");
      weth.deposit{value: msg.value}();
      order.srcToken = address(weth);
    }
    else {
      require(IERC20(order.srcToken).transferFrom(msg.sender, address(this), order.total));
    }

    orders[orderCount++] = order;
    emit LogNewOrder(orderCount - 1);

    return true;
  }

  /**
  * Fills an active order
  * @param id Order ID
  * @return Whether order was filled
  */
  function fillOrder(
    uint id,
    I1inchAggregationRouterV4.SwapDescription memory _desc,
    bytes calldata _data
  )
  public
  returns (bool) {
    require(orders[id].created != 0, "Invalid order");
    require(!orders[id].killed, "Order was killed");
    require(getSrcTokensSwappedForOrder(id) < orders[id].total, "Order is already filled");
    require(
      _desc.srcToken == orders[id].srcToken &&
      _desc.dstToken == orders[id].dstToken &&
      _desc.dstReceiver == address(this) &&
      _desc.amount == orders[id].tickSize,
      "Invalid router swap description"
    );
    
    uint timeElapsed;
    if (fills[id].length > 0) {
      timeElapsed = block.timestamp - fills[id][fills[id].length - 1].timestamp;
      require(timeElapsed > orders[id].interval, "Interval must pass before next fill");
    } else
      timeElapsed = block.timestamp - orders[id].created;

    uint ticksToFill = timeElapsed/orders[id].interval;
    uint timestamp = orders[id].created + (orders[id].interval * ticksToFill);

    fills[id].push(
      Fill({
        filler: msg.sender, 
        ticksFilled: ticksToFill, 
        srcTokensSwapped: 0, // Update after swap
        dstTokensReceived: 0, // Update after swap
        fees: 0, // Update after swapticksToFill * orders[id].tickSize * orders[id].fees / percentagePrecision,
        timestamp: timestamp
      })
    );

    _swap(id, _desc, _data);
    IERC20(orders[id].dstToken).transfer(
      msg.sender, 
      fills[id][fills[id].length - 1].fees
    );
    IERC20(orders[id].dstToken).transfer(
      orders[id].creator, 
      fills[id][fills[id].length - 1].dstTokensReceived - fills[id][fills[id].length - 1].fees
    );

    emit LogNewFill(id, fills[id].length - 1);

    return true;
  }

  /**
  * Execute 1-inch swap
  */
  function _swap(
    uint id,
    I1inchAggregationRouterV4.SwapDescription memory _desc,
    bytes calldata _data
  )
  internal {
    uint preSwapSrcTokenBalance = IERC20(orders[id].srcToken).balanceOf(address(this));
    (uint256 dstTokensReceived,) = aggregationRouterV4.swap(
      address(this),
      _desc,
      _data
    );

    uint srcTokensSwapped = preSwapSrcTokenBalance - IERC20(orders[id].srcToken).balanceOf(address(this));
    fills[id][fills[id].length - 1].srcTokensSwapped = srcTokensSwapped;
    fills[id][fills[id].length - 1].dstTokensReceived = dstTokensReceived;
    fills[id][fills[id].length - 1].fees = dstTokensReceived * orders[id].fees / percentagePrecision;
  }

  /**
  * Kills an active order
  * @param id Order ID
  * @return Whether order was killed
  */
  function killOrder(
    uint id
  )
  public
  returns (bool) {
    require(msg.sender == orders[id].creator, "Invalid sender");
    require(!orders[id].killed, "Order already killed");
    orders[id].killed = true;
    IERC20(orders[id].srcToken).transfer(
      orders[id].creator, 
      orders[id].total - getSrcTokensSwappedForOrder(id)
    );
    emit LogOrderKilled(id);
    return true;
  }

  /**
  * Returns total DST tokens received for an order
  * @param id Order ID
  * @return Total DST tokens received for an order
  */
  function getDstTokensReceivedForOrder(uint id)
  public
  view
  returns (uint) {
    require(orders[id].created != 0, "Invalid order");
    uint dstTokensReceived = 0;
    for (uint i = 0; i < fills[id].length; i++) 
      dstTokensReceived += fills[id][i].dstTokensReceived;
    return dstTokensReceived;
  }

  /**
  * Returns total SRC tokens received for an order
  * @param id Order ID
  * @return Total SRC tokens received for an order
  */
  function getSrcTokensSwappedForOrder(uint id)
  public
  view
  returns (uint) {
    require(orders[id].created != 0, "Invalid order");
    uint srcTokensSwapped = 0;
    for (uint i = 0; i < fills[id].length; i++) 
      srcTokensSwapped += fills[id][i].srcTokensSwapped;
    return srcTokensSwapped;
  }

  /**
  * Returns whether an order is active
  * @param id Order ID
  * @return Whether order is active
  */
  function isOrderActive(uint id) 
  public
  view
  returns (bool) {
    return orders[id].created != 0 && 
      !orders[id].killed && 
      getSrcTokensSwappedForOrder(id) < orders[id].total;
  }



}

