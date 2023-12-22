// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./IRouter.sol";
import "./IERC20.sol";
import "./console.sol";
import "./AutomationCompatible.sol";

import "./OwnableUpgradeable.sol";

contract FeeCollector is AutomationCompatibleInterface, OwnableUpgradeable {

  IRouter public router;

  mapping(address => IRouter.route[]) public routes;
  address public receiver;
  address public target;
  address public automationRegistry;
  address[] public tokens;
  mapping(address => uint256) public lastTrade;
  uint256 public interval;

  event Trade(address _token, uint256 _amount);
  event Error(address _token, uint256 _amount, bytes _error);

  constructor() {}

  function initialize(
    address _router, 
    address _receiver,
    address _target
  ) initializer public {
    __Ownable_init();
    router = IRouter(_router);
    receiver = _receiver;
    automationRegistry = address(0x75c0530885F385721fddA23C539AF3701d6183D4);
    interval = 86400;
    target = _target;
  }  

  function getPeriod() public view returns (uint256) {
      return (block.timestamp / interval) * interval;
  }

  function checkUpkeep(bytes memory /*checkdata*/) public view override returns (bool upkeepNeeded, bytes memory /*performData*/) {
    uint256 _period = getPeriod();
    for (uint256 i = 0; i < tokens.length; i++) {
      if (lastTrade[tokens[i]] < _period && IERC20(tokens[i]).balanceOf(address(this)) > 0) {
        upkeepNeeded = true;
        break;
      }
    }
  }

  function performUpkeep(bytes calldata /*performData*/) external override {
    require(msg.sender == automationRegistry || msg.sender == owner(), 'cannot execute');
    (bool upkeepNeeded, ) = checkUpkeep('0');
    require(upkeepNeeded, "condition not met");
    
    uint256 _period = getPeriod();
    address _token;
    for (uint256 i = 0; i < tokens.length; i++) {
      _token = tokens[i];
      if (lastTrade[_token] < _period) {
        lastTrade[_token] = _period;
        // perform trade
        if (IERC20(_token).balanceOf(address(this)) > 0) {
          address[] memory _tokenList = new address[](1);
          _tokenList[0] = _token;
          swapTokens(_tokenList);
        }
        break;
      }
    }
  }

  function setAutomationRegistry(address _automationRegistry) external onlyOwner {
      require(_automationRegistry != address(0));
      automationRegistry = _automationRegistry;
  }

  function setReceiver(address _receiver)
    external
    onlyOwner()
  {
    receiver = _receiver;
  }

  function clearLastTrade(address _token)
    external
    onlyOwner()
  {
    lastTrade[_token] = 0;
  }

  function removeToken(address _token) public onlyOwner {
    delete routes[_token];
    for (uint i = 0; i < tokens.length; i++) {
      if (tokens[i] == _token) {
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();
        break;
      }
    }
  }

  function setTokenMapping(address _token, IRouter.route[] calldata _routes)
    external
    onlyOwner()
  {
    require(_token != target, "Target token not allowed");
    require(_routes[_routes.length - 1].to == target, "Receive token should be target");
    removeToken(_token);

    for (uint8 i = 0; i < _routes.length; i++) {
      routes[_token].push(IRouter.route({from: _routes[i].from, to: _routes[i].to, stable: _routes[i].stable}));
    }

    if (_token != address(0)) {
      IERC20(_token).approve(address(router), type(uint).max);
    }
    tokens.push(_token);
  }

  // function approveERC20(address _token, uint256 _amount)
  //   external
  //   onlyOwner()
  // {
  //   IERC20(_token).approve(address(router), _amount);
  // }

  function swapTokens(address[] memory _tokens)
    public
  {
    for (uint8 i = 0; i < _tokens.length; i++) {
      if (_tokens[i] != address(0)) {
        uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
        if (balance > 0) {
          try router.getAmountsOut(balance, routes[_tokens[i]]) returns (uint[] memory amounts) { 
            uint amountOutMin = amounts[amounts.length - 1];
            try router.swapExactTokensForTokens(balance, amountOutMin, routes[_tokens[i]], address(this), block.timestamp) {
              emit Trade(tokens[i], balance);
            } catch Error(string memory reason) {
              // catch failing revert() and require()
              emit Error(tokens[i], balance, bytes(reason));
            } catch (bytes memory reason) {
                // catch failing assert()
              emit Error(tokens[i], balance, reason);
            }
          } catch Error(string memory reason) {

            console.log("here2");  
            // catch failing revert() and require()
            emit Error(tokens[i], balance, bytes(reason));
          } catch (bytes memory reason) {
              // catch failing assert()
            emit Error(tokens[i], balance, reason);
          }
        }
      } else {
        uint256 balance = address(this).balance;
        if (balance > 0) { 
          try router.getAmountsOut(balance, routes[_tokens[i]]) returns (uint[] memory amounts) { 
            uint amountOutMin = amounts[amounts.length - 1];
            try router.swapExactETHForTokens{value:balance}(amountOutMin, routes[_tokens[i]], address(this), block.timestamp) {
              emit Trade(tokens[i], balance);
            } catch Error(string memory reason) {
              // catch failing revert() and require()
              emit Error(tokens[i], balance, bytes(reason));
            } catch (bytes memory reason) {
                // catch failing assert()
              emit Error(tokens[i], balance, reason);
            }
          } catch Error(string memory reason) {
            // catch failing revert() and require()
            emit Error(tokens[i], balance, bytes(reason));
          } catch (bytes memory reason) {
              // catch failing assert()
            emit Error(tokens[i], balance, reason);
          }
        }
      }
    }
  }

  function withdraw() external {
    require(receiver != address(0), "Zero address not allowed");
    // TODO !!! transfer to BSC with LayerZero
    // TODO !!! transfer to BSC with LayerZero
    // TODO !!! transfer to BSC with LayerZero
    // address _token = IRewardsDistributor(receiver).token();
    // IERC20(_token).transfer(receiver, IERC20(_token).balanceOf(address(this)));
    // IRewardsDistributor(receiver).checkpoint_token();
    // IRewardsDistributor(receiver).checkpoint_total_supply();
  }

  function getRoutes(address _token)
    public
    view 
    returns (IRouter.route[] memory _routes)
  {
    _routes = routes[_token];
  }

  fallback() external payable {}

  receive() external payable {}
}
